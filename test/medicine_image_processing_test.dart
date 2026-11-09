import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:projectfront/medicine/medicine_image_processing.dart';

void main() {
  test('四角裁切只保留指定區域，原始位元組不變', () {
    final source = img.Image(width: 200, height: 160, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      source,
      x1: 40,
      y1: 32,
      x2: 160,
      y2: 128,
      color: img.ColorRgb8(20, 80, 160),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));
    final before = List<int>.of(bytes);
    final result = rectifyMedicineImage(
      MedicineCropRequest(MedicineImageData(bytes, 200, 160), const [
        MedicineCorner(.25, .25),
        MedicineCorner(.75, .25),
        MedicineCorner(.75, .75),
        MedicineCorner(.25, .75),
      ]),
    );
    expect(result.width, closeTo(100, 1));
    expect(result.height, closeTo(80, 1));
    final pixel = img.decodeJpg(result.bytes)!.getPixel(30, 30);
    expect(pixel.r, closeTo(20, 5));
    expect(pixel.g, closeTo(80, 5));
    expect(pixel.b, closeTo(160, 5));
    expect(bytes, before);
  });

  test('梯形可校正且旋轉交換長寬', () {
    final source = img.Image(width: 240, height: 180, numChannels: 3);
    final image = normalizeMedicineImage(
      Uint8List.fromList(img.encodePng(source)),
    );
    final rotated = rotateMedicineImage(image);
    expect(rotated.width, 180);
    expect(rotated.height, 240);
    final result = rectifyMedicineImage(
      MedicineCropRequest(image, const [
        MedicineCorner(.2, .1),
        MedicineCorner(.8, .15),
        MedicineCorner(.95, .9),
        MedicineCorner(.05, .85),
      ]),
    );
    expect(result.width, greaterThan(100));
    expect(result.height, greaterThan(100));
    expect(img.decodeJpg(result.bytes), isNotNull);
  });

  test('交叉、越界、極小選框不能開始處理', () {
    expect(
      validMedicineCorners(const [
        MedicineCorner(0, 0),
        MedicineCorner(1, 1),
        MedicineCorner(1, 0),
        MedicineCorner(0, 1),
      ]),
      isFalse,
    );
    expect(
      validMedicineCorners(const [
        MedicineCorner(-.1, 0),
        MedicineCorner(1, 0),
        MedicineCorner(1, 1),
        MedicineCorner(0, 1),
      ]),
      isFalse,
    );
    expect(
      validMedicineCorners(const [
        MedicineCorner(0, 0),
        MedicineCorner(.01, 0),
        MedicineCorner(.01, .01),
        MedicineCorner(0, .01),
      ]),
      isFalse,
    );
  });
}
