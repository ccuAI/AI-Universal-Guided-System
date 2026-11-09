import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'medicine_image_processing.dart';

/// 相機／相簿之後、OCR 之前的可取消預覽。
/// 只處理工作副本；回傳 null 代表取消，不建立計畫、照片檔或提醒。
class MedicinePhotoPreparePage extends StatefulWidget {
  const MedicinePhotoPreparePage({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<MedicinePhotoPreparePage> createState() =>
      _MedicinePhotoPreparePageState();
}

class _MedicinePhotoPreparePageState extends State<MedicinePhotoPreparePage> {
  MedicineImageData? _working;
  MedicineImageData? _preview;
  bool _busy = true;
  String? _error;
  List<MedicineCorner> _corners = _fullImage();
  static List<MedicineCorner> _fullImage() => const [
    MedicineCorner(0, 0),
    MedicineCorner(1, 0),
    MedicineCorner(1, 1),
    MedicineCorner(0, 1),
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final image = await compute(normalizeMedicineImage, widget.bytes);
      if (mounted) {
        setState(() {
          _working = image;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '無法讀取照片，請返回並改選 JPG／PNG。';
          _busy = false;
        });
      }
    }
  }

  Future<void> _rotate() async {
    if (_busy || _working == null) return;
    setState(() => _busy = true);
    try {
      final result = await compute(rotateMedicineImage, _working!);
      if (mounted) {
        setState(() {
          _working = result;
          _corners = _fullImage();
          _preview = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '旋轉失敗，請重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop() async {
    if (_busy || _working == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await compute(
        rectifyMedicineImage,
        MedicineCropRequest(_working!, List.of(_corners)),
      );
      if (mounted) setState(() => _preview = result);
    } catch (_) {
      if (mounted) setState(() => _error = '選框太小或無法校正，請重設四角後再試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _canvas(MedicineImageData image) => LayoutBuilder(
    builder: (context, box) {
      final scale = math.min(
        (box.maxWidth - 36) / image.width,
        (box.maxHeight - 36) / image.height,
      );
      final width = (image.width * math.max(0.01, scale)).toDouble();
      final height = (image.height * math.max(0.01, scale)).toDouble();
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.memory(
                  image.bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              if (_preview == null) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _CropPainter(_corners)),
                  ),
                ),
                for (var index = 0; index < 4; index++)
                  Positioned(
                    left: _corners[index].x * width - 22,
                    top: _corners[index].y * height - 22,
                    child: Semantics(
                      label: const ['左上裁切角', '右上裁切角', '右下裁切角', '左下裁切角'][index],
                      child: GestureDetector(
                        key: ValueKey('crop-corner-$index'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _busy
                            ? null
                            : (event) {
                                final next = List<MedicineCorner>.of(_corners);
                                next[index] = MedicineCorner(
                                  (_corners[index].x + event.delta.dx / width)
                                      .clamp(0.0, 1.0),
                                  (_corners[index].y + event.delta.dy / height)
                                      .clamp(0.0, 1.0),
                                );
                                if (validMedicineCorners(next)) {
                                  setState(() => _corners = next);
                                }
                              },
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(_preview == null ? '裁切／四角校正' : '確認校正結果')),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _preview == null
                    ? '拖曳四個圓點框住要辨識的區域，保留完整用藥指示。可排除下方一般衛教文字。'
                    : '確認文字完整、方向正確。被筆跡遮住的內容仍須人工核對；原始照片會保留。',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _working == null
                  ? Center(
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.broken_image_outlined),
                    )
                  : _canvas(_preview ?? _working!),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _preview == null
                    ? [
                        OutlinedButton.icon(
                          onPressed: _busy || _working == null ? null : _rotate,
                          icon: const Icon(Icons.rotate_right),
                          label: const Text('旋轉 90°'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _corners = _fullImage()),
                          child: const Text('重設選框'),
                        ),
                        FilledButton(
                          onPressed: _busy || _working == null ? null : _crop,
                          child: const Text('預覽裁切／校正'),
                        ),
                      ]
                    : [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _preview = null),
                          child: const Text('重新調整'),
                        ),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context, _preview!.bytes),
                          child: const Text('確認，開始辨識'),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.corners);
  final List<MedicineCorner> corners;
  @override
  void paint(Canvas canvas, Size size) {
    final selection = Path()
      ..moveTo(corners.first.x * size.width, corners.first.y * size.height);
    for (final corner in corners.skip(1)) {
      selection.lineTo(corner.x * size.width, corner.y * size.height);
    }
    selection.close();
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(selection, Offset.zero);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawPath(
      selection,
      Paint()
        ..color = Colors.tealAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.corners != corners;
}
