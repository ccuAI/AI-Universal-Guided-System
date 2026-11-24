import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'medicine/medicine_editor_page.dart';
import 'medicine/medicine_models.dart';
import 'medicine/medicine_notification_service.dart';
import 'medicine/medicine_prescription_qr.dart';
import 'medicine/medicine_qr_scan_page.dart';
import 'medicine/medicine_repository.dart';

/// 吃藥小助手的整合頁。
///
/// 三個分頁分別處理今日待服藥、用藥計畫與逐日紀錄。
/// 新增用藥以掃描醫師藥單 QR code 為主，手動新增為輔；已不使用藥袋 OCR。
/// 畫面不直接寫資料庫、不自行推算劑量；分別委派 repository、
/// prescription QR 解析與 notification service，並在每個 await 後確認 mounted。
class MedicineTakerPage extends StatefulWidget {
  const MedicineTakerPage({super.key, this.initialDoseId});
  final int? initialDoseId;

  @override
  State<MedicineTakerPage> createState() => _MedicineTakerPageState();
}

class _MedicineTakerPageState extends State<MedicineTakerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _repository = MedicineRepository.instance;
  final _notifications = MedicineNotificationService.instance;
  late final TabController _tabs;
  List<MedicinePlan> _plans = [];
  List<MedicineDose> _today = [];
  List<MedicineDose> _history = [];
  DateTime _historyDate = calendarDay(DateTime.now());
  String _clinic = '';
  String? _loadError;
  bool _busy = false;
  bool _firstLoad = true;
  Future<void> _reloadQueue = Future.value();
  Timer? _dayTimer;
  DateTime _shownDay = calendarDay(DateTime.now());
  bool _openedNotification = false;
  MedicineReminderStatus _reminders = const MedicineReminderStatus('正在讀取用藥資料…');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_updateTab);
    WidgetsBinding.instance.addObserver(this);
    _reload();
    // 持續開著頁面跨過午夜時刷新今日清單；通知仍由手機系統處理。
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_busy && calendarDay(DateTime.now()) != _shownDay) _reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _updateTab() {
    // 診所篩選只作用於現有計畫與今日清單；歷史可能屬於已刪除的計畫。
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 從設定頁、相機或背景回來時，補齊長期事件並重新檢查通知權限／時區。
    if (state == AppLifecycleState.resumed && !_busy) _reload();
  }

  Future<void> _reload({bool requestPermission = false}) {
    // 把刷新排隊；若背景刷新與保存同時發生，保存後的那次刷新不能被丟掉。
    final task = _reloadQueue.then(
      (_) => _performReload(requestPermission: requestPermission),
    );
    _reloadQueue = task;
    return task;
  }

  Future<void> _performReload({required bool requestPermission}) async {
    if (!mounted) return;
    try {
      await _repository.ensureUpcomingDoses();
      if (!_openedNotification && widget.initialDoseId != null) {
        final dose = await _repository.doseById(widget.initialDoseId!);
        if (!mounted) return;
        if (dose != null) {
          _historyDate = calendarDay(dose.scheduledAt);
          _tabs.index = 2;
        }
        _openedNotification = true;
      }
      final plans = await _repository.plans();
      final today = await _repository.dosesOn(DateTime.now());
      final history = await _repository.dosesOn(_historyDate);
      final status = await _notifications.synchronize(
        requestPermission: requestPermission,
      );
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _today = today;
        _shownDay = calendarDay(DateTime.now());
        _history = history;
        _reminders = status;
        _loadError = null;
        _firstLoad = false;
        if (_clinic.isNotEmpty &&
            !plans.any((plan) => plan.clinic == _clinic)) {
          _clinic = '';
        }
      });
    } catch (error) {
      debugPrint('讀取服藥資料失敗：$error');
      if (mounted) {
        setState(() {
          _loadError = '無法讀取用藥資料，請重新整理。原始資料不會自動清除。';
          _firstLoad = false;
        });
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<MedicinePlan?> _openEditor({
    MedicineDraft draft = const MedicineDraft(),
    MedicinePlan? plan,
    Uint8List? bytes,
    Uint8List? correctedBytes,
    String title = '確認用藥資料',
  }) => Navigator.of(context).push<MedicinePlan>(
    CupertinoPageRoute(
      builder: (_) => MedicineEditorPage(
        draft: draft,
        plan: plan,
        photoBytes: bytes,
        correctedPhotoBytes: correctedBytes,
        title: title,
      ),
    ),
  );

  Future<void> _manual() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await _openEditor();
      await _reload(requestPermission: saved != null);
      if (saved != null) _message('用藥資料已保存。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('掃描醫師藥單 QR code'),
              subtitle: const Text('自動建立用藥計畫與提醒'),
              enabled: MedicineQrScanPage.supported,
              onTap: () => Navigator.pop(context, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('輸入藥單代碼'),
              subtitle: const Text('無法使用相機時，輸入藥單上的代碼'),
              onTap: () => Navigator.pop(context, 'code'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('手動新增用藥'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'manual') await _manual();
    if (action == 'scan') await _scanPrescription();
    if (action == 'code') await _enterPrescriptionCode();
  }

  Future<void> _scanPrescription() async {
    if (_busy) return;
    final raw = await Navigator.of(context).push<String>(
      CupertinoPageRoute(builder: (_) => const MedicineQrScanPage()),
    );
    if (raw != null && mounted) await _importPrescription(raw);
  }

  Future<void> _enterPrescriptionCode() async {
    if (_busy) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _PrescriptionCodeDialog(),
    );
    if (raw != null && raw.trim().isNotEmpty && mounted) {
      await _importPrescription(raw);
    }
  }

  /// 解析藥單並一次建立所有用藥計畫；不經過逐項確認表單。
  /// 建立後顯示摘要，可立即撤銷；之後也能在「用藥計畫」逐項修改。
  Future<void> _importPrescription(String raw) async {
    if (_busy) return;
    final MedicinePrescription prescription;
    try {
      prescription = MedicinePrescription.decode(raw);
    } on FormatException catch (error) {
      await _alert('無法讀取藥單', error.message);
      return;
    }
    final plans = prescription.toPlans(DateTime.now());
    if (plans.isEmpty) {
      await _alert('療程已結束', '這張藥單的所有用藥療程都已結束，沒有建立新的提醒。');
      return;
    }
    setState(() => _busy = true);
    var saved = <MedicinePlan>[];
    try {
      saved = await _repository.importPlans(prescription.id, plans);
    } on DuplicatePrescriptionException {
      if (mounted) setState(() => _busy = false);
      await _alert(
        '這張藥單已經匯入',
        '藥單 ${prescription.id} 的用藥計畫已存在，沒有重複建立。'
            '若要重新匯入，請先在「用藥計畫」刪除原本的項目。',
      );
      return;
    } catch (error) {
      debugPrint('匯入醫師藥單失敗：$error');
      if (mounted) setState(() => _busy = false);
      await _alert('匯入失敗', '資料保存失敗，沒有建立任何提醒，請重試。');
      return;
    }
    try {
      await _reload(requestPermission: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final skipped = prescription.items.length - saved.length;
    final undo = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('已建立 ${saved.length} 項用藥提醒'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${prescription.clinic}'
                '${prescription.doctor.isEmpty ? '' : '・${prescription.doctor}'}'
                '\n看診日 ${dateLabel(prescription.visitDate)}',
              ),
              const SizedBox(height: 12),
              for (final plan in saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '• ${plan.name}：${plan.doseLabel}・${plan.meal}\n'
                    '  ${plan.asNeeded ? '需要時服用' : plan.times.map(timeLabel).join('、')}'
                    '・${plan.endDate == null ? '長期用藥' : '至 ${dateLabel(plan.endDate!)}'}',
                  ),
                ),
              if (skipped > 0) Text('另有 $skipped 項療程已結束，未建立。'),
              const SizedBox(height: 8),
              Text(
                _reminders.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Text('提醒時間可在「用藥計畫」修改。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤銷這次匯入'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    if (undo == true && mounted) {
      await _change(() async {
        for (final plan in saved) {
          await _repository.deletePlan(plan);
        }
      });
      _message('已撤銷這次匯入。');
    }
  }

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(MedicinePlan plan) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _repository.readPhoto(plan.photoPath);
      final corrected = await _repository.readPhoto(plan.correctedPhotoPath);
      if (!mounted) return;
      await _openEditor(
        plan: plan,
        bytes: bytes,
        correctedBytes: corrected,
        title: '修改用藥計畫',
      );
      await _reload();
    } catch (error) {
      debugPrint('編輯用藥資料失敗：$error');
      _message('無法開啟用藥資料，請重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      await _reload();
    } catch (error) {
      debugPrint('更新服藥資料失敗：$error');
      _message('更新失敗，請重試。');
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(MedicinePlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('刪除「${plan.name}」？'),
        content: const Text('將取消後續提醒並移除計畫；既有服藥紀錄會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(() => _repository.deletePlan(plan));
    }
  }

  Future<void> _mark(MedicineDose dose, String status) => _change(() async {
    await _repository.setStatus(dose, status);
    await _notifications.cancelDose(dose.id);
  });

  Future<void> _configureNotifications({bool exact = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _notifications.synchronize(
        requestPermission: true,
        requestExactAlarm: exact,
      );
      if (mounted) setState(() => _reminders = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickHistoryDate() async {
    final today = calendarDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _historyDate,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: '選擇紀錄日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _historyDate = calendarDay(picked));
    await _reload();
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, height: 1.6),
      ),
    ),
  );

  Widget _doseCard(MedicineDose dose) {
    final futureDay = calendarDay(dose.scheduledAt)
        .isAfter(calendarDay(DateTime.now()));
    final status = switch (dose.status) {
      'taken' => '已服用',
      'skipped' => '已跳過',
      _ => dose.scheduledAt.isBefore(DateTime.now()) ? '尚未紀錄' : '待服用',
    };
    final color = dose.status == 'taken'
        ? Colors.green
        : dose.status == 'skipped'
        ? Colors.grey
        : Colors.blue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    dose.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(status, style: TextStyle(color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${dose.asNeeded ? '需要時服用' : timeLabel(dose.scheduledAt.hour * 60 + dose.scheduledAt.minute)}'
              '・${dose.doseLabel}・${dose.meal}',
            ),
            if (dose.recordedAt != null)
              Text(
                '紀錄時間：${dateLabel(dose.recordedAt!)} '
                '${timeLabel(dose.recordedAt!.hour * 60 + dose.recordedAt!.minute)}',
              ),
            const SizedBox(height: 8),
            if (futureDay)
              const Text('未來日期的排程預覽，當天再記錄服用狀態。')
            else if (dose.status == 'pending')
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _mark(dose, 'taken'),
                    icon: const Icon(Icons.check),
                    label: const Text('已服用'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _mark(dose, 'skipped'),
                    child: const Text('跳過'),
                  ),
                ],
              )
            else
              TextButton(
                onPressed: _busy ? null : () => _mark(dose, 'pending'),
                child: Text(dose.asNeeded ? '撤銷這筆紀錄' : '恢復未紀錄'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _todayTab() {
    final ids = _plans
        .where((plan) => _clinic.isEmpty || plan.clinic == _clinic)
        .map((plan) => plan.id)
        .toSet();
    final doses = _today
        .where((dose) => _clinic.isEmpty || ids.contains(dose.planId))
        .toList();
    final prn = _plans
        .where(
          (plan) =>
              plan.asNeeded &&
              plan.appliesOn(DateTime.now()) &&
              (_clinic.isEmpty || plan.clinic == _clinic),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Text(
          '今天・${dateLabel(DateTime.now())}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (doses.isEmpty && prn.isEmpty)
          _empty('今天沒有服藥項目。\n可以掃描醫師藥單 QR code 或手動新增用藥。'),
        ...doses.map(_doseCard),
        for (final plan in prn)
          Card(
            child: ListTile(
              title: Text(plan.name),
              subtitle: Text('需要時服用・${plan.doseLabel}・${plan.meal}'),
              trailing: IconButton(
                tooltip: '記錄已服用',
                icon: const Icon(Icons.add_task),
                onPressed: _busy
                    ? null
                    : () => _change(() => _repository.recordAsNeeded(plan)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _plansTab() {
    final plans = _plans
        .where((plan) => _clinic.isEmpty || plan.clinic == _clinic)
        .toList();
    if (plans.isEmpty) return _empty('尚未建立用藥計畫。\n按下方「新增用藥」開始。');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: plans
          .map(
            (plan) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Switch(
                          value: plan.enabled,
                          onChanged: _busy
                              ? null
                              : (enabled) => _change(() async {
                                  await _repository.savePlan(
                                    MedicinePlan.fromJson({
                                      ...plan.toJson(),
                                      'enabled': enabled,
                                    }),
                                  );
                                }),
                        ),
                      ],
                    ),
                    Text(plan.clinic.isEmpty ? '未標示診所／醫院' : plan.clinic),
                    Text('${plan.doseLabel}・${plan.meal}'),
                    Text(
                      plan.asNeeded
                          ? '需要時服用'
                          : '每日 ${plan.times.length} 次：${plan.times.map(timeLabel).join('、')}',
                    ),
                    Text(
                      '${dateLabel(plan.startDate)} 起'
                      '${plan.endDate == null ? '・長期用藥' : '，至 ${dateLabel(plan.endDate!)}'}',
                    ),
                    if (plan.notes.isNotEmpty) Text('備註：${plan.notes}'),
                    if (!plan.enabled) const Text('已停用。'),
                    if (plan.endDate != null &&
                        calendarDay(plan.endDate!)
                            .isBefore(calendarDay(DateTime.now())))
                      const Text('療程已結束。'),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : () => _edit(plan),
                          icon: const Icon(Icons.edit),
                          label: const Text('修改'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _delete(plan),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('刪除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _historyTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          dateLabel(_historyDate),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('「尚未紀錄」不代表已確認漏服。'),
        trailing: IconButton(
          tooltip: '選擇紀錄日期',
          onPressed: _busy ? null : _pickHistoryDate,
          icon: const Icon(Icons.calendar_month),
        ),
      ),
      if (_history.isEmpty) _empty('這一天沒有服藥紀錄。'),
      ..._history.map(_doseCard),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final clinics =
        _plans
            .map((plan) => plan.clinic)
            .where((clinic) => clinic.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('吃藥小助手'),
        leading: IconButton(
          tooltip: '回到上一頁',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '重新整理與排程',
            onPressed: _busy ? null : () => _reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '今日服藥'),
            Tab(text: '用藥計畫'),
            Tab(text: '歷史紀錄'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy || _firstLoad) const LinearProgressIndicator(),
          if (!_firstLoad)
            Container(
              width: double.infinity,
              color: _reminders.enabled
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_reminders.message),
                  if (_notifications.supported && _plans.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _configureNotifications(),
                          child: const Text('啟用通知'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _reload(),
                          child: const Text('重新排程'),
                        ),
                        if (defaultTargetPlatform == TargetPlatform.android)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _configureNotifications(exact: true),
                            child: const Text('精準時間權限'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          if (clinics.isNotEmpty && _tabs.index != 2)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  for (final clinic in ['', ...clinics])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(clinic.isEmpty ? '全部診所' : clinic),
                        selected: _clinic == clinic,
                        onSelected: (_) => setState(() => _clinic = clinic),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loadError != null
                ? _empty(_loadError!)
                : _firstLoad
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [_todayTab(), _plansTab(), _historyTab()],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _loadError != null || _firstLoad ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('新增用藥'),
      ),
    );
  }
}

/// 輸入藥單代碼的對話框；controller 由對話框自己管理，
/// 關閉動畫期間仍可安全重建，不會使用已釋放的 controller。
class _PrescriptionCodeDialog extends StatefulWidget {
  const _PrescriptionCodeDialog();

  @override
  State<_PrescriptionCodeDialog> createState() =>
      _PrescriptionCodeDialogState();
}

class _PrescriptionCodeDialogState extends State<_PrescriptionCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('輸入藥單代碼'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: 2,
      maxLines: 6,
      decoration: const InputDecoration(
        hintText: '$medicinePrescriptionPrefix…',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('建立提醒'),
      ),
    ],
  );
}
