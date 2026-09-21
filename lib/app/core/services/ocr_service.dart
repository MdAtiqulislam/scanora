import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../data/models/passport_data.dart';

class OcrService extends GetxService {
  late final TextRecognizer _textRecognizer;

  @override
  void onInit() {
    super.onInit();
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  void onClose() {
    _textRecognizer.close();
    super.onClose();
  }

  /// Performs fast on-device text recognition
  Future<String> extractText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      return recognizedText.text;
    } catch (e) {
      debugPrint('Error performing OCR: $e');
      return '';
    }
  }

  /// Parses MRZ (Machine Readable Zone) from Passport bottom region
  Future<PassportData?> parsePassportMrz(File imageFile) async {
    try {
      final text = await extractText(imageFile);
      final lines =
          text
              .split('\n')
              .map((l) => l.replaceAll(' ', '').toUpperCase())
              .toList();

      // Look for 2 lines with length ~44 chars (TD3 standard) or containing 'P<'
      String? line1;
      String? line2;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.startsWith('P<') ||
            (line.startsWith('P') && line.length >= 35)) {
          line1 = line;
          if (i + 1 < lines.length && lines[i + 1].length >= 35) {
            line2 = lines[i + 1];
          }
          break;
        }
      }

      if (line1 != null && line2 != null) {
        return _parseTd3Mrz(line1, line2);
      }

      // Fallback: general passport regex parser
      return _parseGeneralPassportText(text);
    } catch (e) {
      debugPrint('Error parsing MRZ: $e');
      return null;
    }
  }

  PassportData _parseTd3Mrz(String l1, String l2) {
    try {
      // Line 1: P<UTOERIKSSON<<SARAH<<<<<<<<<<<<<<<<<<<<<<<
      final country =
          l1.length >= 5 ? l1.substring(2, 5).replaceAll('<', '') : '';
      final namesPart = l1.length > 5 ? l1.substring(5) : '';
      final nameSplit = namesPart.split('<<');
      final surname =
          nameSplit.isNotEmpty ? nameSplit[0].replaceAll('<', ' ').trim() : '';
      final givenNames =
          nameSplit.length > 1 ? nameSplit[1].replaceAll('<', ' ').trim() : '';

      // Line 2: L898902C36UTO7408122F1204159ZE184226B<<<<<10
      final passportNo =
          l2.length >= 9 ? l2.substring(0, 9).replaceAll('<', '').trim() : '';
      final nationality =
          l2.length >= 13
              ? l2.substring(10, 13).replaceAll('<', '').trim()
              : '';

      // Birth date: YYMMDD
      DateTime? dob;
      if (l2.length >= 19) {
        final yy = int.tryParse(l2.substring(13, 15)) ?? 0;
        final mm = int.tryParse(l2.substring(15, 17)) ?? 1;
        final dd = int.tryParse(l2.substring(17, 19)) ?? 1;
        final year = yy > 30 ? 1900 + yy : 2000 + yy;
        dob = DateTime(year, mm, dd);
      }

      final sex = l2.length >= 21 ? l2.substring(20, 21) : 'M';

      // Expiry date: YYMMDD
      DateTime? expiry;
      if (l2.length >= 27) {
        final yy = int.tryParse(l2.substring(21, 23)) ?? 0;
        final mm = int.tryParse(l2.substring(23, 25)) ?? 1;
        final dd = int.tryParse(l2.substring(25, 27)) ?? 1;
        final year = 2000 + yy;
        expiry = DateTime(year, mm, dd);
      }

      return PassportData(
        documentType: 'Passport (P)',
        issuingCountry: country,
        surname: surname,
        givenNames: givenNames,
        passportNumber: passportNo,
        nationality: nationality,
        dateOfBirth: dob,
        sex: sex == 'F' ? 'Female' : 'Male',
        expiryDate: expiry,
        isValid: true,
        rawMrz: '$l1\n$l2',
      );
    } catch (_) {
      return const PassportData(isValid: false);
    }
  }

  PassportData _parseGeneralPassportText(String text) {
    return PassportData(
      documentType: 'Passport',
      passportNumber: 'Detected from Scan',
      surname: text
          .split('\n')
          .firstWhere((l) => l.length > 3, orElse: () => 'Document'),
      isValid: true,
      rawMrz: text,
    );
  }
}
