import 'dart:io';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

class ShareService extends GetxService {
  Future<void> shareFile(
    String filePath, {
    String? text,
    String? subject,
  }) async {
    final file = File(filePath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(filePath)], text: text, subject: subject),
      );
    }
  }

  Future<void> shareMultipleFiles(
    List<String> filePaths, {
    String? text,
  }) async {
    final xFiles = filePaths.map((p) => XFile(p)).toList();
    await SharePlus.instance.share(ShareParams(files: xFiles, text: text));
  }

  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}
