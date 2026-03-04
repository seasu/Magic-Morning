import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/firebase_service.dart';
import '../models/editor_state.dart';
import '../providers/editor_provider.dart';
import '../widgets/canvas_preview.dart';
import '../widgets/caption_editor.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String imagePath;

  const EditorScreen({super.key, required this.imagePath});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 初始化後立即觸發去背 + AI 文案
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorStateProvider(widget.imagePath).notifier).initialize();
    });
  }

  Future<void> _export() async {
    FirebaseService.log('EditorScreen._export: start');
    final notifier = ref.read(editorStateProvider(widget.imagePath).notifier);
    ref
        .read(editorStateProvider(widget.imagePath).notifier)
        .updateCaption(ref.read(editorStateProvider(widget.imagePath)).caption);

    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 儲存至暫存資料夾（正式版應使用 image_gallery_saver 存入相簿）
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/magic_morning_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('貼圖已儲存！')),
      );
      FirebaseService.log('EditorScreen._export: done → ${file.path}');
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_export_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請重試')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingCaption;

    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯貼圖'),
        actions: [
          if (state.status == EditorStatus.ready)
            IconButton(
              onPressed: _export,
              icon: const Icon(Icons.download_outlined),
              tooltip: '儲存貼圖',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? _LoadingView(status: state.status)
                : state.errorMessage != null
                    ? _ErrorView(message: state.errorMessage!)
                    : RepaintBoundary(
                        key: _repaintKey,
                        child: CanvasPreview(
                          originalImagePath: widget.imagePath,
                          subjectBytes: state.subjectBytes,
                          caption: state.caption,
                          fontSize: state.captionFontSize,
                        ),
                      ),
          ),
          if (state.status == EditorStatus.ready)
            CaptionEditor(
              caption: state.caption,
              fontSize: state.captionFontSize,
              onCaptionChanged: (text) => ref
                  .read(editorStateProvider(widget.imagePath).notifier)
                  .updateCaption(text),
              onFontSizeChanged: (size) => ref
                  .read(editorStateProvider(widget.imagePath).notifier)
                  .updateFontSize(size),
            ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final EditorStatus status;

  const _LoadingView({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == EditorStatus.removingBackground
        ? '正在去除背景…'
        : '正在生成早安文案…';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
