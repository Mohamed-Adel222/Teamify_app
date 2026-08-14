import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class CapturedChatFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const CapturedChatFile({
    required this.name,
    required this.bytes,
    this.mimeType = 'application/octet-stream',
  });
}

/// Opens the device camera on mobile browsers via `<input capture>`.
Future<CapturedChatFile?> captureCameraImage() async {
  final completer = Completer<CapturedChatFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  input.setAttribute('capture', 'environment');
  input.style.display = 'none';
  web.document.body?.append(input);

  void finish(CapturedChatFile? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
    input.remove();
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }
      final file = files.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      file.arrayBuffer().toDart.then((JSArrayBuffer buffer) {
        finish(CapturedChatFile(
          name: file.name.isNotEmpty ? file.name : 'camera_photo.jpg',
          bytes: buffer.toDart.asUint8List(),
          mimeType: file.type.isNotEmpty ? file.type : 'image/jpeg',
        ));
      }).catchError((Object _) {
        finish(null);
        return null;
      });
    }.toJS,
  );

  input.addEventListener(
    'cancel',
    (web.Event _) {
      finish(null);
    }.toJS,
  );

  input.click();
  return completer.future;
}
