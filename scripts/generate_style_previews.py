#!/usr/bin/env python3
"""
generate_style_previews.py
──────────────────────────
使用 Gemini image generation 將貓咪來源圖片
轉換為 6 種風格 × 16 種情感 = 96 張示意圖，儲存到 assets/images/。

命名格式：preview_{style}_{emotionId}.png
例如：preview_chibi_greeting.png、preview_pixel_angry.png

Prompt 格式與 App 實際產圖（_buildSinglePrompt）完全一致，
確保示意圖呈現效果與正式貼圖相符。

使用方法：
  1. 確認來源圖片存在：assets/images/cat_source.png
  2. 設定 API Key：
       export GEMINI_API_KEY="your_key_here"
  3. 安裝依賴：
       pip3 install google-genai pillow
  4. 執行：
       cd /path/to/Magic-Sticker
       python3 scripts/generate_style_previews.py

  可選：只生成特定組合（加速測試）
       python3 scripts/generate_style_previews.py --styles chibi pixel --emotions greeting happy
       python3 scripts/generate_style_previews.py --skip-existing
"""

import os
import sys
import base64
import argparse
from pathlib import Path

# ── 路徑設定 ─────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_DIR / "assets" / "images"
SOURCE_IMAGE = ASSETS_DIR / "cat_source.png"

# ── 風格定義（與 StickerStyle enum 同步）─────────────────────────────────────
# characterDesc 與 promptSuffix 直接對應 lib/core/models/sticker_style.dart

STYLES = {
    "chibi": {
        "label": "Q版卡通",
        "characterDesc": (
            "Cartoon chibi-style face of the person (cute Q-version)\n"
            "  * Big sparkly eyes, small nose, chubby cheeks\n"
            "  * Clean flat illustration, thick black outlines, no photo-realism\n"
            "  * Face and upper body fill the circle naturally"
        ),
        "promptSuffix": "LINE Friends / Chiikawa quality.",
    },
    "popArt": {
        "label": "普普風",
        "characterDesc": (
            "Pop Art portrait inspired by the person in the photo\n"
            "  * Bold simplified face features, vivid high-contrast colors\n"
            "  * Thick black outlines, flat colored areas, Ben-Day dot shading\n"
            "  * Andy Warhol / Roy Lichtenstein aesthetic"
        ),
        "promptSuffix": (
            "Pop Art style — bold black outlines, vivid flat colors, Ben-Day dot "
            "shading, no gradients. Andy Warhol / Roy Lichtenstein aesthetic."
        ),
    },
    "pixel": {
        "label": "像素風",
        "characterDesc": (
            "Pixel art sprite of the person's face\n"
            "  * Chunky pixels visible (≥4 px grid), limited palette (≤16 colors)\n"
            "  * Simple large eyes, blocky rounded shapes\n"
            "  * No anti-aliasing; Nintendo / SNES game sprite aesthetic"
        ),
        "promptSuffix": (
            "Retro 8-bit pixel art style — large visible pixels (≥4 px grid), "
            "limited palette (≤16 colors), no anti-aliasing. "
            "Nintendo / SNES sprite aesthetic."
        ),
    },
    "sketch": {
        "label": "素描",
        "characterDesc": (
            "Pencil sketch portrait of the person\n"
            "  * Hand-drawn lines capturing the likeness from the photo\n"
            "  * Crosshatching for depth and shading, rough expressive strokes\n"
            "  * Monochrome or sepia tones"
        ),
        "promptSuffix": (
            "Pencil sketch / hand-drawn style — monochrome or sepia tones, "
            "visible pencil strokes and crosshatching for shadows, "
            "rough and expressive line quality."
        ),
    },
    "watercolor": {
        "label": "水彩",
        "characterDesc": (
            "Watercolor painting portrait of the person\n"
            "  * Soft rounded face with gentle color washes that bleed at edges\n"
            "  * Translucent layered colors, slight paper texture visible\n"
            "  * Dreamy, cute watercolor quality"
        ),
        "promptSuffix": (
            "Soft watercolor painting style — gentle color washes bleeding at edges, "
            "translucent layered colors, slight paper texture. "
            "Cute and dreamy watercolor quality."
        ),
    },
    "photo": {
        "label": "寫實風",
        "characterDesc": (
            "Photo-realistic portrait of the person\n"
            "  * Faithful likeness with natural skin tones and sharp features\n"
            "  * Clean, well-lit portrait composition\n"
            "  * Smooth edges, vibrant colours, professional headshot quality\n"
            "  * Subject extracted from background — transparent BG preferred"
        ),
        "promptSuffix": (
            "Photo-realistic style — natural colours, sharp facial features, "
            "professional portrait lighting. "
            "High fidelity; maintain the authentic appearance of the person."
        ),
    },
}

