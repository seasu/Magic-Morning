import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;

import 'firebase_service.dart';

/// 貼圖規格：情感主題 + 背景色 + 中文標語
class _StickerSpec {
  final String text;
  final String bgColor;
  final String emotion;

  const _StickerSpec({
    required this.text,
    required this.bgColor,
    required this.emotion,
  });
}

/// Gemini 2.0 Flash 圖片生成服務
///
/// 針對使用者上傳的照片，一次生成 8 張 LINE 貼圖。
/// 每張貼圖為圓形設計，包含：
/// - 彩色實心圓形背景
/// - 根據照片人臉繪製的 Q 版卡通頭像
/// - 特定情緒表情與裝飾
/// - 中文情感標語（直接嵌入圖中）
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/gemini-2.0-flash-exp:generateContent';

  /// 8 張貼圖的情感主題設定（對應 LINE 標準貼圖 8 情感組合）
  static const _kStickers = [
    _StickerSpec(
      text: '哈囉！',
      bgColor: 'warm peach orange #F4A261',
      emotion: 'cheerfully waving hello with big friendly smile',
    ),
    _StickerSpec(
      text: '太棒了！',
      bgColor: 'sky blue #74C0FC',
      emotion: 'excited thumbs-up gesture with sparkle stars ✨★ around the face',
    ),
    _StickerSpec(
      text: '真的嗎？',
      bgColor: 'golden yellow #FFD43B',
      emotion: 'shocked wide eyes with large question marks ？ flying around',
    ),
    _StickerSpec(
      text: '尷尬了...',
      bgColor: 'soft cherry pink #FFB3C6',
      emotion: 'embarrassed blushing with nervous smile and sweat drop 💧 on forehead',
    ),
    _StickerSpec(
      text: '哼！',
      bgColor: 'deep red #FF6B6B',
      emotion: 'angry frowning with flames 🔥 erupting around the head',
    ),
    _StickerSpec(
      text: '開心！',
      bgColor: 'fresh mint green #63E6BE',
      emotion: 'joyfully laughing with rainbow 🌈 and colorful confetti in background',
    ),
    _StickerSpec(
      text: '我想想...',
      bgColor: 'soft lavender #C084FC',
      emotion: 'thoughtfully rubbing chin with a thought bubble ？ floating above',
    ),
    _StickerSpec(
      text: '再見囉！',
      bgColor: 'baby blue #ADE8F4',
      emotion: 'cheerfully waving goodbye wearing cool sunglasses 😎 with sparkles',
    ),
  ];

  /// 並行生成全部 8 張貼圖；每張失敗時回傳 null（使用 Flutter fallback）
  Future<List<Uint8List?>> generateAll(Uint8List photoBytes) async {
    FirebaseService.log('StickerGenerationService.generateAll: start (8 stickers)');
    final results = await Future.wait(
      List.generate(_kStickers.length, (i) => generateOne(photoBytes, i)),
    );
    await FirebaseAnalytics.instance
        .logEvent(name: 'sticker_images_generated');
    return results;
  }

  /// 生成單張貼圖，[index] 對應 _kStickers 的情感主題
  Future<Uint8List?> generateOne(Uint8List photoBytes, int index) async {
    final spec = _kStickers[index % _kStickers.length];
    FirebaseService.log(
        'StickerGenerationService.generateOne: index=$index text=${spec.text}');
    try {
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt(spec)},
              {
                'inlineData': {
                  'mimeType': 'image/jpeg',
                  'data': base64Encode(photoBytes),
                }
              },
            ],
          }
        ],
        'generationConfig': {
          'responseModalities': ['IMAGE', 'TEXT'],
        },
      });

      final response = await http
          .post(
            Uri.parse('$_endpoint?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        FirebaseService.log(
          'StickerGenerationService: HTTP ${response.statusCode} '
          'for index=$index — ${response.body.substring(0, 200)}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts =
          json['candidates'][0]['content']['parts'] as List<dynamic>;

      for (final part in parts) {
        if (part is Map<String, dynamic> &&
            part.containsKey('inlineData')) {
          final mimeType = part['inlineData']['mimeType'] as String;
          if (mimeType.startsWith('image/')) {
            final bytes =
                base64Decode(part['inlineData']['data'] as String);
            FirebaseService.log(
                'StickerGenerationService: index=$index done '
                '(${bytes.lengthInBytes} bytes)');
            return bytes;
          }
        }
      }

      FirebaseService.log(
          'StickerGenerationService: no image part for index=$index');
      return null;
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'sticker_image_gen_failed',
      );
      return null;
    }
  }

  /// 建立 Gemini prompt：生成圓形 LINE 貼圖，內含卡通頭像與文字
  ///
  /// 設計原則：
  /// 1. 圓形背景填色（指定色票）
  /// 2. 根據照片人臉繪製 Q 版卡通頭像
  /// 3. 情緒表情由 [spec.emotion] 決定
  /// 4. 中文標語 [spec.text] 直接嵌入圓圈底部
  /// 5. 加入 LINE 貼圖特有裝飾（閃光、星星）
  String _buildPrompt(_StickerSpec spec) => '''
You are a professional LINE sticker illustrator. Create ONE circular LINE sticker based on the person's face in the provided photo.

STICKER DESIGN SPECIFICATIONS:
- Canvas: 370 × 370 px square, pure WHITE background outside the circle
- Main shape: A large filled circle (340px diameter, centered) with solid background color: ${spec.bgColor}
- Face: Draw a CUTE CHIBI/Q-VERSION cartoon face of the person in the photo
  * Simplify the face into rounded cute features: big sparkly eyes, small nose, chubby cheeks
  * The cartoon face should fill about 60-70% of the circle area (upper portion)
  * Expression: ${spec.emotion}
  * Style: clean flat illustration, thick outlines (2-3px), no photo-realism
- Chinese text: Write "${spec.text}" in bold rounded Chinese font
  * Position: bottom 25% area INSIDE the circle
  * Text color: WHITE with dark drop shadow for readability
  * Font size: large (approx 36-40px equivalent), bold, clearly legible
- Decorations inside the circle: add 3-5 small sparkle/star elements (✦ ★ ✨ small hearts or themed icons)
  * Scatter around the face and near the text
  * Colors should complement the background

STYLE REFERENCES: LINE Friends, Chiikawa, Molang — professional sticker quality with clean illustration
IMPORTANT: The circle must have a thick white outline (4px) to separate it from white background. Do NOT add text outside the circle. Keep design simple and cute.

Output: The sticker image only. No captions or explanations.
''';
}
