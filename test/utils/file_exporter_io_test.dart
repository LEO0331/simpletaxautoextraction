import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/utils/file_exporter.dart';
import 'package:simpletaxautoextraction/utils/file_exporter_io.dart' as io_impl;

class FakeFilePicker extends FilePicker {
  FakeFilePicker({required this.path});

  final String? path;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    return path;
  }
}

void main() {
  group('file exporter io', () {
    setUp(() {
      FilePicker.platform = FakeFilePicker(path: null);
    });

    tearDown(() {
      FilePicker.platform = FakeFilePicker(path: null);
    });

    test('saveTextFile writes file content when path is provided', () async {
      final tempDir = await Directory.systemTemp.createTemp('export_test_');
      final filePath = '${tempDir.path}/sample.csv';
      FilePicker.platform = FakeFilePicker(path: filePath);

      final ok = await saveTextFile('sample.csv', 'a,b\n1,2');

      expect(ok, isTrue);
      expect(await File(filePath).readAsString(), 'a,b\n1,2');
    });

    test('saveBinaryFile returns false when canceled', () async {
      FilePicker.platform = FakeFilePicker(path: null);

      final ok = await saveBinaryFile(
        'sample.pdf',
        Uint8List.fromList([1, 2, 3]),
      );

      expect(ok, isFalse);
    });

    test('saveBinaryFile writes bytes when path is provided', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'export_binary_test_',
      );
      final filePath = '${tempDir.path}/sample.pdf';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      FilePicker.platform = FakeFilePicker(path: filePath);

      final ok = await io_impl.saveBinaryFile('sample.pdf', bytes);

      expect(ok, isTrue);
      expect(await File(filePath).readAsBytes(), bytes);
    });

    test(
      'saveBinaryFile returns false when picker returns empty path',
      () async {
        FilePicker.platform = FakeFilePicker(path: '');

        final ok = await io_impl.saveBinaryFile(
          'sample.pdf',
          Uint8List.fromList([1, 2, 3]),
        );

        expect(ok, isFalse);
      },
    );
  });
}