# ── 情感定義（與 kEmotionCategories + _kFallbackSpecs 同步）──────────────────
# emotion 對應 StickerSpec.emotion（promptHint），bgColor 對應預設配色

EMOTIONS = {
    "greeting": {
        "label": "打招呼",
        "emotion": "cheerfully waving hello",
        "bgColor": "warm peach #F4A261",
    },
    "praise": {
        "label": "讚美",
        "emotion": "excited thumbs-up with sparkles",
        "bgColor": "sky blue #74C0FC",
    },
    "surprise": {
        "label": "驚訝",
        "emotion": "shocked wide eyes, question marks",
        "bgColor": "golden yellow #FFD43B",
    },
    "awkward": {
        "label": "尷尬",
        "emotion": "embarrassed blushing, sweat drop",
        "bgColor": "soft pink #FFB3C6",
    },
    "angry": {
        "label": "生氣",
        "emotion": "angry frowning with flames",
        "bgColor": "deep red #FF6B6B",
    },
    "happy": {
        "label": "開心",
        "emotion": "joyful laughing, rainbow confetti",
        "bgColor": "mint green #63E6BE",
    },
    "thinking": {
        "label": "思考",
        "emotion": "thoughtful chin-rubbing, thought bubble",
        "bgColor": "lavender #C084FC",
    },
    "farewell": {
        "label": "道別",
        "emotion": "waving goodbye with sunglasses",
        "bgColor": "baby blue #ADE8F4",
    },
    "shy": {
        "label": "害羞",
        "emotion": "shy blushing, covering face gently",
        "bgColor": "blush pink #FFD6E0",
    },
    "cool": {
        "label": "得意",
        "emotion": "smug cool confident sunglasses expression",
        "bgColor": "electric blue #339AF0",
    },
    "tired": {
        "label": "疲倦",
        "emotion": "tired droopy eyes, yawning heavily",
        "bgColor": "warm grey #CED4DA",
    },
    "cry": {
        "label": "哭泣",
        "emotion": "crying tears flowing dramatically",
        "bgColor": "light blue #A5D8FF",
    },
    "love": {
        "label": "愛心",
        "emotion": "loving warm smile, heart eyes, rosy cheeks",
        "bgColor": "rose #FF8FAB",
    },
    "excited": {
        "label": "興奮",
        "emotion": "star-struck excitement, jumping with joy",
        "bgColor": "bright orange #FF922B",
    },
    "scared": {
        "label": "害怕",
        "emotion": "terrified wide eyes, trembling in fear",
        "bgColor": "pale purple #E5DBFF",
    },
    "mischief": {
        "label": "調皮",
        "emotion": "playful mischievous wink, sticking out tongue",
        "bgColor": "lime green #94D82D",
    },
}

# ─────────────────────────────────────────────────────────────────────────────


def build_prompt(style_key: str, emotion_key: str) -> str:
    """使用與 App _buildSinglePrompt（圓形模式）完全相同的格式。"""
    style = STYLES[style_key]
    emotion = EMOTIONS[emotion_key]
    return (
        "You are a professional LINE sticker illustrator. "
        "Draw ONE single circular sticker based on the person's face in the reference photo.\n\n"
        "DESIGN REQUIREMENTS:\n"
        "- A single large filled perfect circle, centered, occupying ~95% of the square canvas (nearly edge-to-edge)\n"
        "- The circle must be geometrically perfect (equal width and height)\n"
        f"- Circle background color: {emotion['bgColor']}\n"
        f"- Character expression / pose: {emotion['emotion']}\n"
        f"- {style['characterDesc']}\n"
        "- DO NOT draw any text or letters inside the image\n"
        "- 3–5 small sparkles / stars scattered inside the circle\n"
        "- NO white outline, NO white border around the circle\n"
        "- The area outside the circle must be completely transparent (alpha = 0), no fill at all\n\n"
        "OUTPUT: A single square PNG (equal width and height) with a transparent background "
        "outside the circle, containing exactly this ONE circular sticker.\n"
        f"STYLE: {style['promptSuffix']}\n"
    )


