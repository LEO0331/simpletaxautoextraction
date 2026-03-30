import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveTextFile(String fileName, String content) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
  );
  if (path == null || path.isEmpty) {
    return false;
  }
  final file = File(path);
  await file.writeAsString(content);
  return true;
}

Future<bool> saveBinaryFile(String fileName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
  );
  if (path == null || path.isEmpty) {
    return false;
  }
  final file = File(path);
  await file.writeAsBytes(bytes);
  return true;
}
