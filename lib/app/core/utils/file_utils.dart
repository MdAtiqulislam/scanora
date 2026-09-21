import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  FileUtils._();

  static int _uniqueCounter = 0;
  static String? overrideAppDocumentsDirectoryPath;

  static Future<String> getAppDocumentsDirectoryPath() async {
    if (overrideAppDocumentsDirectoryPath != null) {
      return overrideAppDocumentsDirectoryPath!;
    }
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<String> createTimestampedFilePath({
    String prefix = 'scan',
    String extension = 'jpg',
  }) async {
    final dirPath = await getAppDocumentsDirectoryPath();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    _uniqueCounter = (_uniqueCounter + 1) % 1000000;
    return '$dirPath/${prefix}_${timestamp}_$_uniqueCounter.$extension';
  }

  static Future<void> deleteFileIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final size = bytes / pow(1024, i);
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