def load_source_image() -> bytes:
    if not SOURCE_IMAGE.exists():
        print(f"❌ 找不到來源圖片：{SOURCE_IMAGE}")
        print("   請將貓咪圖片存成 assets/images/cat_source.png 後再執行")
        sys.exit(1)
    with open(SOURCE_IMAGE, "rb") as f:
        return f.read()


def generate_image(client, types, image_model: str, source_b64: str, prompt: str) -> bytes | None:
    try:
        response = client.models.generate_content(
            model=image_model,
            contents=[
                types.Content(
                    role="user",
                    parts=[
                        types.Part(
                            inline_data=types.Blob(
                                mime_type="image/png",
                                data=source_b64,
                            )
                        ),
                        types.Part(text=prompt),
                    ],
                )
            ],
            config=types.GenerateContentConfig(
                response_modalities=["image"],
                temperature=1.0,
            ),
        )
        for part in response.candidates[0].content.parts:
            if part.inline_data is not None:
                data = part.inline_data.data
                return data if isinstance(data, bytes) else base64.b64decode(data)
        return None
    except Exception as e:
        print(f"   ⚠️  失敗: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="產生 style×emotion 示意圖")
    parser.add_argument("--styles", nargs="+", choices=list(STYLES.keys()),
                        help="只產生指定風格（預設全部）")
    parser.add_argument("--emotions", nargs="+", choices=list(EMOTIONS.keys()),
                        help="只產生指定情感（預設全部）")
    parser.add_argument("--skip-existing", action="store_true",
                        help="跳過已存在的圖片")
    args = parser.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("❌ 請設定環境變數 GEMINI_API_KEY")
        print("   export GEMINI_API_KEY='your_api_key_here'")
        sys.exit(1)

    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("📦 安裝 google-genai...")
        os.system("pip3 install google-genai -q")
        from google import genai
        from google.genai import types

    image_model = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
    client = genai.Client(api_key=api_key)

    styles_to_gen = args.styles or list(STYLES.keys())
    emotions_to_gen = args.emotions or list(EMOTIONS.keys())
    total = len(styles_to_gen) * len(emotions_to_gen)

    print("🐱 Magic Sticker — Style×Emotion 示意圖產生器")
    print(f"   風格：{styles_to_gen}")
    print(f"   情感：{emotions_to_gen}")
    print(f"   總計：{total} 張")
    print(f"   來源：{SOURCE_IMAGE}")
    print(f"   輸出：{ASSETS_DIR}")
    print()

    source_bytes = load_source_image()
    source_b64 = base64.b64encode(source_bytes).decode()
    print(f"✅ 已載入來源圖片（{len(source_bytes) / 1024:.0f} KB）\n")

    success_count = 0
    skipped_count = 0
    count = 0

    for style_key in styles_to_gen:
        style_info = STYLES[style_key]
        for emotion_key in emotions_to_gen:
            emotion_info = EMOTIONS[emotion_key]
            count += 1
            out_path = ASSETS_DIR / f"preview_{style_key}_{emotion_key}.png"

            if args.skip_existing and out_path.exists():
                print(f"   ⏭️  [{count}/{total}] {style_key}×{emotion_key} 已存在，跳過")
                skipped_count += 1
                continue

            print(f"🎨 [{count}/{total}] {style_info['label']} × {emotion_info['label']} ({style_key}×{emotion_key})...")
            prompt = build_prompt(style_key, emotion_key)
            data = generate_image(client, types, image_model, source_b64, prompt)

            if data:
                out_path.write_bytes(data)
                print(f"   ✅ {out_path.name} ({len(data) // 1024} KB)")
                success_count += 1
            else:
                print(f"   ❌ {style_key}×{emotion_key} 產生失敗，跳過")

    generated = total - skipped_count
    print(f"\n🎉 完成！成功 {success_count}/{generated} 張（跳過 {skipped_count} 張）")

    if success_count < generated:
        print("\n💡 失敗可能原因：")
        print("   - API Key 無效或額度用盡")
        print("   - Gemini image generation 模型尚未開放")
        print("   - 請至 https://aistudio.google.com 確認帳號狀態")


if __name__ == "__main__":
    main()
