import 'dart:typed_data';

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

/// Non-web fallback: the chat screen uses the image file picker instead.
Future<CapturedChatFile?> captureCameraImage() async => null;
