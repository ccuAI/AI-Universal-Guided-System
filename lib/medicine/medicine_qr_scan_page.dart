import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'medicine_prescription_qr.dart';

/// 掃描醫師藥單上的 QR code，回傳原始文字給上一頁解析與保存。
///
/// 只接受 [medicinePrescriptionPrefix] 開頭的內容；其他 QR code 只提示，不離開。
/// 也可從相簿選取藥單照片辨識 QR code（例如家人傳來的照片）。
class MedicineQrScanPage extends StatefulWidget {
  const MedicineQrScanPage({super.key});

  /// mobile_scanner 支援的平台；Windows／Linux 桌面改用輸入藥單代碼。
  static bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<MedicineQrScanPage> createState() => _MedicineQrScanPageState();
}

class _MedicineQrScanPageState extends State<MedicineQrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  DateTime _lastHint = DateTime(2000);

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _accept(Iterable<Barcode> barcodes) {
    if (_done || !mounted) return;
    for (final barcode in barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.startsWith(medicinePrescriptionPrefix)) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
    // 掃到其他 QR code 時節流提示，避免每一幀都跳出訊息。
    final now = DateTime.now();
    if (barcodes.isNotEmpty && now.difference(_lastHint).inSeconds >= 3) {
      _lastHint = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('這不是醫師藥單的 QR code，請對準藥單上的 QR code。')),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (photo == null || !mounted) return;
      final capture = await _controller.analyzeImage(
        photo.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted) return;
      if (capture == null || capture.barcodes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('照片中找不到 QR code，請換一張較清楚的照片。')),
        );
        return;
      }
      _lastHint = DateTime(2000);
      _accept(capture.barcodes);
    } catch (error) {
      debugPrint('從相簿辨識 QR code 失敗：$error');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('無法讀取照片，請確認相簿權限後重試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('掃描藥單 QR code'),
        actions: [
          IconButton(
            tooltip: '手電筒',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          if (!kIsWeb)
            IconButton(
              tooltip: '從相簿選取',
              icon: const Icon(Icons.photo_library),
              onPressed: _pickImage,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) => _accept(capture.barcodes),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? '沒有相機權限。請到手機設定允許相機，或改用相簿／輸入藥單代碼。'
                      : '無法開啟相機，請改用相簿或輸入藥單代碼。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              '將藥單上的 QR code 放進框內，掃到後會自動建立用藥提醒。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
