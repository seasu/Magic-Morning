import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

admin.initializeApp();

const db = admin.firestore();
const geminiApiKey = defineSecret("GEMINI_API_KEY");

// ── generateStickerSpecs ────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. Firestore Transaction 原子性扣 1 點
// 3. 呼叫 Gemini 2.0 Flash（文字）取得 8 組貼圖規格
// 4. 回傳 specs + remainingCredits

export const generateStickerSpecs = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const {photoBase64} = request.data as {photoBase64: string};

    if (!photoBase64) {
      throw new HttpsError("invalid-argument", "photoBase64 is required.");
    }

    // ── 原子性扣點 ──────────────────────────────────────────────────────────
    const userRef = db.collection("users").doc(uid);
    let remainingCredits = 0;

    const deducted = await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      const credits = (doc.data()?.credits as number) ?? 0;
      if (credits <= 0) return false;
      remainingCredits = credits - 1;
      tx.update(userRef, {
        credits: remainingCredits,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!deducted) {
      throw new HttpsError("resource-exhausted", "Insufficient credits.");
    }

    // ── 呼叫 Gemini 文字 API ────────────────────────────────────────────────
    const apiKey = geminiApiKey.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta" +
      `/models/gemini-2.0-flash-lite:generateContent?key=${apiKey}`;

    const body = {
      contents: [
        {
          parts: [
            {
              text:
                "你是一位創意 LINE 貼圖設計師，擅長根據照片人物的個性與氛圍，" +
                "設計出最適合的貼圖情感組合。\n\n" +
                "請仔細觀察照片中人物的外型、氣質、表情與場景，" +
                "為他們設計專屬的 8 張 LINE 貼圖規格。\n\n" +
                "每張貼圖請【自由發揮】，無需使用固定情感模板。" +
                "可以根據人物特色選擇有趣、幽默、溫馨或獨特的情感表達。\n\n" +
                "輸出格式：僅回傳 JSON 陣列（8 個物件），每個物件包含：\n" +
                '- "text": 繁體中文標語（2–6 字，口語化有趣，適合貼圖）\n' +
                '- "emotion": 英文情感描述（用於繪製卡通表情）\n' +
                '- "bgColor": 背景色描述（英文色名 + hex，例如 "coral red #FF6B6B"）\n\n' +
                "範例格式（不要照抄，請根據照片創作）：\n" +
                '[{"text":"哈囉！","emotion":"cheerfully waving hello","bgColor":"warm peach #F4A261"}]',
            },
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: photoBase64,
              },
            },
          ],
        },
      ],
    };

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(50000),
    });

    if (!res.ok) {
      const errText = await res.text();
      // 扣點已成功，但 AI 失敗 → 退還 1 點
      await userRef.update({
        credits: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError(
        "internal",
        `Gemini text API error ${res.status}: ${errText.slice(0, 300)}`
      );
    }

    const json = (await res.json()) as {
      candidates: Array<{content: {parts: Array<{text?: string}>}}>;
    };

    const text = json.candidates?.[0]?.content?.parts
      ?.map((p) => p.text ?? "")
      .join("") ?? "";

    const match = text.match(/\[[\s\S]*\]/);
    if (!match) {
      // 退還點數
      await userRef.update({
        credits: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("internal", "Invalid Gemini response format.");
    }

    const specs = JSON.parse(match[0]) as unknown[];
    if (!Array.isArray(specs) || specs.length < 8) {
      await userRef.update({
        credits: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw new HttpsError("internal", "Gemini returned fewer than 8 specs.");
    }

    return {specs: specs.slice(0, 8), remainingCredits};
  }
);

// ── generateStickerImage ────────────────────────────────────────────────────
//
// 不扣點（點數在 generateStickerSpecs 時已扣）
// 只驗證登入，然後 proxy Gemini Image API

export const generateStickerImage = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const {photoBase64, prompt} = request.data as {
      photoBase64: string;
      prompt: string;
    };

    if (!photoBase64 || !prompt) {
      throw new HttpsError(
        "invalid-argument",
        "photoBase64 and prompt are required."
      );
    }

    const apiKey = geminiApiKey.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta" +
      `/models/gemini-2.5-flash-preview-05-20:generateContent?key=${apiKey}`;

    const body = {
      contents: [
        {
          parts: [
            {text: prompt},
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: photoBase64,
              },
            },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ["IMAGE", "TEXT"],
      },
    };

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(110000),
    });

    if (res.status === 429) {
      const retryAfter = res.headers.get("Retry-After") ?? "30";
      throw new HttpsError(
        "resource-exhausted",
        `Rate limited. Retry after ${retryAfter}s.`
      );
    }

    if (!res.ok) {
      const errText = await res.text();
      throw new HttpsError(
        "internal",
        `Gemini image API error ${res.status}: ${errText.slice(0, 300)}`
      );
    }

    const json = (await res.json()) as {
      candidates: Array<{
        content: {
          parts: Array<{
            inlineData?: {mimeType: string; data: string};
          }>;
        };
      }>;
    };

    const parts = json.candidates?.[0]?.content?.parts ?? [];
    for (const part of parts) {
      if (part.inlineData?.mimeType?.startsWith("image/")) {
        return {imageBase64: part.inlineData.data};
      }
    }

    throw new HttpsError("internal", "No image returned by Gemini.");
  }
);
