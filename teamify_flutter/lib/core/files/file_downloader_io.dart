import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveDownloadedBytes({
  required String filename,
  required Uint8List bytes,
  String? mimeType,
}) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
}

Future<bool> shareDownloadedBytes({
  required String filename,
  required Uint8List bytes,
  String? mimeType,
}) async {
  await saveDownloadedBytes(
    filename: filename,
    bytes: bytes,
    mimeType: mimeType,
  );
  return true;
}
