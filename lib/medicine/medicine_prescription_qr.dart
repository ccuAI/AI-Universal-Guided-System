import 'dart:convert';

import 'medicine_models.dart';

/// 醫師藥單 QR code 的格式與轉換。
///
/// QR 內容為 `AIGSRX1:` 加上 UTF-8 JSON 的 base64url（無補位）。
/// 全部使用 ASCII，避免掃描器把中文位元組誤判成其他編碼。
/// 只放建立提醒所需的資料；病人姓名、病歷號只印在紙本藥單，不進 QR code。
///
/// JSON 欄位（醫師端 doctor_portal/index.html 產生，必須與此處一致）：
/// ```
/// {
///   "v": 1,                      格式版本
///   "id": "RX-20261121-AB12CD",  藥單編號，用來避免重複匯入
///   "c": "仁愛診所",              診所／醫院
///   "dr": "王醫師",               醫師（選填）
///   "vd": "2026-11-21",          看診日期
///   "s": "2026-11-21",           開始服藥日（選填，預設看診日期）
///   "m": [{
///     "n": "Amlodipine 5mg",     藥名（選填，顯示於通知標題）
///     "a": 1, "u": "錠",          每次用量與單位
///     "w": "飯後",                用法，限 medicinePrescriptionMeals
///     "t": ["08:00", "20:00"],   每日提醒時間；需要時服用為空陣列
///     "p": false,                需要時服用
///     "days": 7,                 療程天數（含開始日），與 "lt" 二選一
///     "lt": false,               長期用藥
///     "note": "飯後多喝水"         醫囑備註（選填）
///   }]
/// }
/// ```
const medicinePrescriptionPrefix = 'AIGSRX1:';
const medicinePrescriptionVersion = 1;

/// 與確認表單的用法選項一致，匯入後仍可在表單中修改。
const medicinePrescriptionMeals = ['飯前', '飯後', '隨餐', '睡前', '依藥袋指示', '未註明'];

class MedicinePrescriptionItem {
  const MedicinePrescriptionItem({
    this.name = '',
    required this.amount,
    required this.unit,
    required this.meal,
    this.times = const [],
    this.asNeeded = false,
    this.days,
    this.longTerm = false,
    this.note = '',
  });

  final String name;
  final double amount;
  final String unit;
  final String meal;

  /// 每天午夜起算的分鐘，已排序。
  final List<int> times;
  final bool asNeeded;
  final int? days;
  final bool longTerm;
  final String note;

  Map<String, dynamic> toJson() => {
    if (name.isNotEmpty) 'n': name,
    'a': amount == amount.roundToDouble() ? amount.toInt() : amount,
    'u': unit,
    'w': meal,
    't': times.map(timeLabel).toList(),
    'p': asNeeded,
    if (longTerm) 'lt': true else 'days': days,
    if (note.isNotEmpty) 'note': note,
  };
}

class MedicinePrescription {
  const MedicinePrescription({
    required this.id,
    required this.clinic,
    this.doctor = '',
    required this.visitDate,
    required this.startDate,
    required this.items,
  });

  final String id;
  final String clinic;
  final String doctor;
  final DateTime visitDate;
  final DateTime startDate;
  final List<MedicinePrescriptionItem> items;

