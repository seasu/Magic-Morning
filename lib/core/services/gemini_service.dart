import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'firebase_service.dart';

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  /// 根據圖片內容生成 10~20 字的早安文案
  Future<String> generateCaption(File imageFile) async {
    FirebaseService.log('GeminiService.generateCaption: start');
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await _model.generateContent([
        Content.multi([
          TextPart(
            '請根據這張照片的氛圍，用繁體中文生成一段 10~20 字的溫馨早安祝福語。'
            '只回傳祝福語本身，不要加任何解釋或標點以外的內容。',
          ),
          DataPart('image/jpeg', base64Decode(base64Image)),
        ]),
      ]);

      final text = response.text ?? '早安！願你今天充滿活力，笑顏常開。';
      FirebaseService.log('GeminiService.generateCaption: done');
      return text;
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'gemini_caption_failed');
      return '早安！願你今天充滿活力，笑顏常開。';
    }
  }
}
