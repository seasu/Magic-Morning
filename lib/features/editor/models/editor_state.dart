import 'dart:typed_data';

enum EditorStatus {
  idle,
  removingBackground,
  generatingTexts,
  ready, // AI 圖片可能仍在後台生成
  exporting,
}

const _kFallbackTexts = [
  '哈囉！', '太棒了！', '真的嗎？', '尷尬了...',
  '哼！', '開心！', '我想想...', '再見囉！',
];

class EditorState {
  final String originalImagePath;
  final Uint8List? subjectBytes;          // 去背結果 PNG（保留作 fallback）
  final List<String> stickerTexts;        // 8 組情感標語（fallback 用）
  final List<Uint8List?> generatedImages; // 8 張 Gemini 生成圓形貼圖（null = 仍在生成）
  final List<int> frameIndices;           // 每張貼圖選用的邊框索引（kFrameStyles）
  final EditorStatus status;
  final String? errorMessage;

  EditorState({
    required this.originalImagePath,
    this.subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    List<int>? frameIndices,
    this.status = EditorStatus.idle,
    this.errorMessage,
  })  : stickerTexts = stickerTexts ?? List.from(_kFallbackTexts),
        generatedImages = generatedImages ?? List.filled(8, null),
        frameIndices = frameIndices ?? [0, 5, 8, 1, 3, 12, 6, 20];

  EditorState copyWith({
    Uint8List? subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    List<int>? frameIndices,
    EditorStatus? status,
    String? errorMessage,
  }) {
    return EditorState(
      originalImagePath: originalImagePath,
      subjectBytes: subjectBytes ?? this.subjectBytes,
      stickerTexts: stickerTexts ?? this.stickerTexts,
      generatedImages: generatedImages ?? this.generatedImages,
      frameIndices: frameIndices ?? this.frameIndices,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}
