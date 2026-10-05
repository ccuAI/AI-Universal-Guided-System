import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class MedicineTakerPage extends StatefulWidget {
  const MedicineTakerPage({Key? key}) : super(key: key);

  @override
  State<MedicineTakerPage> createState() => _MedicineTakerPageState();
}

class _MedicineTakerPageState extends State<MedicineTakerPage> {
  // 宣告儲存照片的變數
  File? _scannedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false; // 用於辨識中的載入動畫

  // 拍照辨識藥袋的方法
  Future<void> _takeMedicinePhoto() async {
    try {
      // 呼叫系統相機拍照
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,// 從相簿選取照片final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
        maxWidth: 1800, // 限制最大寬度，避免照片過大導致辨識變慢
        maxHeight: 1800,
        imageQuality: 85,
         // 微幅壓縮提升傳輸效率
      );

      if (photo != null) {
        setState(() {
          _scannedImage = File(photo.path);
          _isLoading = true; // 開啟辨識中動畫
        });

        // TODO: 這裡實作你的藥袋辨識邏輯（例如送至後端 API 或 OCR 套件）
        // 模擬辨識耗時 2 秒
        await Future.delayed(const Duration(seconds: 2));

        setState(() {
          _isLoading = false; // 辨識完成，關閉動畫
        });

        // 提示使用者拍照成功（測試用）
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('藥袋照片選取成功！路徑: ${photo.path}')),
          );
        }
      }
    } catch (e) {
      debugPrint('拍照發生錯誤: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 頂部大標題
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text(
                '吃藥小助手',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            
            // 分隔線
            const Divider(height: 1, thickness: 1, color: Colors.black26),
            
            // 中間主要內容：時間列表與照片預覽
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoading)
                      const Column(
                        children: [
                          CircularProgressIndicator(color: Color(0xFF9AD1F8)),
                          SizedBox(height: 16),
                          Text('正在辨識藥袋中...', style: TextStyle(fontSize: 16)),
                        ],
                      )
                    else if (_scannedImage != null)
                      // 拍照後顯示剛剛拍完的藥袋照片預覽
                      Expanded(
                        child: Column(
                          children: [
                            const Text('已拍攝的藥袋：', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Expanded(child: Image.file(_scannedImage!)),
                          ],
                        ),
                      )
                    else
                      // 原本的時間列表預留區
                      const Expanded(
                        child: Center(
                          child: Text(
                            '目前沒有處方資料\n請點擊下方「+」拍照辨識藥袋',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black45, fontSize: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // 底部診所切換欄與功能按鈕
            const Divider(height: 1, thickness: 1, color: Colors.black26),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  // 封裝底部導覽與功能區塊
  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 診所處方切換列
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 36, color: Color(0xFF9AD1F8)),
                onPressed: () {},
              ),
              const Text(
                'XX診所處方',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 36, color: Color(0xFF9AD1F8)),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 拍照辨識藥袋按鈕
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '拍照辨識藥袋',
                    style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _takeMedicinePhoto, // 綁定拍照點擊事件
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black87, width: 2),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.add,
                        size: 32,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
