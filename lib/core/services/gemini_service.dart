import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'firebase_service.dart';

const _kFallbackTexts = [
  '哈囉！', '太棒了！', '真的嗎？', '尷尬了...',
  '哼！', '開心！', '我想想...', '再見囉！',
];

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  /// 依照照片內容，生成 8 組符合情境的 LINE 貼圖短文字（2–6 字）
  ///
  /// 回傳長度固定為 8；API 失敗或逾時（10 秒）時自動使用 Fallback。
  /// 主要作為 AI 圖生成失敗時的 fallback 文字標籤。
  Future<List<String>> generateStickerTexts(Uint8List imageBytes) async {
    FirebaseService.log('GeminiService.generateStickerTexts: start');
    try {
      final response = await _model.generateContent([
        Content.multi([
          TextPart(
            '你是 LINE 貼圖文字設計師。\n'
            '請根據這張照片的人物氛圍，產出 8 組繁體中文短文字作為貼圖情感標語，格式如下：\n'
            '- 每組 2–6 字，口語化、有趣、適合貼圖\n'
            '- 涵蓋 8 種情感：打招呼、讚美、驚訝、尷尬、生氣、開心、思考、道別\n'
            '- 禁止重複\n'
            '- 僅回傳 JSON 陣列（8 個元素），例如：["哈囉！","太棒了！","真的嗎？","尷尬了...","哼！","開心！","我想想...","再見囉！"]',
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 10));

      final raw = response.text ?? '';
      final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(raw);
      if (match != null) {
        final list = (jsonDecode(match.group(0)!) as List).cast<String>();
        if (list.length >= 8) {
          FirebaseService.log('GeminiService.generateStickerTexts: done');
          await FirebaseAnalytics.instance.logEvent(name: 'ai_text_generated');
          return list.take(8).toList();
        }
      }
      throw FormatException('Unexpected response format: $raw');
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'gemini_sticker_texts_failed',
      );
      await FirebaseAnalytics.instance.logEvent(name: 'ai_text_fallback');
      return List.from(_kFallbackTexts);
    }
  }
}
