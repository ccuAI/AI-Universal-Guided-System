import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 傳入背景 isolate 的資料只包含位元組與數字，不持有 Widget 或原生圖片物件。
class MedicineImageData {
  const MedicineImageData(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// 使用 0～1 的圖片座標，讓螢幕縮放不影響實際裁切位置。
class MedicineCorner {
  const MedicineCorner(this.x, this.y);
  final double x;
  final double y;
}

class MedicineCropRequest {
  const MedicineCropRequest(this.image, this.corners);
  final MedicineImageData image;

  /// 順序固定為左上、右上、右下、左下。
  final List<MedicineCorner> corners;
}

img.Image _decode(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('無法讀取圖片，請改選 JPG 或 PNG。');
  return img.bakeOrientation(decoded);
}

MedicineImageData _encode(img.Image image) => MedicineImageData(
  Uint8List.fromList(img.encodeJpg(image, quality: 95)),
  image.width,
  image.height,
);

/// 先套用相機 EXIF 方向，再產生與畫面座標一致的工作影像。
/// 原始照片由呼叫端另外保存；此處限制工作圖尺寸以免手機記憶體暴增。
MedicineImageData normalizeMedicineImage(Uint8List bytes) {
  var image = _decode(bytes);
  if (math.max(image.width, image.height) > 2400) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2400 : null,
      height: image.height > image.width ? 2400 : null,
      interpolation: img.Interpolation.linear,
    );
  }
  return _encode(image);
}

MedicineImageData rotateMedicineImage(MedicineImageData input) =>
    _encode(img.copyRotate(_decode(input.bytes), angle: 90));

/// 要求凸四邊形與最小面積，拒絕交叉、反向、重疊的選框。
/// 這只驗證幾何形狀，不能保證所選區域包含足夠的處方資訊。
bool validMedicineCorners(List<MedicineCorner> corners) {
  if (corners.length != 4 ||
      corners.any(
        (p) =>
            !p.x.isFinite ||
            !p.y.isFinite ||
            p.x < 0 ||
            p.x > 1 ||
            p.y < 0 ||
            p.y > 1,
      )) {
    return false;
  }
  var area = 0.0;
  for (var index = 0; index < 4; index++) {
    final a = corners[index];
    final b = corners[(index + 1) % 4];
    final c = corners[(index + 2) % 4];
    if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 0.0001) {
      return false;
    }
    area += a.x * b.y - b.x * a.y;
  }
  return area / 2 > 0.01;
}

/// 將使用者指定的四邊形以投影轉換映射到長方形，兼具裁切與透視校正。
/// 不修補文字、不移除醫師筆跡，也不使用生成式影像「補字」。
/// 長寬由兩組對邊平均長度估計；曲面皺摺及已遮住的字仍需原圖核對。
MedicineImageData rectifyMedicineImage(MedicineCropRequest request) {
  if (!validMedicineCorners(request.corners)) throw ArgumentError('四角選框無效');
  final source = _decode(request.image.bytes);
  final points = request.corners
      .map(
        (p) =>
            MedicineCorner(p.x * (source.width - 1), p.y * (source.height - 1)),
      )
      .toList();
  final p0 = points[0], p1 = points[1], p2 = points[2], p3 = points[3];
  double distance(MedicineCorner a, MedicineCorner b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  final width = ((distance(p0, p1) + distance(p3, p2)) / 2).round();
  final height = ((distance(p0, p3) + distance(p1, p2)) / 2).round();
  if (width < 48 || height < 48) throw ArgumentError('選取區域太小，請保留完整文字');

  // 從單位正方形至來源四邊形的 3×3 homography。
  // 輸出逐像素反查來源，避免正向投影留下空洞；雙線性取樣減少斜線鋸齒。
  final dx1 = p1.x - p2.x, dx2 = p3.x - p2.x;
  final dy1 = p1.y - p2.y, dy2 = p3.y - p2.y;
  final dx3 = p0.x - p1.x + p2.x - p3.x;
  final dy3 = p0.y - p1.y + p2.y - p3.y;
  final determinant = dx1 * dy2 - dx2 * dy1;
  if (determinant.abs() < 0.000001) throw ArgumentError('選框無法校正，請重設四角');
  final g = (dx3 * dy2 - dx2 * dy3) / determinant;
  final h = (dx1 * dy3 - dx3 * dy1) / determinant;
  final a = p1.x - p0.x + g * p1.x;
  final b = p3.x - p0.x + h * p3.x;
  final d = p1.y - p0.y + g * p1.y;
  final e = p3.y - p0.y + h * p3.y;
  final output = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    final v = y / (height - 1);
    for (var x = 0; x < width; x++) {
      final u = x / (width - 1);
      final denominator = g * u + h * v + 1;
      if (denominator.abs() < 0.000001) throw ArgumentError('選框投影無效');
      final sx = ((a * u + b * v + p0.x) / denominator).clamp(
        0.0,
        source.width - 1.0,
      );
      final sy = ((d * u + e * v + p0.y) / denominator).clamp(
        0.0,
        source.height - 1.0,
      );
      output.setPixel(
        x,
        y,
        source.getPixelInterpolate(
          sx,
          sy,
          interpolation: img.Interpolation.linear,
        ),
      );
    }
  }
  return _encode(output);
}
