import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/utils/image_processor.dart';
import '../../../native/method_channel.dart';
import '../models/editor_state.dart';

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => throw UnimplementedError('use EditorNotifier.family');

  Future<void> initialize() async {
    // Phase 1: 去背
    state = state.copyWith(status: EditorStatus.removingBackground);
    try {
      final imageFile = File(state.originalImagePath);
      final resized = await ImageProcessor.resizeForNative(imageFile);
      final subjectBytes = await BackgroundRemovalChannel.removeBackground(resized);

      state = state.copyWith(
        subjectBytes: subjectBytes,
        status: EditorStatus.generatingCaption,
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_remove_bg_failed');
      state = state.copyWith(
        status: EditorStatus.idle,
        errorMessage: '去背失敗，請重試',
      );
      return;
    }

    // Phase 2: AI 文案
    try {
      final caption = await GeminiService().generateCaption(
        File(state.originalImagePath),
      );
      state = state.copyWith(caption: caption, status: EditorStatus.ready);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_caption_failed');
      state = state.copyWith(
        caption: '早安！願你今天充滿活力，笑顏常開。',
        status: EditorStatus.ready,
      );
    }
  }

  void updateCaption(String text) {
    state = state.copyWith(caption: text);
  }

  void updateFontSize(double size) {
    state = state.copyWith(captionFontSize: size);
  }
}

final editorProvider = NotifierProvider.family<EditorNotifier, EditorState, String>(
  () => EditorNotifier(),
  // family 的 build 由外部傳入 imagePath
)..overrideWith(
    // 用 autoDispose.family 較佳，此處簡化示範
    () => EditorNotifier(),
  );

/// 實際使用的 provider — 以 imagePath 為 key
final editorStateProvider =
    NotifierProvider.autoDispose.family<_EditorFamilyNotifier, EditorState, String>(
  _EditorFamilyNotifier.new,
);

class _EditorFamilyNotifier
    extends AutoDisposeFamilyNotifier<EditorState, String> {
  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  Future<void> initialize() async {
    // 去背
    state = state.copyWith(status: EditorStatus.removingBackground);
    try {
      final imageFile = File(state.originalImagePath);
      final resized = await ImageProcessor.resizeForNative(imageFile);
      final subjectBytes = await BackgroundRemovalChannel.removeBackground(resized);
      state = state.copyWith(
        subjectBytes: subjectBytes,
        status: EditorStatus.generatingCaption,
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_remove_bg_failed');
      state = state.copyWith(
        status: EditorStatus.idle,
        errorMessage: '去背失敗，請重試',
      );
      return;
    }

    // AI 文案
    try {
      final caption = await GeminiService().generateCaption(
        File(state.originalImagePath),
      );
      state = state.copyWith(caption: caption, status: EditorStatus.ready);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_caption_failed');
      state = state.copyWith(
        caption: '早安！願你今天充滿活力，笑顏常開。',
        status: EditorStatus.ready,
      );
    }
  }

  void updateCaption(String text) => state = state.copyWith(caption: text);
  void updateFontSize(double size) => state = state.copyWith(captionFontSize: size);
}
