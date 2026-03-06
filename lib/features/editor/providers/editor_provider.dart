import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/sticker_generation_service.dart';
import '../../../core/utils/image_processor.dart';
import '../models/editor_state.dart';

/// 以 imagePath 為 key 的 provider
final editorStateProvider =
    NotifierProvider.autoDispose.family<_EditorFamilyNotifier, EditorState, String>(
  _EditorFamilyNotifier.new,
);

class _EditorFamilyNotifier
    extends AutoDisposeFamilyNotifier<EditorState, String> {
  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  /// 初始化：直接讓 Gemini 從原始照片生成 8 張圓形貼圖
  ///
  /// 新流程（v1.9+）：
  /// 1. Resize 照片（防 OOM）
  /// 2. 後台並行生成 8 張圓形卡通貼圖（含文字，跳過 ML Kit 去背）
  /// 3. 每張完成後即時更新對應卡片
  Future<void> initialize() async {
    state = state.copyWith(status: EditorStatus.generatingTexts);

    Uint8List resized;
    try {
      final imageFile = File(state.originalImagePath);
      resized = await ImageProcessor.resizeForNative(imageFile);
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_resize_failed',
      );
      state = state.copyWith(
        status: EditorStatus.idle,
        errorMessage: '圖片處理失敗，請重試',
      );
      return;
    }

    state = state.copyWith(status: EditorStatus.ready);
    _generateImagesInBackground(resized);
  }

  /// 重新生成全部 8 張貼圖
  Future<void> regenerateTexts() async {
    state = state.copyWith(
      status: EditorStatus.generatingTexts,
      generatedImages: List.filled(8, null),
    );
    try {
      final resized = await ImageProcessor.resizeForNative(
        File(state.originalImagePath),
      );
      state = state.copyWith(status: EditorStatus.ready);
      _generateImagesInBackground(resized);
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_regen_failed',
      );
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者手動修改第 [index] 張貼圖的文字（fallback 模式用）
  void updateStickerText(int index, String text) {
    final updated = List<String>.from(state.stickerTexts);
    updated[index] = text;
    state = state.copyWith(stickerTexts: updated);
  }

  /// 使用者切換第 [stickerIndex] 張貼圖的邊框樣式（kFrameStyles 中的索引）
  void updateFrameIndex(int stickerIndex, int frameIndex) {
    final updated = List<int>.from(state.frameIndices);
    updated[stickerIndex] = frameIndex;
    state = state.copyWith(frameIndices: updated);
  }

  // ─── private ────────────────────────────────────────────

  /// 後台並行生成 8 張 AI 貼圖；每張完成後立即更新對應卡片（非阻塞）
  ///
  /// sentinel 規則（Uint8List?）：
  ///   null          → 生成中（顯示 "AI 生成中…" badge）
  ///   Uint8List(0)  → 生成完但 API 失敗/無圖（顯示 fallback 文字貼圖）
  ///   Uint8List(>0) → 成功，顯示 AI 圓形貼圖
  void _generateImagesInBackground(Uint8List photoBytes) {
    for (int i = 0; i < 8; i++) {
      final index = i;
      StickerGenerationService().generateOne(photoBytes, index).then((img) {
        try {
          final updated = List<Uint8List?>.from(state.generatedImages);
          updated[index] = img ?? Uint8List(0);
          state = state.copyWith(generatedImages: updated);
        } catch (_) {
          // provider 已 dispose，忽略
        }
      });
    }
  }
}
