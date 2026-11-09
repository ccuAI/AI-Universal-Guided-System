import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'medicine_models.dart';

/// 服藥資料的唯一讀寫入口。
///
/// Android／iOS 使用 SQLite 交易保存計畫與每次事件；照片另存 App 私有目錄。
/// Chrome／Windows 的手動預覽使用單一 JSON 快照，不會呼叫手機原生資料庫。
/// 桌面／瀏覽器預覽資料不會自動同步到手機，也不會上傳到後端。
class MedicineRepository {
  MedicineRepository._();
  static final instance = MedicineRepository._();

  bool get usesMobileDatabase =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Database? _database;
  Future<void>? _opening;
  final _preferences = SharedPreferencesAsync();
  static const _previewKey = 'medicine_preview_v1';
  List<MedicinePlan> _previewPlans = [];
  List<Map<String, dynamic>> _previewDoses = [];
  int _nextPlan = 1;
  int _nextDose = 1;
  Future<void> _previewQueue = Future.value();

  Future<void> initialize() =>
      _opening ??= _open().catchError((Object error, StackTrace stack) {
        // 首次開啟失敗後允許使用者重試，但不清除任何原始資料。
        _opening = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _open() async {
    if (!usesMobileDatabase) {
      await _loadPreview();
      return;
    }
    _database = await openDatabase(
      path.join(await getDatabasesPath(), 'medicine_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE plans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payload TEXT NOT NULL
          )
        ''');
        // 事件保存用藥快照，不以刪除計畫連帶刪除服藥歷史。
        await db.execute('''
          CREATE TABLE doses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plan_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            dose_label TEXT NOT NULL,
            meal TEXT NOT NULL,
            scheduled_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            recorded_at TEXT,
            as_needed INTEGER NOT NULL DEFAULT 0,
            UNIQUE(plan_id, scheduled_at)
          )
        ''');
        await db.execute(
          'CREATE INDEX dose_schedule ON doses(status, scheduled_at)',
        );
      },
    );
  }

  Future<void> _loadPreview() async {
    final saved = await _preferences.getString(_previewKey);
    if (saved == null) return;
    // 損壞的資料不能默默清空；讓畫面顯示讀取失敗，避免覆蓋原始內容。
    final snapshot = jsonDecode(saved) as Map<String, dynamic>;
    _previewPlans = (snapshot['plans'] as List)
        .map((item) => MedicinePlan.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    _previewDoses = (snapshot['doses'] as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    _nextPlan = (snapshot['nextPlan'] as num).toInt();
    _nextDose = (snapshot['nextDose'] as num).toInt();
  }

  Future<void> _savePreview() async {
    await _preferences.setString(
      _previewKey,
      jsonEncode({
        'plans': _previewPlans.map((plan) => plan.toJson()).toList(),
        'doses': _previewDoses,
        'nextPlan': _nextPlan,
        'nextDose': _nextDose,
      }),
    );
  }

  /// 預覽資料也逐次保存：寫入失敗時恢復記憶體快照，不顯示未成功保存的內容。
  /// 手機的同等工作由 SQLite transaction 處理；這裡只用於手動預覽平台。
  Future<void> _mutatePreview(void Function() change) {
    final task = _previewQueue.then((_) async {
      final oldPlans = List<MedicinePlan>.of(_previewPlans);
      final oldDoses = _previewDoses
          .map((row) => Map<String, dynamic>.of(row))
          .toList();
      final oldNextPlan = _nextPlan;
      final oldNextDose = _nextDose;
      try {
        change();
        await _savePreview();
      } catch (_) {
        _previewPlans = oldPlans;
        _previewDoses = oldDoses;
        _nextPlan = oldNextPlan;
        _nextDose = oldNextDose;
        rethrow;
      }
    });
    // 一次失敗不阻止下一次重試；失敗仍會傳回給原本的呼叫者。
    _previewQueue = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<List<MedicinePlan>> plans() async {
    await initialize();
    if (!usesMobileDatabase) {
      await _previewQueue;
      return List.of(_previewPlans.reversed);
    }
    final rows = await _database!.query('plans', orderBy: 'id DESC');
    return rows
        .map(
          (row) => MedicinePlan.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// 照片不留在 image_picker 的暫存目錄，避免系統清理後失去原藥袋。
  Future<MedicinePlan> savePlan(
    MedicinePlan plan, {
    Uint8List? photoBytes,
    Uint8List? correctedPhotoBytes,
  }) async {
    await initialize();
    _validate(plan);
    var photoPath = plan.photoPath;
    var correctedPath = plan.correctedPhotoPath;
    // 同一次保存的兩份照片一起清理；第二份寫入失敗也不留下第一份孤兒檔。
    final createdPaths = <String>[];
    Future<String> writePhoto(Uint8List bytes, String kind) async {
      final folder = Directory(
        path.join(
          (await getApplicationDocumentsDirectory()).path,
          'medicine_photos',
        ),
      );
      await folder.create(recursive: true);
      final filename = path.join(
        folder.path,
        'bag_${DateTime.now().microsecondsSinceEpoch}_$kind.image',
      );
      createdPaths.add(filename);
      await File(filename).writeAsBytes(bytes, flush: true);
      return filename;
    }

    late MedicinePlan saved;
    try {
      if (usesMobileDatabase) {
        if (photoBytes != null) {
          photoPath = await writePhoto(photoBytes, 'original');
        }
        if (correctedPhotoBytes != null) {
          correctedPath = await writePhoto(correctedPhotoBytes, 'corrected');
        }
      }
      if (!usesMobileDatabase) {
        await _mutatePreview(() {
          saved = plan.withIdentity(plan.id == 0 ? _nextPlan++ : plan.id, null);
          _previewPlans.removeWhere((item) => item.id == saved.id);
          _previewPlans.add(saved);
          _removePreviewPending(saved.id);
          _generatePreview(saved);
        });
      } else {
        await _database!.transaction((tx) async {
          var id = plan.id;
          if (id == 0) {
            id = await tx.insert('plans', {
              'payload': jsonEncode(plan.toJson()),
            });
          }
          saved = plan.withIdentity(id, photoPath, correctedPath);
          await tx.update(
            'plans',
            {'payload': jsonEncode(saved.toJson())},
            where: 'id = ?',
            whereArgs: [id],
          );
          await tx.delete(
            'doses',
            where: 'plan_id = ? AND status = ? AND scheduled_at >= ?',
            whereArgs: [
              id,
              'pending',
              calendarDay(DateTime.now()).toIso8601String(),
            ],
          );
          await _generateMobile(tx, saved);
        });
      }
    } catch (_) {
      // 資料庫交易失敗時，只清除本次尚未被計畫引用的新照片。
      for (final filename in createdPaths) {
        await _deletePhoto(filename);
      }
      rethrow;
    }
    if (plan.photoPath != null && plan.photoPath != saved.photoPath) {
      await _deletePhoto(plan.photoPath);
    }
    if (plan.correctedPhotoPath != null &&
        plan.correctedPhotoPath != saved.correctedPhotoPath) {
      await _deletePhoto(plan.correctedPhotoPath);
    }
    return saved;
  }

  static void _validate(MedicinePlan plan) {
    if (plan.name.trim().isEmpty ||
        !plan.amount.isFinite ||
        plan.amount <= 0 ||
        plan.unit.trim().isEmpty ||
        plan.meal.trim().isEmpty) {
      throw ArgumentError('請確認用藥資料、每次用量、單位與用法');
    }
    if (plan.endDate != null &&
        calendarDay(plan.endDate!).isBefore(calendarDay(plan.startDate))) {
      throw ArgumentError('結束日期不能早於開始日期');
    }
    if (!plan.asNeeded &&
        (plan.times.isEmpty ||
            plan.times.toSet().length != plan.times.length ||
            plan.times.any((value) => value < 0 || value >= 1440))) {
      throw ArgumentError('請設定不重複的每日提醒時間');
    }
    if (plan.asNeeded && plan.times.isNotEmpty) {
      throw ArgumentError('需要時服用不建立固定時間通知');
    }
  }

  /// 以日曆加一天，避免夏令時間時使用 24 小時造成日期或時間偏移。
  Iterable<Map<String, dynamic>> _rowsForPlan(MedicinePlan plan) sync* {
    if (!plan.enabled || plan.asNeeded) return;
    final today = calendarDay(DateTime.now());
    var day = calendarDay(plan.startDate);
    if (day.isBefore(today)) day = today;
    final horizon = DateTime(today.year, today.month, today.day + 365);
    final end = plan.endDate != null && plan.endDate!.isBefore(horizon)
        ? calendarDay(plan.endDate!)
        : horizon;
    for (
      ;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      for (final minutes in plan.times) {
        yield {
          'plan_id': plan.id,
          'name': plan.name,
          'dose_label': plan.doseLabel,
          'meal': plan.meal,
          'scheduled_at': DateTime(
            day.year,
            day.month,
            day.day,
            minutes ~/ 60,
            minutes % 60,
          ).toIso8601String(),
          'status': 'pending',
          'recorded_at': null,
          'as_needed': 0,
        };
      }
    }
  }

  Future<void> _generateMobile(DatabaseExecutor db, MedicinePlan plan) async {
    if (!plan.enabled || plan.asNeeded) return;
    // 先查已有事件，避免每次回到 App 都向 SQLite 重複插入一整年的資料，
    // 也避免 INSERT OR IGNORE 的衝突耗盡 AUTOINCREMENT 的事件編號。
    final existing = (await db.query(
      'doses',
      columns: ['scheduled_at'],
      where: 'plan_id = ? AND scheduled_at >= ?',
      whereArgs: [plan.id, calendarDay(DateTime.now()).toIso8601String()],
    )).map((row) => row['scheduled_at']).toSet();
    final batch = db.batch();
    for (final row in _rowsForPlan(plan)) {
      if (!existing.add(row['scheduled_at'])) continue;
      // 已服用／跳過的事件不會被重新生成或覆蓋。
      batch.insert('doses', row, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  void _generatePreview(MedicinePlan plan) {
    final existing = _previewDoses
        .where((row) => row['plan_id'] == plan.id)
        .map((row) => row['scheduled_at'])
        .toSet();
    for (final row in _rowsForPlan(plan)) {
      if (existing.add(row['scheduled_at'])) {
        _previewDoses.add({...row, 'id': _nextDose++});
      }
    }
  }

  void _removePreviewPending(int planId) {
    final today = calendarDay(DateTime.now()).toIso8601String();
    _previewDoses.removeWhere(
      (row) =>
          row['plan_id'] == planId &&
          row['status'] == 'pending' &&
          (row['scheduled_at'] as String).compareTo(today) >= 0,
    );
  }

  /// 每次開啟或回到 App 都延伸長期用藥的事件範圍，不需雲端定時工作。
  Future<void> ensureUpcomingDoses() async {
    await initialize();
    if (!usesMobileDatabase) {
      await _mutatePreview(() {
        for (final plan in _previewPlans) {
          _generatePreview(plan);
        }
      });
      return;
    }
    await _database!.transaction((tx) async {
      // 在同一交易中讀取計畫，避免同時編輯時用到舊計畫並生成舊排程。
      final rows = await tx.query('plans');
      final currentPlans = rows.map(
        (row) => MedicinePlan.fromJson(
          jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        ),
      );
      for (final plan in currentPlans) {
        await _generateMobile(tx, plan);
      }
    });
  }

  Future<List<MedicineDose>> dosesOn(DateTime date) async {
    await initialize();
    if (!usesMobileDatabase) await _previewQueue;
    final start = calendarDay(date).toIso8601String();
    final end = DateTime(date.year, date.month, date.day + 1).toIso8601String();
    final rows = usesMobileDatabase
        ? await _database!.query(
            'doses',
            where: 'scheduled_at >= ? AND scheduled_at < ?',
            whereArgs: [start, end],
            orderBy: 'scheduled_at ASC',
          )
        : _previewDoses.where((row) {
            final stamp = row['scheduled_at'] as String;
            return stamp.compareTo(start) >= 0 && stamp.compareTo(end) < 0;
          }).toList();
    return rows.map(MedicineDose.fromRow).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Future<List<MedicineDose>> upcoming({int limit = 401}) async {
    await initialize();
    final activePlans = {
      for (final plan in await plans())
        if (plan.enabled && !plan.asNeeded) plan.id: plan,
    };
    if (activePlans.isEmpty) return [];
    final now = DateTime.now().toIso8601String();
    final rows = usesMobileDatabase
        ? await _database!.query(
            'doses',
            where:
                'status = ? AND scheduled_at > ? AND as_needed = 0 '
                'AND plan_id IN (${activePlans.keys.map((_) => '?').join(',')})',
            whereArgs: ['pending', now, ...activePlans.keys],
            orderBy: 'scheduled_at ASC',
            limit: limit,
          )
        : (_previewDoses
                  .where(
                    (row) =>
                        row['status'] == 'pending' &&
                        activePlans.containsKey(row['plan_id']) &&
                        (row['scheduled_at'] as String).compareTo(now) > 0,
                  )
                  .toList()
                ..sort(
                  (a, b) => (a['scheduled_at'] as String).compareTo(
                    b['scheduled_at'] as String,
                  ),
                ))
              .take(limit)
              .toList();
    return rows
        .map(MedicineDose.fromRow)
        .where(
          (dose) =>
              activePlans[dose.planId]?.appliesOn(dose.scheduledAt) ?? false,
        )
        .toList();
  }

  /// 通知帶回事件 id 時，用它找到日期，不依賴計畫是否仍存在。
  Future<MedicineDose?> doseById(int id) async {
    await initialize();
    if (!usesMobileDatabase) await _previewQueue;
    final rows = usesMobileDatabase
        ? await _database!.query(
            'doses',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          )
        : _previewDoses.where((row) => row['id'] == id).toList();
    return rows.isEmpty ? null : MedicineDose.fromRow(rows.first);
  }

  /// 修改單次事件狀態；恢復「未紀錄」時清除實際紀錄時間。
  Future<void> setStatus(MedicineDose dose, String status) async {
    await initialize();
    if (!['pending', 'taken', 'skipped'].contains(status)) {
      throw ArgumentError('無效的服藥狀態');
    }
    if (dose.asNeeded && status == 'pending') {
      if (usesMobileDatabase) {
        await _database!.delete('doses', where: 'id = ?', whereArgs: [dose.id]);
      } else {
        await _mutatePreview(() {
          _previewDoses.removeWhere((row) => row['id'] == dose.id);
        });
      }
      return;
    }
    final values = {
      'status': status,
      'recorded_at': status == 'pending'
          ? null
          : DateTime.now().toIso8601String(),
    };
    if (usesMobileDatabase) {
      await _database!.update(
        'doses',
        values,
        where: 'id = ?',
        whereArgs: [dose.id],
      );
    } else {
      await _mutatePreview(() {
        final row = _previewDoses.firstWhere((row) => row['id'] == dose.id);
        row.addAll(values);
      });
    }
  }

  /// 需要時服用由使用者主動紀錄，沒有排定通知，也不推算下一次劑量。
  Future<void> recordAsNeeded(MedicinePlan plan) async {
    await initialize();
    if (!plan.asNeeded || !plan.appliesOn(DateTime.now())) {
      throw StateError('這項需要時用藥目前未啟用或已超出療程');
    }
    final now = DateTime.now().toIso8601String();
    final row = {
      'plan_id': plan.id,
      'name': plan.name,
      'dose_label': plan.doseLabel,
      'meal': plan.meal,
      'scheduled_at': now,
      'status': 'taken',
      'recorded_at': now,
      'as_needed': 1,
    };
    if (usesMobileDatabase) {
      await _database!.insert('doses', row);
    } else {
      await _mutatePreview(() {
        _previewDoses.add({...row, 'id': _nextDose++});
      });
    }
  }

  Future<void> deletePlan(MedicinePlan plan) async {
    await initialize();
    if (usesMobileDatabase) {
      await _database!.transaction((tx) async {
        await tx.delete('plans', where: 'id = ?', whereArgs: [plan.id]);
        await tx.delete(
          'doses',
          where: 'plan_id = ? AND status = ? AND scheduled_at >= ?',
          whereArgs: [
            plan.id,
            'pending',
            calendarDay(DateTime.now()).toIso8601String(),
          ],
        );
      });
    } else {
      await _mutatePreview(() {
        _previewPlans.removeWhere((item) => item.id == plan.id);
        _removePreviewPending(plan.id);
      });
    }
    await _deletePhoto(plan.photoPath);
    await _deletePhoto(plan.correctedPhotoPath);
  }

  Future<Uint8List?> readPhoto(String? filename) async {
    if (!usesMobileDatabase || filename == null) return null;
    final file = File(filename);
    return await file.exists() ? await file.readAsBytes() : null;
  }

  Future<void> _deletePhoto(String? filename) async {
    if (!usesMobileDatabase || filename == null) return;
    try {
      final file = File(filename);
      if (await file.exists()) await file.delete();
    } catch (error) {
      // 照片清理失敗不把已完成的資料庫交易誤報為保存失敗。
      debugPrint('清理藥袋照片失敗：$error');
    }
  }
}
