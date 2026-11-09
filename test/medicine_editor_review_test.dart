import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:projectfront/medicine/medicine_editor_page.dart';
import 'package:projectfront/medicine/medicine_parser.dart';
import 'package:projectfront/medicine/medicine_photo_comparison.dart';

void main() {
  testWidgets('移除逐欄提示後可直接最終確認，修改用量仍會撤銷確認', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = MedicineParser.parse('每次1錠\n需要時服用 飯後\n療程3天').single;
    await tester.pumpWidget(
      MaterialApp(home: MedicineEditorPage(draft: draft)),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '藥品名稱'), findsNothing);
    expect(find.byKey(const ValueKey('review-name')), findsNothing);
    for (final field in ['amount', 'meal', 'frequency', 'days']) {
      expect(find.byKey(ValueKey('review-$field')), findsNothing);
    }
    expect(find.textContaining('逐欄核對：'), findsNothing);
    final finalReview = find.byKey(const ValueKey('review-all'));
    await tester.ensureVisible(finalReview);
    expect(tester.widget<CheckboxListTile>(finalReview).onChanged, isNotNull);
    await tester.tap(finalReview);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(finalReview).value, isTrue);
    final amount = find.widgetWithText(TextFormField, '每次用量');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '2');
    await tester.pump();
    await tester.ensureVisible(finalReview);
    expect(tester.widget<CheckboxListTile>(finalReview).value, isFalse);
    expect(tester.widget<CheckboxListTile>(finalReview).onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手機表單捲動時照片仍固定顯示，可開啟全螢幕', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 20, height: 20)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MedicineEditorPage(
          photoBytes: bytes,
          correctedPhotoBytes: bytes,
          draft: MedicineParser.parse('藥名：版面測試\n每次1錠').single,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final photo = find.byType(MedicinePhotoComparison);
    final position = tester.getTopLeft(photo);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(photo), position);
    await tester.tap(find.byTooltip('全螢幕放大照片'));
    await tester.pumpAndSettle();
    expect(find.text('放大對照藥袋'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('移除提示卡片後，缺少用量與單位仍無法保存', (tester) async {
    tester.view.physicalSize = const Size(1000, 2500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = MedicineParser.parse('需要時服用 飯後\n療程3天').single;
    await tester.pumpWidget(
      MaterialApp(home: MedicineEditorPage(draft: draft)),
    );
    await tester.pumpAndSettle();
    final finalReview = find.byKey(const ValueKey('review-all'));
    await tester.ensureVisible(finalReview);
    expect(tester.widget<CheckboxListTile>(finalReview).onChanged, isNotNull);
    await tester.tap(finalReview);
    await tester.pump();
    // 點保存直接驗證必填欄位，確認隱藏提示卡片沒有略過輸入驗證。
    final save = find.byKey(const ValueKey('save-medicine-plan'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('請填寫大於零的用量'), findsOneWidget);
    expect(find.text('請填寫單位'), findsOneWidget);
    expect(find.byType(MedicineEditorPage), findsOneWidget);
    expect(find.textContaining('沒有明確的每次用量'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多列選項不顯示提示卡片，未知用法與次數仍須填寫', (tester) async {
    tester.view.physicalSize = const Size(1000, 2500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = MedicineParser.parse('□1日4次 飯後(前)\n✓1日3次 飯後(前)').single;
    await tester.pumpWidget(
      MaterialApp(home: MedicineEditorPage(draft: draft)),
    );
    await tester.pumpAndSettle();
    final frequency = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(frequency);
    expect(
      tester.widget<DropdownButtonFormField<int>>(frequency).initialValue,
      isNull,
    );
    expect(find.textContaining('文字辨識無法確認哪一格被勾選'), findsNothing);
    expect(find.byKey(const ValueKey('review-frequency')), findsNothing);
    // 解析歧義時不自動挑選第一個值，保存時仍要求使用者補完欄位。
    final save = find.byKey(const ValueKey('save-medicine-plan'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('請確認用法'), findsOneWidget);
    expect(find.text('請確認每日次數'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
