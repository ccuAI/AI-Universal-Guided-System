import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:projectfront/medicine/medicine_notification_service.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);
  test('模擬器 GMT 別名不會阻止建立提醒', () {
    expect(resolveMedicineTimezone('GMT'), same(tz.UTC));
    expect(resolveMedicineTimezone('Etc/UTC'), same(tz.UTC));
    expect(resolveMedicineTimezone('Asia/Taipei').name, 'Asia/Taipei');
  });
  test('未知時區仍報錯，不默默轉成 UTC', () {
    expect(
      () => resolveMedicineTimezone('unknown/test-zone'),
      throwsA(isA<Exception>()),
    );
  });
}
