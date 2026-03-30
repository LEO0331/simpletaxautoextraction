// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

Future<bool> saveTextFile(String fileName, String content) async {
  final bytes = utf8.encode(content);
  return saveBinaryFile(fileName, Uint8List.fromList(bytes));
}

Future<bool> saveBinaryFile(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}