  /// 主要供測試與日後其他端點使用；醫師端網頁有相同的 JavaScript 實作。
  String encode() {
    final json = jsonEncode({
      'v': medicinePrescriptionVersion,
      'id': id,
      'c': clinic,
      if (doctor.isNotEmpty) 'dr': doctor,
      'vd': _dateText(visitDate),
      's': _dateText(startDate),
      'm': items.map((item) => item.toJson()).toList(),
    });
    return medicinePrescriptionPrefix +
        base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// 依掃描當天轉成用藥計畫。
  ///
  /// 療程以開始日起算的日曆天數計，晚幾天掃描只會建立剩餘天數的提醒；
  /// 已結束的項目不建立，以免產生沒有任何提醒的計畫。
  List<MedicinePlan> toPlans(DateTime today) {
    final day = calendarDay(today);
    final plans = <MedicinePlan>[];
    for (final item in items) {
      final end = item.longTerm
          ? null
          : DateTime(
              startDate.year,
              startDate.month,
              startDate.day + item.days! - 1,
            );
      if (end != null && end.isBefore(day)) continue;
      final source = [
        '醫師藥單 $id',
        '看診日 ${dateLabel(visitDate)}',
        if (doctor.isNotEmpty) '醫師 $doctor',
        if (item.name.isNotEmpty) '藥名 ${item.name}',
      ].join('｜');
      plans.add(
        MedicinePlan(
          name: item.name.isNotEmpty
              ? item.name
              : medicinePlanDisplayName(clinic),
          clinic: clinic,
          amount: item.amount,
          unit: item.unit,
          meal: item.meal,
          times: item.asNeeded ? const [] : item.times,
          startDate: startDate,
          endDate: end,
          asNeeded: item.asNeeded,
          rawText: source,
          notes: item.note,
          prescriptionId: id,
        ),
      );
    }
    return plans;
  }

  /// 解析掃描到的文字；任何欄位不符合都整張拒絕，不猜測或部分採用。
  static MedicinePrescription decode(String raw) {
    final text = raw.trim();
    if (!text.startsWith(medicinePrescriptionPrefix)) {
      throw const FormatException('這不是吃藥小助手的醫師藥單 QR code。');
    }
    final Object? json;
    try {
      final body = text.substring(medicinePrescriptionPrefix.length);
      json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(body))),
      );
    } catch (_) {
      throw const FormatException('藥單 QR code 內容不完整，請重新掃描或請診所重新列印。');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('藥單內容格式錯誤。');
    }
    if (json['v'] != medicinePrescriptionVersion) {
      throw const FormatException('藥單格式版本不支援，請更新 App。');
    }
    final id = _text(json, 'id', required: true, max: 64);
    final clinic = _text(json, 'c', required: true, max: 40);
    final doctor = _text(json, 'dr', max: 40);
    final visit = _date(json['vd'], '看診日期');
    final start = json['s'] == null ? visit : _date(json['s'], '開始服藥日');
    final today = calendarDay(DateTime.now());
    if (start.isAfter(DateTime(today.year, today.month, today.day + 365))) {
      throw const FormatException('開始服藥日超過一年後，請向診所確認。');
    }
    final rawItems = json['m'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 20) {
      throw const FormatException('藥單需要 1～20 項用藥。');
    }
    final items = <MedicinePrescriptionItem>[];
    for (var index = 0; index < rawItems.length; index++) {
      final value = rawItems[index];
      if (value is! Map<String, dynamic>) {
        throw FormatException('第 ${index + 1} 項用藥格式錯誤。');
      }
      items.add(_item(value, index + 1));
    }
    return MedicinePrescription(
      id: id,
      clinic: clinic,
      doctor: doctor,
      visitDate: visit,
      startDate: start,
      items: items,
    );
  }

  static MedicinePrescriptionItem _item(Map<String, dynamic> json, int index) {
    FormatException fail(String message) =>
        FormatException('第 $index 項：$message');
    final amount = json['a'];
    if (amount is! num || !amount.isFinite || amount <= 0 || amount > 1000) {
      throw fail('每次用量需大於 0。');
    }
    final String unit;
    final String meal;
    final String name;
    final String note;
    try {
      name = _text(json, 'n', max: 60);
      unit = _text(json, 'u', required: true, max: 10);
      meal = _text(json, 'w', required: true, max: 10);
      note = _text(json, 'note', max: 200);
    } on FormatException catch (error) {
      throw fail(error.message);
    }
    if (!medicinePrescriptionMeals.contains(meal)) throw fail('用法「$meal」不支援。');
    final asNeeded = json['p'] == true;
    final rawTimes = json['t'] ?? const [];
    if (rawTimes is! List) throw fail('提醒時間格式錯誤。');
    final times = <int>[];
    for (final value in rawTimes) {
      final match = value is String
          ? RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value)
          : null;
      if (match == null) throw fail('提醒時間「$value」格式錯誤。');
      times.add(int.parse(match[1]!) * 60 + int.parse(match[2]!));
    }
    if (times.toSet().length != times.length) throw fail('提醒時間重複。');
    if (asNeeded && times.isNotEmpty) throw fail('需要時服用不能設定固定提醒時間。');
    if (!asNeeded && (times.isEmpty || times.length > 12)) {
      throw fail('每日需要 1～12 個提醒時間。');
    }
    final longTerm = json['lt'] == true;
    final days = json['days'];
    if (longTerm == (days != null)) throw fail('請擇一設定療程天數或長期用藥。');
    if (!longTerm && (days is! int || days < 1 || days > 365)) {
      throw fail('療程天數需為 1～365 天。');
    }
    return MedicinePrescriptionItem(
      name: name,
      amount: amount.toDouble(),
      unit: unit,
      meal: meal,
      times: times..sort(),
      asNeeded: asNeeded,
      days: longTerm ? null : days as int,
      longTerm: longTerm,
      note: note,
    );
  }

  static String _text(
    Map<String, dynamic> json,
    String key, {
    bool required = false,
    required int max,
  }) {
    final value = json[key];
    if (value == null && !required) return '';
    if (value is! String || (required && value.trim().isEmpty)) {
      throw FormatException('缺少必要欄位（$key）。');
    }
    if (value.trim().length > max) throw FormatException('欄位 $key 過長。');
    return value.trim();
  }

  static DateTime _date(Object? value, String label) {
    final match = value is String
        ? RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value)
        : null;
    if (match != null) {
      final date = DateTime(
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
      );
      // 拒絕 2026-02-30 這類會被 DateTime 自動進位的日期。
      if (date.month == int.parse(match[2]!) &&
          date.day == int.parse(match[3]!)) {
        return date;
      }
    }
    throw FormatException('$label格式錯誤。');
  }

  static String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
