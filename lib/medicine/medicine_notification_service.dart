import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'medicine_models.dart';
import 'medicine_repository.dart';

/// Android 模擬器可能回傳 GMT；它是明確的零時差別名，不是未知時區。
/// timezone 精簡資料未必保留此別名，因此直接使用套件的 UTC 常數。
/// 其他查不到的識別碼仍報錯，不猜測使用者所在國家或時區。
tz.Location resolveMedicineTimezone(String identifier) =>
    identifier == 'GMT' ||
        identifier == 'UTC' ||
        identifier == 'Etc/UTC' ||
        identifier == 'Etc/GMT'
    ? tz.UTC
    : tz.getLocation(identifier);

/// 把通知排程狀態交回畫面，避免資料已保存卻讓使用者誤以為提醒一定開啟。
class MedicineReminderStatus {
  const MedicineReminderStatus(
    this.message, {
    this.enabled = false,
    this.scheduledCount = 0,
    this.scheduledThrough,
  });
  final String message;
  final bool enabled;
  final int scheduledCount;
  final DateTime? scheduledThrough;
}

/// 只管理服藥模組的本機通知，不使用雲端推播，也不取消其他模組的通知。
///
/// 使用每次服藥事件的固定 id 配對通知；已服用、跳過、修改、停用或刪除後，
/// 重新讀取資料庫並建立排程。所有同步工作序列執行，避免連續點擊造成交錯。
class MedicineNotificationService {
  MedicineNotificationService._();
  static final instance = MedicineNotificationService._();
  static const _prefix = 'medicine-dose:';
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializing;
  String _zoneIdentifier = '';
  Future<void> _queue = Future.value();

