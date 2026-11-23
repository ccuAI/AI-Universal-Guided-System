import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:projectfront/medicine/medicine_models.dart';
import 'package:projectfront/medicine/medicine_prescription_qr.dart';

String _code(Map<String, dynamic> json) =>
    medicinePrescriptionPrefix +
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

Map<String, dynamic> _sample({List<Map<String, dynamic>>? items}) => {
  'v': 1,
  'id': 'RX-20261121-TEST01',
  'c': '仁愛診所',
  'dr': '王醫師',
  'vd': '2026-11-21',
  's': '2026-11-21',
  'm':
      items ??
      [
        {
          'n': 'Amlodipine 5mg',
          'a': 1,
          'u': '錠',
          'w': '飯後',
          't': ['20:00', '08:00'],
          'p': false,
          'days': 7,
        },
        {'a': 0.5, 'u': '錠', 'w': '睡前', 't': [], 'p': true, 'lt': true},
      ],
};

void main() {
  test('解析中文藥單並轉成用藥計畫', () {
    final rx = MedicinePrescription.decode(_code(_sample()));
    expect(rx.clinic, '仁愛診所');
    expect(rx.items.first.times, [480, 1200]);
    final plans = rx.toPlans(DateTime(2026, 11, 21, 9));
    expect(plans, hasLength(2));
    expect(plans.first.name, 'Amlodipine 5mg');
    expect(plans.first.endDate, DateTime(2026, 11, 27));
    expect(plans.first.prescriptionId, 'RX-20261121-TEST01');
    expect(plans.first.rawText, contains('醫師藥單 RX-20261121-TEST01'));
    expect(plans.last.name, medicinePlanDisplayName('仁愛診所'));
    expect(plans.last.asNeeded, isTrue);
    expect(plans.last.endDate, isNull);
    expect(plans.last.doseLabel, '0.5 錠');
  });

  test('可解析醫師端網頁實際產生的藥單代碼', () {
    // doctor_portal/index.html 於 2026-11-21 產生；格式變更時兩端必須一起更新。
    const fromPortal =
        'AIGSRX1:eyJ2IjoxLCJpZCI6IlJYLTIwMjYxMTIxLTQ2MERCRDdGIiwiYyI6IuS7geaEm-iouuaJgCIsImRyIjoi546L5bCP5piOIiwidmQiOiIyMDI2LTExLTIxIiwicyI6IjIwMjYtMTEtMjEiLCJtIjpbeyJhIjoxLCJ1Ijoi6YygIiwidyI6Iumjr-W-jCIsInQiOlsiMDg6MDAiLCIyMDowMCJdLCJwIjpmYWxzZSwibiI6IkFtbG9kaXBpbmUgNW1nIiwiZGF5cyI6N30seyJhIjowLjUsInUiOiLpjKAiLCJ3Ijoi6aOv5b6MIiwidCI6W10sInAiOnRydWUsImx0Ijp0cnVlfSx7ImEiOjEsInUiOiLpjKAiLCJ3Ijoi552h5YmNIiwidCI6WyIyMTowMCJdLCJwIjpmYWxzZSwibiI6IuiDg-iXpSIsImRheXMiOjMsIm5vdGUiOiLnnaHliY3muqvmsLTmnI3nlKgifV19';
    final rx = MedicinePrescription.decode(fromPortal);
    expect(rx.id, 'RX-20261121-460DBD7F');
    expect(rx.clinic, '仁愛診所');
    expect(rx.doctor, '王小明');
    expect(rx.items, hasLength(3));
    expect(rx.items[0].times, [480, 1200]);
    expect(rx.items[1].asNeeded && rx.items[1].longTerm, isTrue);
    expect(rx.items[2].note, '睡前溫水服用');
    final plans = rx.toPlans(DateTime(2026, 11, 21));
    expect(plans.map((plan) => plan.name), ['Amlodipine 5mg', '仁愛診所用藥', '胃藥']);
    expect(plans[2].endDate, DateTime(2026, 11, 23));
  });

  test('Dart 編碼後可解回相同內容', () {
    final rx = MedicinePrescription.decode(_code(_sample()));
    final again = MedicinePrescription.decode(rx.encode());
    expect(again.encode(), rx.encode());
    expect(again.items.last.longTerm, isTrue);
  });

  test('model JSON 保留藥單編號，舊資料沒有此欄位仍可讀取', () {
    final plan = MedicinePrescription.decode(_code(_sample()))
        .toPlans(DateTime(2026, 11, 21))
        .first;
    expect(
      MedicinePlan.fromJson(plan.toJson()).prescriptionId,
      plan.prescriptionId,
    );
    final old = plan.toJson()..remove('prescriptionId');
    expect(MedicinePlan.fromJson(old).prescriptionId, isNull);
  });

  test('晚幾天掃描只保留剩餘療程，已結束的項目不建立', () {
    final rx = MedicinePrescription.decode(_code(_sample()));
    expect(rx.toPlans(DateTime(2026, 11, 27)), hasLength(2));
    final later = rx.toPlans(DateTime(2026, 11, 28));
    expect(later, hasLength(1));
    expect(later.single.asNeeded, isTrue);
  });

  test('拒絕非本系統或損壞的 QR code', () {
    expect(
      () => MedicinePrescription.decode('https://example.com'),
      throwsFormatException,
    );
    expect(
      () => MedicinePrescription.decode('${medicinePrescriptionPrefix}abc!'),
      throwsFormatException,
    );
    expect(
      () => MedicinePrescription.decode(_code({..._sample(), 'v': 2})),
      throwsFormatException,
    );
  });

  Map<String, dynamic> item(Map<String, dynamic> change) => {
    'a': 1,
    'u': '錠',
    'w': '飯後',
    't': ['08:00'],
    'p': false,
    'days': 3,
    ...change,
  };

  for (final entry in {
    '用量為 0': item({'a': 0}),
    '用法不在選項中': item({'w': 'BID'}),
    '時間格式錯誤': item({
      't': ['8:00'],
    }),
    '時間重複': item({
      't': ['08:00', '08:00'],
    }),
    '固定服用卻沒有時間': item({'t': []}),
    '需要時服用卻有時間': item({'p': true}),
    '同時設定天數與長期': item({'lt': true}),
    '天數超過 365': item({'days': 400}),
    '缺少單位': item({'u': ''}),
  }.entries) {
    test('拒絕：${entry.key}', () {
      expect(
        () => MedicinePrescription.decode(_code(_sample(items: [entry.value]))),
        throwsFormatException,
      );
    });
  }

  test('拒絕不存在的日期與空藥單', () {
    expect(
      () => MedicinePrescription.decode(
        _code({..._sample(), 'vd': '2026-02-30'}),
      ),
      throwsFormatException,
    );
    expect(
      () => MedicinePrescription.decode(_code(_sample(items: []))),
      throwsFormatException,
    );
  });
}
