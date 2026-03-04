import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/firebase_service.dart';

class ImageProcessor {
  static const int _maxDimension = 1080;

  /// 縮圖至最長邊不超過 1080px，回傳 JPEG bytes
  /// 必須在傳往原生層前呼叫，以防 OOM
  static Future<Uint8List> resizeForNative(File imageFile) async {
    FirebaseService.log('ImageProcessor.resizeForNative: start');
    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) throw Exception('無法解碼圖片');

    final needsResize =
        original.width > _maxDimension || original.height > _maxDimension;

    final processed = needsResize
        ? img.copyResize(
            original,
            width: original.width > original.height ? _maxDimension : -1,
            height: original.height >= original.width ? _maxDimension : -1,
          )
        : original;

    FirebaseService.log(
      'ImageProcessor.resizeForNative: done '
      '(${processed.width}x${processed.height})',
    );
    return Uint8List.fromList(img.encodeJpg(processed, quality: 90));
  }
}