  void Function(int doseId)? onOpenDose;
  int? initialDoseId;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() {
    if (!supported || _initialized) return Future.value();
    // 首頁初始化與服藥頁刷新可能同時進來，共用同一個原生初始化工作。
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    if (!supported || _initialized) return;
    tz_data.initializeTimeZones();
    await _setDeviceTimezone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_medicine_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = _doseId(response.payload);
        if (id != null) onOpenDose?.call(id);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      initialDoseId = _doseId(launch?.notificationResponse?.payload);
    }
    _initialized = true;
  }

  int? _doseId(String? payload) =>
      payload != null && payload.startsWith(_prefix)
      ? int.tryParse(payload.substring(_prefix.length).split('|').first)
      : null;

  Future<void> _setDeviceTimezone() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    // 無法取得時區時回報失敗，不默默改用 UTC 或猜測台灣時間。
    tz.setLocalLocation(resolveMedicineTimezone(zone.identifier));
    _zoneIdentifier = zone.identifier;
  }

  Future<MedicineReminderStatus> synchronize({
    bool requestPermission = false,
    bool requestExactAlarm = false,
  }) {
    final task = _queue.then(
      (_) => _synchronize(
        requestPermission: requestPermission,
        requestExactAlarm: requestExactAlarm,
      ),
    );
    _queue = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<void> _cancelOwnedNotifications() async {
    for (final request in await _plugin.pendingNotificationRequests()) {
      if (request.payload?.startsWith(_prefix) ?? false) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  /// 記錄已服用或跳過時，同時移除通知列上可能已顯示的那一則提醒。
  Future<void> cancelDose(int doseId) async {
    if (!supported) return;
    try {
      await initialize();
      await _plugin.cancel(id: 1000000000 + doseId);
    } catch (error) {
      debugPrint('移除單次服藥通知失敗：$error');
    }
  }

  String _payload(MedicineDose dose, bool exact) =>
      '$_prefix${dose.id}|$_zoneIdentifier|${dose.scheduledAt.toIso8601String()}|$exact';

  Future<MedicineReminderStatus> _synchronize({
    required bool requestPermission,
    required bool requestExactAlarm,
  }) async {
    if (!supported) {
      return const MedicineReminderStatus('可手動管理用藥；手機 App 才會發送提醒。');
    }
    try {
      await initialize();
      // 回到 App 時重新取得時區，使用者旅行或更改時區後會重建當地時間排程。
      await _setDeviceTimezone();
      final limit = defaultTargetPlatform == TargetPlatform.iOS ? 60 : 400;
      final upcoming = await MedicineRepository.instance.upcoming(
        limit: limit + 1,
      );
      if (upcoming.isEmpty) {
        await _cancelOwnedNotifications();
        return const MedicineReminderStatus('目前沒有待排程的用藥提醒。');
      }

      var allowed = false;
      var exact = true;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!;
        if (requestPermission) await android.requestNotificationsPermission();
        if (requestExactAlarm) await android.requestExactAlarmsPermission();
        allowed = await android.areNotificationsEnabled() ?? false;
        exact = await android.canScheduleExactNotifications() ?? false;
      } else {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()!;
        if (requestPermission) {
          await ios.requestPermissions(alert: true, badge: false, sound: true);
        }
        final permission = await ios.checkPermissions();
        allowed =
            (permission?.isEnabled ?? false) &&
            (permission?.isAlertEnabled ?? false);
      }

      // 停用或刪除的計畫不應殘留通知；沒有權限時也清除本模組舊排程。
      if (!allowed) {
        await _cancelOwnedNotifications();
        return const MedicineReminderStatus('通知尚未開啟。資料已保存，請按「啟用通知」並允許通知權限。');
      }

      // 比對排程指紋，只改動新增、刪除、時區或精準權限改變的通知。
      // 勾選一次已服用時不必取消並重建另外數百則相同提醒。
      final existing = {
        for (final request in await _plugin.pendingNotificationRequests())
          if (request.payload?.startsWith(_prefix) ?? false)
            request.id: request.payload,
      };
      final wanted = {
        for (final dose in upcoming.take(limit))
          1000000000 + dose.id: _payload(dose, exact),
      };
      for (final entry in existing.entries) {
        if (wanted[entry.key] != entry.value) {
          await _plugin.cancel(id: entry.key);
        }
      }
      var count = 0;
      DateTime? through;
      for (final dose in upcoming.take(limit)) {
        final at = dose.scheduledAt;
        final scheduled = tz.TZDateTime(
          tz.local,
          at.year,
          at.month,
          at.day,
          at.hour,
          at.minute,
        );
        if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) continue;
        final payload = _payload(dose, exact);
        if (existing[1000000000 + dose.id] == payload) {
          count++;
          through = at;
          continue;
        }
        await _plugin.zonedSchedule(
          // 為服藥模組保留十億起算的通知 id 區間。
          id: 1000000000 + dose.id,
          title: '用藥提醒：${dose.name}',
          body: '${dose.doseLabel}・${dose.meal}。服用後請到 App 記錄。',
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'medicine_reminders',
              '服藥提醒',
              channelDescription: '依已確認用藥計畫發送的本機提醒',
              importance: Importance.high,
              priority: Priority.high,
              icon: 'ic_medicine_notification',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBadge: false,
            ),
          ),
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        count++;
        through = at;
      }
      final limited = upcoming.length > limit;
      final needsExtension =
          through != null &&
          (await MedicineRepository.instance.plans()).any(
            (plan) =>
                plan.enabled &&
                !plan.asNeeded &&
                (plan.endDate == null ||
                    calendarDay(plan.endDate!).isAfter(calendarDay(through!))),
          );
      var message = '已排程 $count 次提醒。';
      if (!exact) message += '尚未允許精準鬧鐘，提醒可能延遲；可按「精準時間權限」設定。';
      if (through != null) {
        message +=
            '已排至 ${dateLabel(through)} '
            '${timeLabel(through.hour * 60 + through.minute)}。';
        // 長期用藥即使未達系統數量上限，也只建立了一年內的事件。
        if (limited || needsExtension) {
          message += '請在此前重新開啟 App 延伸後續提醒。';
        }
      }
      return MedicineReminderStatus(
        message,
        enabled: true,
        scheduledCount: count,
        scheduledThrough: through,
      );
    } catch (error) {
      debugPrint('同步服藥通知失敗：$error');
      // 不回滾已保存用藥資料；畫面必須明確顯示本次排程未完成。
      return const MedicineReminderStatus('提醒排程未完成，資料仍已保存。請確認手機通知設定後按「重新排程」。');
    }
  }
}
