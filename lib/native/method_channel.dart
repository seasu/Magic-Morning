import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/services/firebase_service.dart';

/// Flutter ↔ Native 去背橋接介面
class BackgroundRemovalChannel {
  static const _channel = MethodChannel('com.magicmorning/background_removal');

  /// 傳入已縮圖的圖片 bytes，回傳去背後的 PNG bytes
  static Future<Uint8List> removeBackground(Uint8List imageBytes) async {
    FirebaseService.log(
      'BackgroundRemovalChannel.removeBackground: start '
      '(${imageBytes.lengthInBytes} bytes)',
    );
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'removeBackground',
        {'imageBytes': imageBytes},
      );
      if (result == null) throw PlatformException(code: 'NULL_RESULT');
      FirebaseService.log(
        'BackgroundRemovalChannel.removeBackground: done '
        '(${result.lengthInBytes} bytes)',
      );
      return result;
    } on PlatformException catch (e, stack) {
      await FirebaseService.recordError(
        e,
        stack,
        reason: 'remove_background_platform_error',
      );
      rethrow;
    }
  }
}
