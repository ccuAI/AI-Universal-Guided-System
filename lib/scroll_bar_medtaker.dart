import 'package:flutter/material.dart';
import 'dart:io';

// 1. 在此處加入 imagePath 參數接收照片路徑
Widget listForMedicine(int itemCount, String? imagePath) {
  return ListView.builder(
    itemCount: itemCount,
    itemBuilder: (context, index) {
      return ListTile(
        leading: const Icon(Icons.medication, color: Color(0xFF9AD1F8)),
        title: Text('藥品 ${index + 1}'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
        onTap: () {
          // 點擊時同步把 imagePath 傳給底部的彈窗
          showMedicineBottomSheet(context, index + 1, imagePath);
        },
      );
    },
  );
}


// 2. 彈窗函數同步接收 imagePath
void showMedicineBottomSheet(BuildContext context, int medicineNumber, String? imagePath) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // 頂部小灰條
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(height: 20),
                
                // 藥品圖示
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('web/icons/pill_icon.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // 辨識結果詳細標題
                Text(
                  '藥品 $medicineNumber 辨識結果',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const Divider(height: 24),
                
                // 內容詳細列表
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      // 3. 改造第一個項目：如果照片存在，就用卡片排版放大顯示該照片
                      if (imagePath != null && imagePath.isNotEmpty)
                        Card(
                          elevation: 2,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Container(
                            height: 200, // 放大照片的高度
                            width: double.infinity,
                            color: Colors.black12,
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover, // 讓照片填滿容器，裁剪多餘部分
                            ),
                          ),
                        )
                      else
                        const ListTile(
                          leading: Icon(Icons.image_not_supported_outlined),
                          title: Text('無法載入藥袋照片'),
                        ),
                      const SizedBox(height: 12), // 與下方欄位保留間距

                      const ListTile(
                        leading: Icon(Icons.label_outline),
                        title: Text('藥物名稱'),
                        subtitle: Text('普拿疼錠 500 毫克 (Acetaminophen)'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('用藥資訊'),
                        subtitle: Text('每次 1 粒，退燒緩解頭痛。'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.access_time),
                        title: Text('用藥時間'),
                        subtitle: Text('三餐飯後，症狀緩解時可停用。'),
                      ),
                      const ListTile(
                        leading: Icon(Icons.warning_amber_rounded, color: Colors.amber),
                        title: Text('注意事項'),
                        subtitle: Text('請勿與其他含有乙醯胺酚的藥物同時服用，避免飲酒。'),
                      ),
                    ],
                  ),
                )
              ],
            ),
          );
        },
      );
    },
  );
}
