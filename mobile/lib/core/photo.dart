import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Take or pick a photo, stamp "08 Oct, 14:05  ·  RS" along the bottom (as
/// the website does), and shrink it to fit the server's 1 MB photo limit.
class PhotoTool {
  static final _picker = ImagePicker();
  static const maxBytes = 1000 * 1000;

  static Future<Uint8List?> capture({required String stamp, bool camera = true}) async {
    final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (x == null) return null;
    final raw = await x.readAsBytes();
    return compute(_process, (raw, stamp));
  }
}

Uint8List _process((Uint8List, String) a) {
  final (raw, stamp) = a;
  var im = img.decodeImage(raw);
  if (im == null) return raw;
  im = img.bakeOrientation(im);
  if (im.width > 1280 || im.height > 1280) {
    im = im.width >= im.height ? img.copyResize(im, width: 1280) : img.copyResize(im, height: 1280);
  }
  final bar = (im.height * 0.035).round().clamp(22, 80);
  img.fillRect(im,
      x1: 0, y1: im.height - bar, x2: im.width, y2: im.height, color: img.ColorRgba8(0, 0, 0, 153));
  final font = bar >= 40 ? img.arial48 : (bar >= 26 ? img.arial24 : img.arial14);
  final fh = bar >= 40 ? 48 : (bar >= 26 ? 24 : 14);
  img.drawString(im, stamp,
      font: font, x: (bar * 0.35).round(), y: im.height - bar + ((bar - fh) / 2).round(), color: img.ColorRgb8(255, 255, 255));

  for (final (scale, q) in [(1.0, 85), (0.75, 85), (0.6, 80), (0.45, 75), (0.3, 70)]) {
    final s = scale == 1.0 ? im : img.copyResize(im, width: (im.width * scale).round());
    final out = img.encodeJpg(s, quality: q);
    if (out.length <= PhotoTool.maxBytes) return out;
  }
  return img.encodeJpg(img.copyResize(im, width: 480), quality: 60);
}
