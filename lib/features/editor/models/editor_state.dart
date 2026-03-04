import 'dart:typed_data';

enum EditorStatus { idle, removingBackground, generatingCaption, ready, exporting }

class EditorState {
  final String originalImagePath;
  final Uint8List? subjectBytes; // 去背結果 PNG
  final String caption;
  final double captionFontSize;
  final EditorStatus status;
  final String? errorMessage;

  const EditorState({
    required this.originalImagePath,
    this.subjectBytes,
    this.caption = '',
    this.captionFontSize = 28,
    this.status = EditorStatus.idle,
    this.errorMessage,
  });

  EditorState copyWith({
    Uint8List? subjectBytes,
    String? caption,
    double? captionFontSize,
    EditorStatus? status,
    String? errorMessage,
  }) {
    return EditorState(
      originalImagePath: originalImagePath,
      subjectBytes: subjectBytes ?? this.subjectBytes,
      caption: caption ?? this.caption,
      captionFontSize: captionFontSize ?? this.captionFontSize,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}
