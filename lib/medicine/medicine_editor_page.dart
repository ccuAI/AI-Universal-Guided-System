import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'medicine_models.dart';
import 'medicine_repository.dart';
import 'medicine_photo_comparison.dart';

/// OCR／手動輸入／編輯共用的確認表單。
///
/// OCR 只能預填候選值。未知欄位保持空白，每個提醒時間都由使用者親自選擇；
/// 表單只保留最後一次核對勾選；通過欄位驗證後才保存，通知由上一頁同步。
class MedicineEditorPage extends StatefulWidget {
  const MedicineEditorPage({
    super.key,
    this.draft = const MedicineDraft(),
    this.plan,
    this.photoBytes,
    this.correctedPhotoBytes,
    this.title = '確認用藥資料',
  });
  final MedicineDraft draft;
  final MedicinePlan? plan;
  final Uint8List? photoBytes;
  final Uint8List? correctedPhotoBytes;
  final String title;

  @override
  State<MedicineEditorPage> createState() => _MedicineEditorPageState();
}

class _MedicineEditorPageState extends State<MedicineEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _clinic;
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  late final TextEditingController _days;
  late final TextEditingController _notes;
  late DateTime _start;
  DateTime? _end;
  String? _meal;
  int? _frequency;
  List<int?> _times = [];
  bool _asNeeded = false;
  bool _longTerm = false;
  bool _confirmed = false;
  bool _saving = false;
  // 舊計畫仍保留 OCR 解析問題供資料相容；表單不再顯示逐欄提示卡片。
  List<MedicineReviewIssue> get _issues =>
      (widget.plan?.reviewIssues ?? widget.draft.issues)
          .where((issue) => requiredMedicineReviewFields.contains(issue.field))
          .toList();
  static const _meals = ['飯前', '飯後', '隨餐', '睡前', '依藥袋指示', '未註明'];

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    final draft = widget.draft;
    _clinic = TextEditingController(text: plan?.clinic ?? draft.clinic);
    _amount = TextEditingController(
      text: plan == null ? draft.amount : plan.amount.toString(),
    );
    _unit = TextEditingController(text: plan?.unit ?? draft.unit);
    _notes = TextEditingController(text: plan?.notes ?? '');
    _start = calendarDay(plan?.startDate ?? DateTime.now());
    _end = plan?.endDate;
    _asNeeded = plan?.asNeeded ?? draft.asNeeded;
    _longTerm = plan != null && plan.endDate == null;
    final meal = plan?.meal ?? draft.meal;
    _meal = _meals.contains(meal) ? meal : null;
    final frequency = plan == null ? draft.frequency : plan.times.length;
    _frequency = frequency != null && frequency >= 1 && frequency <= 12
        ? frequency
        : null;
    _times = plan == null
        ? List<int?>.filled(_frequency ?? 0, null)
        : List<int?>.from(plan.times);

    // 日期差用 UTC 日曆計算，避免夏令時間的 23／25 小時造成少一天。
    final duration = _end == null
        ? draft.days
        : DateTime.utc(_end!.year, _end!.month, _end!.day)
                  .difference(
                    DateTime.utc(_start.year, _start.month, _start.day),
                  )
                  .inDays +
              1;
    _days = TextEditingController(text: duration?.toString() ?? '');
    _updateEnd();
  }

  @override
  void dispose() {
    for (final controller in [_clinic, _amount, _unit, _days, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateEnd() {
    final days = int.tryParse(_days.text);
    _end = !_longTerm && days != null && days > 0 && days <= 365
        ? DateTime(_start.year, _start.month, _start.day + days - 1)
        : null;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickStart() async {
    final today = calendarDay(DateTime.now());
    final first = DateTime(today.year - 2);
    // 目前建立一年內的事件，避免保存過遠的起日卻沒有任何可排程提醒。
    final last = DateTime(today.year, today.month, today.day + 365);
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(first)
          ? first
          : (_start.isAfter(last) ? last : _start),
      firstDate: first,
      lastDate: last,
      helpText: '選擇療程開始日期',
    );
    if (date == null || !mounted) return;
    setState(() {
      _start = calendarDay(date);
      _updateEnd();
      _confirmed = false;
    });
  }

  Future<void> _pickTime(int index) async {
    final minutes = _times[index];
    final time = await showTimePicker(
      context: context,
      initialTime: minutes == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: '選擇第 ${index + 1} 次提醒時間',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _times[index] = time.hour * 60 + time.minute;
      _confirmed = false;
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_meal == null) {
      _message('請確認飯前／飯後等用法；藥袋未註明時可選「未註明」。');
      return;
    }
    if (!_asNeeded &&
        (_frequency == null ||
            _times.length != _frequency ||
            _times.any((time) => time == null))) {
      _message('請確認每日次數，並逐一選擇提醒時間。');
      return;
    }
    if (!_asNeeded && _times.toSet().length != _times.length) {
      _message('同一項用藥的提醒時間不能重複。');
      return;
    }
    if (!_longTerm && _end == null) {
      _message('請填寫療程天數，或明確選擇長期用藥。');
      return;
    }
    if (!_confirmed) {
      _message('請先核對資料並勾選確認。');
      return;
    }
    setState(() => _saving = true);
    try {
      final plan = MedicinePlan(
        id: widget.plan?.id ?? 0,
        // 舊計畫保留既有標題；新計畫自動命名，不要求病人認識藥品名稱。
        name: widget.plan?.name ?? medicinePlanDisplayName(_clinic.text),
        clinic: _clinic.text.trim(),
        amount: double.parse(_amount.text.trim()),
        unit: _unit.text.trim(),
        meal: _meal!,
        times: _asNeeded ? [] : (_times.cast<int>().toList()..sort()),
        startDate: _start,
        endDate: _longTerm ? null : _end,
        asNeeded: _asNeeded,
        enabled: widget.plan?.enabled ?? true,
        rawText: widget.plan?.rawText ?? widget.draft.rawText,
        notes: _notes.text.trim(),
        photoPath: widget.plan?.photoPath,
        correctedPhotoPath: widget.plan?.correctedPhotoPath,
        reviewIssues: _issues,
      );
      final saved = await MedicineRepository.instance.savePlan(
        plan,
        // 編輯時顯示既有照片，但不重複複製；只有新匯入才保存新照片。
        photoBytes: widget.plan == null ? widget.photoBytes : null,
        correctedPhotoBytes: widget.plan == null
            ? widget.correctedPhotoBytes
            : null,
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      debugPrint('保存用藥資料失敗：$error');
      if (mounted) _message('資料保存失敗，請重試；此時尚未建立新的提醒。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) =>
              required && (value?.trim().isEmpty ?? true) ? '請填寫$label' : null,
      onChanged: (value) {
        setState(() {
          _confirmed = false;
        });
        onChanged?.call(value);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rawText = widget.plan?.rawText ?? widget.draft.rawText;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final form = Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (rawText.isNotEmpty)
                    ExpansionTile(
                      title: const Text('查看藥袋辨識原文'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(rawText),
                        ),
                      ],
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('請逐項核對原藥袋。空白欄位需要補填；提醒時間由你確認。'),
                  ),
                  _textField(_clinic, '診所／醫院（選填）'),
                  Row(
                    children: [
                      Expanded(
                        child: _textField(
                          _amount,
                          '每次用量',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          hint: '例如 1 或 0.5',
                          validator: (value) {
                            final amount = double.tryParse(value?.trim() ?? '');
                            return amount == null ||
                                    !amount.isFinite ||
                                    amount <= 0
                                ? '請填寫大於零的用量'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _textField(
                          _unit,
                          '單位',
                          required: true,
                          hint: '錠、顆、包、毫升等',
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _meal,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '用法',
                      border: OutlineInputBorder(),
                    ),
                    items: _meals
                        .map(
                          (meal) =>
                              DropdownMenuItem(value: meal, child: Text(meal)),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (meal) => setState(() {
                            _meal = meal;
                            _confirmed = false;
                          }),
                    validator: (value) => value == null ? '請確認用法' : null,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('需要時服用'),
                    subtitle: const Text('由你主動記錄服用，不建立固定時間通知。'),
                    value: _asNeeded,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _asNeeded = value;
                            _confirmed = false;
                          }),
                  ),
                  if (!_asNeeded) ...[
                    DropdownButtonFormField<int>(
                      initialValue: _frequency,
                      decoration: const InputDecoration(
                        labelText: '每日服用次數',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('每日 ${index + 1} 次'),
                        ),
                      ),
                      onChanged: _saving
                          ? null
                          : (frequency) => setState(() {
                              final old = _times;
                              _frequency = frequency;
                              _times = List.generate(
                                frequency ?? 0,
                                (index) =>
                                    index < old.length ? old[index] : null,
                              );
                              _confirmed = false;
                            }),
                      validator: (value) => value == null ? '請確認每日次數' : null,
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < _times.length; index++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text('第 ${index + 1} 次提醒'),
                        trailing: OutlinedButton(
                          onPressed: _saving ? null : () => _pickTime(index),
                          child: Text(
                            _times[index] == null
                                ? '選擇時間'
                                : timeLabel(_times[index]!),
                          ),
                        ),
                      ),
                  ],
                  const Divider(height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('療程開始日期'),
                    subtitle: Text(dateLabel(_start)),
                    trailing: IconButton(
                      tooltip: '選擇開始日期',
                      onPressed: _saving ? null : _pickStart,
                      icon: const Icon(Icons.calendar_month),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('長期用藥，沒有結束日期'),
                    value: _longTerm,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _longTerm = value;
                            _updateEnd();
                            _confirmed = false;
                          }),
                  ),
                  if (!_longTerm) ...[
                    _textField(
                      _days,
                      '療程天數',
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final days = int.tryParse(value ?? '');
                        return days == null || days < 1 || days > 365
                            ? '請填寫 1 到 365 天'
                            : null;
                      },
                      onChanged: (_) => setState(_updateEnd),
                    ),
                    Text(
                      _end == null
                          ? '尚未確認結束日期'
                          : '最後一天：${dateLabel(_end!)}（含開始日）',
                    ),
                  ],
                  const SizedBox(height: 20),
                  _textField(_notes, '備註（選填）', maxLines: 3),
                  CheckboxListTile(
                    key: const ValueKey('review-all'),
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    title: const Text('我已核對用量、用法、療程與提醒時間'),
                    controlAffinity: ListTileControlAffinity.leading,
                    // 四個逐欄勾選區塊已移除，最後確認可直接操作。
                    // 保存時仍由 _save 檢查必填值、用量、時間與療程。
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _confirmed = value ?? false),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('save-medicine-plan'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? '正在保存' : '確認並保存'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
            if (widget.photoBytes == null) return form;
            final comparison = MedicinePhotoComparison(
              original: widget.photoBytes!,
              corrected: widget.correctedPhotoBytes,
            );
            // 寬螢幕左右並排；手機上方固定照片，下方表單獨立捲動。
            if (constraints.maxWidth >= 760) {
              return Row(
                children: [
                  Expanded(child: comparison),
                  Expanded(child: form),
                ],
              );
            }
            return Column(
              children: [
                SizedBox(
                  height: (constraints.maxHeight * 0.32).clamp(130.0, 240.0),
                  child: comparison,
                ),
                Expanded(child: form),
              ],
            );
          },
        ),
      ),
    );
  }
}
