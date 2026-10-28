import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 引入套件
import 'scroll_bar_medtaker.dart' as medtaker;
import 'dart:io';

class MedicineTakerPage extends StatefulWidget {
  const MedicineTakerPage({Key? key}) : super(key: key);

  @override
  State<MedicineTakerPage> createState() => _MedicineTakerPageState();
}

class _MedicineTakerPageState extends State<MedicineTakerPage> {
  File? _scannedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false; 
  int ltemcount = 0; // 本地暫存的數量

  @override
  void initState() {
    super.initState();
    _loadData(); // App 一開啟時，立刻從手機本地硬碟讀取舊資料
  }


  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 讀取儲存的數量，若沒有紀錄過則預設為 0
      ltemcount = prefs.getInt('medicine_count') ?? 0;
      
      // 讀取儲存的照片路徑
      String? imagePath = prefs.getString('scanned_image_path');
      if (imagePath != null && imagePath.isNotEmpty) {
        _scannedImage = File(imagePath);
      }
    });
  }

  //  儲存資料到本地的方法
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('medicine_count', ltemcount); // 儲存數量
    await prefs.setString('scanned_image_path', _scannedImage?.path ?? ''); // 儲存照片路徑
  }

  // 拍照辨識藥袋的方法
  Future<void> _takeMedicinePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1800, 
        maxHeight: 1800,
        imageQuality: 85, 
      );

      if (photo != null) {
        setState(() {
          _scannedImage = File(photo.path);
          _isLoading = true; 
        });

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          setState(() {
            _isLoading = false; 
            ltemcount++; // 數量加 1
          });

          await _saveData(); // 關鍵：狀態更新後，立刻同步儲存到手機本地空間！

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('藥袋照片選取成功並已儲存！')),
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
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2.0),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Colors.black26),
            
            // 中間主要內容
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
                      ),
                    
                    if (!_isLoading)
                      _scannedImage == null
                          ? const Expanded(
                              child: Center(
                                child: Text(
                                  '目前沒有處方資料\n請點擊下方「+」拍照辨識藥袋',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black45, fontSize: 16),
                                ),
                              ),
                            )
                          : Expanded(
                              child: medtaker.listForMedicine(ltemcount, _scannedImage?.path),
                            ),
                  ],
                ),
              ),
            ),
            
            const Divider(height: 1, thickness: 1, color: Colors.black26),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 36, color: Color(0xFF9AD1F8)), onPressed: () {}),
              const Text('XX診所處方', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 36, color: Color(0xFF9AD1F8)), onPressed: () {}),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('拍照辨識藥袋', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _takeMedicinePhoto,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black87, width: 2)),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.add, size: 32, color: Colors.black87),
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