import 'dart:typed_data';

import 'file_exporter_stub.dart'
    if (dart.library.io) 'file_exporter_io.dart'
    if (dart.library.html) 'file_exporter_web.dart'
    as impl;

Future<bool> saveTextFile(String fileName, String content) {
  return impl.saveTextFile(fileName, content);
}

Future<bool> saveBinaryFile(String fileName, Uint8List bytes) {
  return impl.saveBinaryFile(fileName, bytes);
}
