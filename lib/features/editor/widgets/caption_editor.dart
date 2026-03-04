import 'package:flutter/material.dart';

class CaptionEditor extends StatefulWidget {
  final String caption;
  final double fontSize;
  final ValueChanged<String> onCaptionChanged;
  final ValueChanged<double> onFontSizeChanged;

  const CaptionEditor({
    super.key,
    required this.caption,
    required this.fontSize,
    required this.onCaptionChanged,
    required this.onFontSizeChanged,
  });

  @override
  State<CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<CaptionEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.caption);
  }

  @override
  void didUpdateWidget(CaptionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.caption != widget.caption &&
        _controller.text != widget.caption) {
      _controller.text = widget.caption;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('編輯文案', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 2,
            onChanged: widget.onCaptionChanged,
            decoration: InputDecoration(
              hintText: '輸入早安祝福語…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.format_size, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: widget.fontSize,
                  min: 16,
                  max: 48,
                  divisions: 16,
                  label: widget.fontSize.toStringAsFixed(0),
                  onChanged: widget.onFontSizeChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
