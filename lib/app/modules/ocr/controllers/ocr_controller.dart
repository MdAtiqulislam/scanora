import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../data/models/passport_data.dart';

class OcrController extends GetxController {
  final OcrService ocrService = Get.find<OcrService>();
  final ShareService shareService = Get.put(ShareService());

  late String imagePath;
  var isPassport = false.obs;
  var isLoading = true.obs;
  var extractedText = ''.obs;
  Rx<PassportData?> passportData = Rx<PassportData?>(null);

  final TextEditingController textEditingController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>?;
    if (args != null) {
      imagePath = args['imagePath'] ?? '';
      isPassport.value = args['isPassport'] ?? false;
      _processOcr();
    }
  }

  Future<void> _processOcr() async {
    isLoading.value = true;
    update();

    final file = File(imagePath);
    if (!file.existsSync()) {
      isLoading.value = false;
      update();
      return;
    }

    if (isPassport.value) {
      final data = await ocrService.parsePassportMrz(file);
      passportData.value = data;
    }

    final text = await ocrService.extractText(file);
    extractedText.value = text;
    textEditingController.text = text;

    isLoading.value = false;
    update();
  }

  void copyAllText() {
    Clipboard.setData(ClipboardData(text: textEditingController.text));
    SnackbarHelper.showSuccess('Text copied to clipboard!');
  }

  void shareExtractedText() {
    shareService.shareText(
      textEditingController.text,
      subject: 'Scanora Extracted OCR Text',
    );
  }

  @override
  void onClose() {
    textEditingController.dispose();
    super.onClose();
  }
}
