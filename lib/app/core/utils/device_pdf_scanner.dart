import 'dart:io';

class DevicePdfScanner {
  DevicePdfScanner._();

  static Future<List<File>> getSavedPdfs(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final list = await dir.list().toList();
    return list
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList();
  }
}
