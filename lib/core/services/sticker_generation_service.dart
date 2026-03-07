import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../models/sticker_spec.dart';
import 'firebase_service.dart';

/// Gemini 貼圖生成服務
///
/// 一次 API 呼叫生成 1×8 直欄圖（共 8 張貼圖，垂直堆疊），
/// 收到後沿水平線均切 8 份，裁切最可靠（無欄位對齊問題）。
/// 只消耗 1 個 API 請求，大幅降低 rate-limit 壓力。
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/gemini-2.5-flash-image:generateContent';

  /// 一次呼叫生成 8 張貼圖（1 欄 × 8 列，垂直堆疊），裁切後回傳 List<Uint8List?>
  ///
  /// 回傳長度固定為 8，對應索引 0–7（上→下）。
  /// 失敗時對應位置為 null。
  Future<List<Uint8List?>> generateAllAsGrid(
    Uint8List photoBytes,
    List<StickerSpec> specs,
  ) async {
    assert(specs.length == 8, 'generateAllAsGrid expects exactly 8 specs');
    FirebaseService.log('StickerGenerationService.generateAllAsGrid: start');

    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final body = jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': _buildGridPrompt(specs)},
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
            .timeout(const Duration(seconds: 90)); // grid 較大，給更長 timeout

        if (response.statusCode == 429) {
          if (attempt < maxRetries) {
            final delay = _parseRetryDelay(response.body) ??
                Duration(seconds: (attempt + 1) * 15);
            FirebaseService.log(
              'StickerGenerationService: grid rate-limited, '
              'retry ${attempt + 1}/$maxRetries in ${delay.inSeconds}s',
            );
            await Future.delayed(delay);
            continue;
          }
          _logApiError(429, response.body, attempt);
          throw StickerApiException(429, response.body);
        }

        if (response.statusCode != 200) {
          _logApiError(response.statusCode, response.body, attempt);
          // 5xx server error → retry；4xx（除 429）→ 直接失敗
          if (response.statusCode >= 500 && attempt < maxRetries) {
            final delay = Duration(seconds: (attempt + 1) * 5);
            await Future.delayed(delay);
            continue;
          }
          throw StickerApiException(response.statusCode, response.body);
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final parts =
            json['candidates'][0]['content']['parts'] as List<dynamic>;

        for (final part in parts) {
          if (part is Map<String, dynamic> && part.containsKey('inlineData')) {
            final mimeType = part['inlineData']['mimeType'] as String;
            if (mimeType.startsWith('image/')) {
              final gridBytes =
                  base64Decode(part['inlineData']['data'] as String);
              FirebaseService.log(
                'StickerGenerationService: grid received '
                '(${gridBytes.lengthInBytes} bytes), cropping…',
              );
              final crops = await _cropGrid(gridBytes, cols: 1, rows: 8);
              await FirebaseAnalytics.instance
                  .logEvent(name: 'sticker_images_generated');
              return crops;
            }
          }
        }

        _logApiError(200, response.body, attempt, label: 'no image part');
        throw StickerApiException(200, 'API 回傳無圖片（response body）:\n${response.body}');

      } catch (e, stack) {
        await FirebaseService.recordError(
          e, stack, reason: 'sticker_grid_gen_failed',
        );
        return List.filled(8, null);
      }
    }

    return List.filled(8, null);
  }

  // ─── private ────────────────────────────────────────────────────────────

  /// grid 圖裁切：將大圖均分為 cols×rows 個格子，回傳 PNG bytes list
  /// 順序：左→右、上→下（與 prompt 編號一致）
  Future<List<Uint8List?>> _cropGrid(
    Uint8List imageBytes, {
    required int cols,
    required int rows,
  }) async {
    // 解碼完整圖片
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final fullImage = frame.image;

    final cellW = fullImage.width ~/ cols;
    final cellH = fullImage.height ~/ rows;

    FirebaseService.log(
      'StickerGenerationService._cropGrid: '
      '${fullImage.width}×${fullImage.height} → ${cellW}×$cellH per cell',
    );

    final results = <Uint8List?>[];

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        try {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);

          canvas.drawImageRect(
            fullImage,
            Rect.fromLTWH(
              (col * cellW).toDouble(),
              (row * cellH).toDouble(),
              cellW.toDouble(),
              cellH.toDouble(),
            ),
            Rect.fromLTWH(0, 0, cellW.toDouble(), cellH.toDouble()),
            ui.Paint(),
          );

          final picture = recorder.endRecording();
          final cropped = await picture.toImage(cellW, cellH);
          final byteData =
              await cropped.toByteData(format: ui.ImageByteFormat.png);
          results.add(byteData?.buffer.asUint8List());
        } catch (e) {
          FirebaseService.log(
            'StickerGenerationService._cropGrid: crop error at [$row,$col]: $e',
          );
          results.add(null);
        }
      }
    }

    return results;
  }

  /// API 錯誤時：同時寫入 Crashlytics log（完整 body）供事後查閱
  ///
  /// Crashlytics log 上限約 64 KB；body 超過 4000 字元時截斷並標注。
  static void _logApiError(
    int statusCode,
    String body,
    int attempt, {
    String label = '',
  }) {
    const maxLen = 4000;
    final truncated = body.length > maxLen;
    final bodySnippet =
        truncated ? '${body.substring(0, maxLen)}…[truncated]' : body;
    final tag = label.isNotEmpty ? ' ($label)' : '';
    FirebaseService.log(
      '[API ERROR] HTTP $statusCode attempt=${attempt + 1}$tag\n$bodySnippet',
    );
  }

  /// 從 Gemini 錯誤訊息解析「retry in X.Xs」秒數
  static Duration? _parseRetryDelay(String body) {
    final m = RegExp(r'retry in (\d+(?:\.\d+)?)s', caseSensitive: false)
        .firstMatch(body);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: ((seconds + 1) * 1000).round());
  }

  /// 建立 1×8 垂直堆疊 prompt（單欄，水平切割最可靠）
  String _buildGridPrompt(List<StickerSpec> specs) {
    final cells = List.generate(8, (i) {
      final s = specs[i];
      return 'Row ${i + 1}: background=${s.bgColor}, '
          'expression=${s.emotion}, Chinese text="${s.text}"';
    }).join('\n');

    return '''
You are a professional LINE sticker illustrator. Create a single tall image containing 8 circular LINE stickers stacked vertically (1 column × 8 rows) based on the person's face in the photo.

LAYOUT:
- 1 column, 8 rows = 8 cells total, stacked top-to-bottom
- Each cell is a PERFECT SQUARE of identical size
- NO gaps, borders, numbers, or labels between rows
- NO padding at top or bottom — cells fill the entire canvas edge-to-edge
- White background outside each circle

EACH CELL DESIGN:
- A large filled circle occupying ~90% of the cell, centered
- Cartoon chibi face of the person in the photo (cute, Q-version)
  * Big sparkly eyes, small nose, chubby cheeks
  * Face fills ~65% of the circle (upper portion)
  * Clean flat illustration, thick black outlines, no photo-realism
- Chinese text in bold rounded font at bottom 25% inside the circle, white fill with dark shadow
- 3–5 small sparkles/stars/themed icons scattered inside the circle
- White outline (4 px) around each circle

ROW SPECIFICATIONS (top to bottom):
$cells

STYLE: LINE Friends / Chiikawa quality. Each sticker must look different.
CRITICAL: Output ONLY this 1×8 stacked image. No text, no labels, no extra borders.
''';
  }
}

/// Gemini API 呼叫失敗時拋出，攜帶完整錯誤資訊供 UI 顯示
class StickerApiException implements Exception {
  final int statusCode;
  final String body;

  const StickerApiException(this.statusCode, this.body);

  @override
  String toString() => 'StickerApiException HTTP $statusCode:\n$body';
}
