import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 表單外固定顯示照片，捲動欄位時仍可對照；支援切換原圖／校正圖與放大。
/// 照片僅來自 App 記憶體或私有檔案，不產生網路請求。
class MedicinePhotoComparison extends StatefulWidget {
  const MedicinePhotoComparison({
    super.key,
    required this.original,
    this.corrected,
    this.fullscreen = false,
  });
  final Uint8List original;
  final Uint8List? corrected;
  final bool fullscreen;
  @override
  State<MedicinePhotoComparison> createState() =>
      _MedicinePhotoComparisonState();
}

class _MedicinePhotoComparisonState extends State<MedicinePhotoComparison> {
  bool _original = true;
  final _transform = TransformationController();
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _original = true;
                _transform.value = Matrix4.identity();
              }),
              child: Text(_original ? '● 原始照片' : '原始照片'),
            ),
            if (widget.corrected != null)
              TextButton(
                onPressed: () => setState(() {
                  _original = false;
                  _transform.value = Matrix4.identity();
                }),
                child: Text(!_original ? '● 裁切校正' : '裁切校正'),
              ),
            if (!widget.fullscreen)
              IconButton(
                tooltip: '全螢幕放大照片',
                icon: const Icon(Icons.fullscreen),
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => Dialog.fullscreen(
                      child: Scaffold(
                        appBar: AppBar(title: const Text('放大對照藥袋')),
                        body: MedicinePhotoComparison(
                          original: widget.original,
                          corrected: widget.corrected,
                          fullscreen: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        Expanded(
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 8,
            child: SizedBox.expand(
              child: Image.memory(
                _original || widget.corrected == null
                    ? widget.original
                    : widget.corrected!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('可雙指放大；點全螢幕查看細節', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}
