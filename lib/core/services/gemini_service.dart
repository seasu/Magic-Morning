import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import '../models/sticker_spec.dart';
import 'firebase_service.dart';

/// 8 組預設 fallback（Cloud Function 失敗時使用）
const _kFallbackSpecs = [
  {'text': '哈囉！',    'emotion': 'cheerfully waving hello',            'bgColor': 'warm peach #F4A261'},
  {'text': '太棒了！',  'emotion': 'excited thumbs-up with sparkles',    'bgColor': 'sky blue #74C0FC'},
  {'text': '真的嗎？',  'emotion': 'shocked wide eyes, question marks',  'bgColor': 'golden yellow #FFD43B'},
  {'text': '尷尬了...', 'emotion': 'embarrassed blushing, sweat drop',   'bgColor': 'soft pink #FFB3C6'},
  {'text': '哼！',      'emotion': 'angry frowning with flames',         'bgColor': 'deep red #FF6B6B'},
  {'text': '開心！',    'emotion': 'joyful laughing, rainbow confetti',  'bgColor': 'mint green #63E6BE'},
  {'text': '我想想...', 'emotion': 'thoughtful chin-rubbing, thought bubble', 'bgColor': 'lavender #C084FC'},
  {'text': '再見囉！',  'emotion': 'waving goodbye with sunglasses',     'bgColor': 'baby blue #ADE8F4'},
];

class GeminiService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// 呼叫 Cloud Function `generateStickerSpecs`。
  ///
  /// Spec 預覽免費，不扣點。
  /// 失敗時回傳 fallback specs，確保使用者仍能看到預覽。
  Future<List<StickerSpec>> generateStickerSpecs(Uint8List imageBytes) async {
    FirebaseService.log('GeminiService.generateStickerSpecs: start');

    try {
      final callable = _fn.httpsCallable(
        'generateStickerSpecs',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 65)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'photoBase64': base64Encode(imageBytes),
      });

      final data = result.data;
      final rawSpecs = (data['specs'] as List).cast<Map<String, dynamic>>();
      final specs = rawSpecs.take(8).map(StickerSpec.fromJson).toList();

      FirebaseService.log('GeminiService.generateStickerSpecs: done');
      await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_generated');

      return specs;
    } on FirebaseFunctionsException catch (e, stack) {
      FirebaseService.log(
        'GeminiService: Cloud Function error code=${e.code} msg=${e.message}',
      );
      await FirebaseService.recordError(
        e, stack, reason: 'gemini_specs_fn_failed',
      );
      await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
      return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'gemini_specs_unexpected_failed',
      );
      await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
      return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
    }
  }
}
