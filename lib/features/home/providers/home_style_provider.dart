import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首頁選擇的預設貼圖風格索引（對應 StickerStyle.values）
final homeStyleProvider = StateProvider<int>((ref) => 0);
