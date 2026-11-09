import 'package:flutter_test/flutter_test.dart';
import 'package:projectfront/medicine/medicine_models.dart';
import 'package:projectfront/medicine/medicine_parser.dart';

void main() {
  // 使用虛構文字重現測試照片的預印選單，不將個人照片／姓名放入專案。
  test('多個印刷次數及括號用法不會採用第一筆', () {
    final draft = MedicineParser.parse('''
示範診所
藥品及含量見袋內
□1日4次，三餐飯後(前)及睡前各服用
✓1日3次，三餐飯後(前)各服用
□1日4次，每天6小時服用一次
□1日2次，早晚飯後(前)各服用
□1日1次，睡前服用
調劑處方醫師：測試
1.請核對藥袋姓名
''').single;
    expect(draft.name, isEmpty);
    expect(draft.amount, isEmpty);
    expect(draft.frequency, isNull);
    expect(draft.meal, isEmpty);
    expect(draft.days, isNull);
    expect(
      draft.issues.map((issue) => issue.field).toSet(),
      requiredMedicineReviewFields.toSet(),
    );
    expect(
      draft.issues
          .firstWhere((issue) => issue.field == MedicineReviewField.frequency)
          .candidates,
      containsAll(['每日 4 次', '每日 3 次', '每日 2 次', '每天6小時']),
    );
  });

  test('清楚的單項處方可預填，衛教文字不改變用法', () {
    final draft = MedicineParser.parse('''
測試診所
藥名：示範藥品
每次半錠
每日二次 飯後
療程：三天
1.請核對藥袋姓名
4.飯前(後)服用是指飯前(後)30分鐘
''').single;
    expect(draft.name, '示範藥品');
    expect(draft.amount, '0.5');
    expect(draft.unit, '錠');
    expect(draft.frequency, 2);
    expect(draft.meal, '飯後');
    expect(draft.days, 3);
    expect(draft.issues, isEmpty);
    expect(draft.rawText, contains('30分鐘'));
  });

  test('多個劑量與療程保留衝突，不能各拿第一個', () {
    final draft = MedicineParser.parse('藥名：示範\n每次1錠\n每次2錠\n療程3天\n療程5天').single;
    expect(draft.amount, isEmpty);
    expect(draft.unit, isEmpty);
    expect(draft.days, isNull);
    expect(
      draft.issues
          .firstWhere((i) => i.field == MedicineReviewField.amount)
          .candidates,
      ['1 錠', '2 錠'],
    );
  });

  test('即使數字相同，多列選項仍需核對', () {
    final draft = MedicineParser.parse('□1日1次 飯後服用\n□1日1次 睡前服用').single;
    expect(draft.frequency, isNull);
    expect(draft.meal, isEmpty);
  });

  test('間隔小時不能自動換成每日固定提醒', () {
    final draft = MedicineParser.parse('藥名：示範\n每日4次，每6小時服用').single;
    expect(draft.frequency, isNull);
    expect(draft.issues.any((i) => i.message.contains('間隔服用')), isTrue);
  });

  test('只裁到一個未確認的勾選框也不能視為已選取', () {
    final draft = MedicineParser.parse('□1日3次 飯後服用').single;
    expect(draft.frequency, isNull);
    expect(draft.meal, isEmpty);
  });

  test('多藥不串用量，支援全形數字', () {
    final drafts = MedicineParser.parse(
      '藥名：甲\n每次１錠\n每日２次 飯後\n療程３天\n藥名：乙\n每次２包\n每日１次 睡前\n療程５天',
    );
    expect(drafts.length, 2);
    expect(drafts[0].amount, '1');
    expect(drafts[0].frequency, 2);
    expect(drafts[1].amount, '2');
    expect(drafts[1].unit, '包');
    expect(drafts[1].days, 5);
  });

  test('原圖／校正圖與疑點可序列化，舊資料仍能讀取', () {
    final plan = MedicinePlan(
      name: '示範',
      clinic: '',
      amount: 1,
      unit: '錠',
      meal: '未註明',
      times: [480],
      startDate: DateTime(2026, 10, 27),
      photoPath: 'original.image',
      correctedPhotoPath: 'corrected.image',
      reviewIssues: const [
        MedicineReviewIssue(
          MedicineReviewField.frequency,
          '多個候選',
          candidates: ['每日 1 次', '每日 3 次'],
        ),
      ],
    );
    final restored = MedicinePlan.fromJson(plan.toJson());
    expect(restored.correctedPhotoPath, 'corrected.image');
    expect(restored.reviewIssues.single.candidates.length, 2);
    final legacy = plan.toJson()
      ..remove('correctedPhotoPath')
      ..remove('reviewIssues');
    expect(MedicinePlan.fromJson(legacy).correctedPhotoPath, isNull);
    expect(MedicinePlan.fromJson(legacy).reviewIssues, isEmpty);
  });

  test('不需要藥名即可建立可辨識的用藥標題', () {
    expect(medicinePlanDisplayName(''), '藥袋用藥');
    expect(medicinePlanDisplayName('  示範診所  '), '示範診所用藥');
    final draft = MedicineParser.parse('每次1錠\n每日2次 飯後\n療程3天').single;
    expect(draft.name, isEmpty);
    expect(draft.issues, isEmpty);
  });
}
