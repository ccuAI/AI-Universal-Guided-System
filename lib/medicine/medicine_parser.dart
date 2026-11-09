import 'medicine_models.dart';

/// 保守地整理文字候選，不判斷手寫勾選、不猜測被筆跡遮住的藥名或劑量。
/// 多個候選、印刷選項或間隔服用指示一律交給人工核對，不能取第一筆代替處方。
class MedicineParser {
  static final _nameMarker = RegExp(r'(?:藥品名稱|藥物名稱|藥名|品名)\s*[:：]');
  static const _numbers = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '十': 10,
  };
  static int? _number(String? text) =>
      text == null ? null : int.tryParse(text) ?? _numbers[text];

  static List<MedicineDraft> parse(String rawText) {
    // 全形數字只做字形正規化，不能把 O／I 等模糊字元自動猜成數字。
    var text = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAllMapped(
      RegExp('[０-９]'),
      (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xfee0),
    );
    final clinic =
        RegExp(r'([^\n]{1,50}(?:診所|醫院))').firstMatch(text)?.group(1)?.trim() ??
        '';
    // 不直接依「注意事項」切斷，多欄 OCR 可能先讀到旁邊直排標題。
    // 藥師與衛教段落不當成個人服藥指示；原始全文仍完整保留供比對。
    final footer = RegExp(r'調劑處方醫師|[1１][.．、]\s*請核對|[2２][.．、]\s*藥品請放置')
        .firstMatch(text);
    if (footer != null) text = text.substring(0, footer.start);
    final markers = _nameMarker.allMatches(text).toList();
    if (markers.length < 2) return [_parseOne(text, clinic, rawText)];
    return List.generate(
      markers.length,
      (index) => _parseOne(
        text.substring(
          markers[index].start,
          index + 1 < markers.length ? markers[index + 1].start : text.length,
        ),
        clinic,
        rawText,
      ),
    );
  }

  static MedicineDraft _parseOne(String text, String clinic, String original) {
    final issues = <MedicineReviewIssue>[];
    final names = RegExp(r'(?:藥品名稱|藥物名稱|藥名|品名)[ \t]*[:：][ \t]*([^\n]+)')
        .allMatches(text)
        .map(
          (match) =>
              match[1]!.split(RegExp(r'\s+(?:每次|每日|用法|用量|療程)')).first.trim(),
        )
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    // 藥名標籤只協助分開多項候選；沒有藥名不再要求病人補填或人工核對。

    final doses = RegExp(
      r'每次\s*[:：]?\s*(\d+(?:\.\d+)?(?:/\d+)?|半|[一二三四五六七八九十])\s*(錠|顆|粒|包|滴|毫升|mL|ml|公克|克|g)',
    ).allMatches(text).toList();
    final doseLabels = doses
        .map((match) => '${match[1]} ${match[2]}')
        .toSet()
        .toList();
    var amount = '';
    var unit = '';
    if (doseLabels.length == 1) {
      amount = doses.first[1]!;
      unit = doses.first[2]!;
      if (amount == '半') {
        amount = '0.5';
      } else if (amount.contains('/')) {
        final values = amount.split('/').map(double.tryParse).toList();
        amount = values[0] != null && values[1] != null && values[1]! > 0
            ? (values[0]! / values[1]!).toString()
            : '';
      } else if (_numbers.containsKey(amount)) {
        amount = _numbers[amount].toString();
      }
    }
    if (amount.isEmpty) {
      issues.add(
        MedicineReviewIssue(
          MedicineReviewField.amount,
          doseLabels.length > 1
              ? '出現多個每次用量，請對照原圖填寫。'
              : '沒有明確的每次用量與單位，不能從手寫數字猜測。',
          candidates: doseLabels,
        ),
      );
    }

    final frequencies = RegExp(
      r'(?:每日|每天|一天|一日|1\s*日)\s*[:：]?\s*(\d+|[一二三四五六七八九十])\s*次',
    ).allMatches(text).toList();
    final frequencyLabels = frequencies
        .map((match) => '每日 ${_number(match[1])} 次')
        .toSet()
        .toList();
    final intervals = RegExp(r'每(?:隔|天)?\s*\d+\s*(?:小時|分鐘)')
        .allMatches(text)
        .map((m) => m[0]!)
        .toSet()
        .toList();
    // 即使數字相同，多列印刷選項也可能代表「飯後／睡前」兩種不同用法。
    final printedOptions =
        frequencies.length > 1 ||
        RegExp(
          r'^[ \t]*[□☐☑✓✔口][ \t]*(?:1\s*日|一日|每日)',
          multiLine: true,
        ).allMatches(text).isNotEmpty;
    final frequency =
        !printedOptions && intervals.isEmpty && frequencies.length == 1
        ? _number(frequencies.single[1])
        : null;
    if (frequency == null) {
      issues.add(
        MedicineReviewIssue(
          MedicineReviewField.frequency,
          intervals.isNotEmpty
              ? '有間隔服用指示。本版只排每日固定時刻，不能自動換算；請確認適用的提醒方式。'
              : printedOptions
              ? '有多列服藥選項；文字辨識無法確認哪一格被勾選，請自行核對。'
              : '未取得明確每日次數，請核對藥袋。',
          candidates: [...frequencyLabels, ...intervals],
        ),
      );
    }
    final meals = ['飯前', '飯後', '隨餐', '睡前'].where(text.contains).toList();
    // 「飯後(前)」等預印括號不是唯一用法，不能因 OCR 漏字便選另一項。
    final hasMealAlternatives = RegExp(r'飯[前後]\s*[（(]\s*[前後]\s*[）)]')
        .hasMatch(text);
    final meal = !printedOptions && !hasMealAlternatives && meals.length == 1
        ? meals.single
        : '';
    if (meal.isEmpty) {
      issues.add(
        MedicineReviewIssue(
          MedicineReviewField.meal,
          '用法不明或有多種印刷選項，請對照勾選及註記，無法確認時先向藥局查詢。',
          candidates: meals,
        ),
      );
    }
    final days =
        RegExp(r'(?:服用|用藥|療程|給藥日數|天數|共)\s*[:：]?\s*(\d+|[一二三四五六七八九十])\s*(?:天|日)')
            .allMatches(text)
            .map((match) => _number(match[1]))
            .whereType<int>()
            .toSet()
            .toList();
    if (days.length != 1) {
      issues.add(
        MedicineReviewIssue(
          MedicineReviewField.days,
          days.length > 1 ? '出現多個療程天數，請核對。' : '療程天數不明；不要把調劑日期或「一日幾次」當作天數。',
          candidates: days.map((day) => '$day 天').toList(),
        ),
      );
    }
    return MedicineDraft(
      name: names.length == 1 ? names.single : '',
      clinic: clinic,
      amount: amount,
      unit: unit,
      meal: meal,
      frequency: frequency,
      days: days.length == 1 ? days.single : null,
      asNeeded:
          !printedOptions && (text.contains('需要時') || text.contains('必要時')),
      rawText: original,
      issues: issues,
    );
  }
}
