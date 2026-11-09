/// 服藥模組的純資料物件。
///
/// 不在模型內呼叫相機、資料庫或通知，讓畫面、儲存與排程共用同一份資料。
/// 所有排程日期都代表「裝置當地日曆時間」，每天的時間以午夜起算分鐘保存。
library;

DateTime calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateLabel(DateTime value) =>
    '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

String timeLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// 畫面不要求病人輸入藥品學名；新計畫以診所或通用名稱標示。
/// name 仍作為資料庫／通知標題欄位，避免破壞既有計畫與歷史快照。
String medicinePlanDisplayName(String clinic) =>
    clinic.trim().isEmpty ? '藥袋用藥' : '${clinic.trim()}用藥';

/// 一項「已由使用者確認」的用藥計畫；OCR 草稿不能直接轉成通知。
class MedicinePlan {
  const MedicinePlan({
    this.id = 0,
    required this.name,
    required this.clinic,
    required this.amount,
    required this.unit,
    required this.meal,
    required this.times,
    required this.startDate,
    this.endDate,
    this.asNeeded = false,
    this.enabled = true,
    this.rawText = '',
    this.notes = '',
    this.photoPath,
    this.correctedPhotoPath,
    this.reviewIssues = const [],
  });

  final int id;
  final String name;
  final String clinic;
  final double amount;
  final String unit;
  final String meal;
  final List<int> times;
  final DateTime startDate;
  final DateTime? endDate;
  final bool asNeeded;
  final bool enabled;
  final String rawText;
  final String notes;
  final String? photoPath;

  /// 原始照片與校正照片分開保存；舊資料沒有校正照片時仍可正常讀取。
  final String? correctedPhotoPath;
  final List<MedicineReviewIssue> reviewIssues;

  String get doseLabel =>
      '${amount == amount.roundToDouble() ? amount.toInt() : amount} $unit';

  bool appliesOn(DateTime date) {
    final day = calendarDay(date);
    return enabled &&
        !day.isBefore(calendarDay(startDate)) &&
        (endDate == null || !day.isAfter(calendarDay(endDate!)));
  }

  MedicinePlan withIdentity(
    int identity,
    String? imagePath, [
    String? correctedPath,
  ]) => MedicinePlan.fromJson({
    ...toJson(),
    'id': identity,
    'photoPath': imagePath,
    'correctedPhotoPath': correctedPath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'clinic': clinic,
    'amount': amount,
    'unit': unit,
    'meal': meal,
    'times': times,
    'startDate': calendarDay(startDate).toIso8601String(),
    'endDate': endDate == null ? null : calendarDay(endDate!).toIso8601String(),
    'asNeeded': asNeeded,
    'enabled': enabled,
    'rawText': rawText,
    'notes': notes,
    'photoPath': photoPath,
    'correctedPhotoPath': correctedPhotoPath,
    'reviewIssues': reviewIssues.map((issue) => issue.toJson()).toList(),
  };

  factory MedicinePlan.fromJson(Map<String, dynamic> json) => MedicinePlan(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    clinic: json['clinic'] as String,
    amount: (json['amount'] as num).toDouble(),
    unit: json['unit'] as String,
    meal: json['meal'] as String,
    times: (json['times'] as List)
        .map((value) => (value as num).toInt())
        .toList(),
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: json['endDate'] == null
        ? null
        : DateTime.parse(json['endDate'] as String),
    asNeeded: json['asNeeded'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
    rawText: json['rawText'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    photoPath: json['photoPath'] as String?,
    correctedPhotoPath: json['correctedPhotoPath'] as String?,
    reviewIssues: (json['reviewIssues'] as List? ?? const [])
        .map(
          (value) => MedicineReviewIssue.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList(),
  );
}

/// 每次預定服藥的獨立事件。
///
/// 保存用藥標題、用量、用法快照，因此修改或刪除計畫後，既有紀錄仍保留原貌。
class MedicineDose {
  const MedicineDose({
    required this.id,
    required this.planId,
    required this.name,
    required this.doseLabel,
    required this.meal,
    required this.scheduledAt,
    this.status = 'pending',
    this.recordedAt,
    this.asNeeded = false,
  });

  final int id;
  final int planId;
  final String name;
  final String doseLabel;
  final String meal;
  final DateTime scheduledAt;
  final String status;
  final DateTime? recordedAt;
  final bool asNeeded;

  Map<String, dynamic> toRow() => {
    'id': id,
    'plan_id': planId,
    'name': name,
    'dose_label': doseLabel,
    'meal': meal,
    'scheduled_at': scheduledAt.toIso8601String(),
    'status': status,
    'recorded_at': recordedAt?.toIso8601String(),
    'as_needed': asNeeded ? 1 : 0,
  };

  factory MedicineDose.fromRow(Map<String, dynamic> row) => MedicineDose(
    id: (row['id'] as num).toInt(),
    planId: (row['plan_id'] as num).toInt(),
    name: row['name'] as String,
    doseLabel: row['dose_label'] as String,
    meal: row['meal'] as String,
    scheduledAt: DateTime.parse(row['scheduled_at'] as String),
    status: row['status'] as String,
    recordedAt: row['recorded_at'] == null
        ? null
        : DateTime.parse(row['recorded_at'] as String),
    asNeeded: row['as_needed'] == 1,
  );
}

/// OCR 擷取出的候選值。空白代表未知，不能自行猜測藥名、劑量或療程。
class MedicineDraft {
  const MedicineDraft({
    this.name = '',
    this.clinic = '',
    this.amount = '',
    this.unit = '',
    this.meal = '',
    this.frequency,
    this.days,
    this.asNeeded = false,
    this.rawText = '',
    this.issues = const [],
  });

  final String name;
  final String clinic;
  final String amount;
  final String unit;
  final String meal;
  final int? frequency;
  final int? days;
  final bool asNeeded;
  final String rawText;
  final List<MedicineReviewIssue> issues;
}

/// 一個核對欄位可能同時有多個候選，或完全沒有足夠線索。
/// 不使用虛構的信心分數；候選和原因都來自實際辨識到的文字。
enum MedicineReviewField { name, amount, meal, frequency, days }

/// name 僅保留給舊資料解碼，不再是病人必須填寫或核對的欄位。
const requiredMedicineReviewFields = [
  MedicineReviewField.amount,
  MedicineReviewField.meal,
  MedicineReviewField.frequency,
  MedicineReviewField.days,
];

class MedicineReviewIssue {
  const MedicineReviewIssue(
    this.field,
    this.message, {
    this.candidates = const [],
  });
  final MedicineReviewField field;
  final String message;
  final List<String> candidates;

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'message': message,
    'candidates': candidates,
  };

  factory MedicineReviewIssue.fromJson(Map<String, dynamic> value) =>
      MedicineReviewIssue(
        MedicineReviewField.values.byName(value['field'] as String),
        value['message'] as String,
        candidates: (value['candidates'] as List? ?? const []).cast<String>(),
      );
}
