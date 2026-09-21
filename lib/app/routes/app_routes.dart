part of 'app_pages.dart';

abstract class Routes {
  Routes._();
  static const home = _Paths.home;
  static const scanner = _Paths.scanner;
  static const editor = _Paths.editor;
  static const documents = _Paths.documents;
  static const documentDetail = _Paths.documentDetail;
  static const ocr = _Paths.ocr;
  static const idCardMerge = _Paths.idCardMerge;
  static const settings = _Paths.settings;
}

abstract class _Paths {
  _Paths._();
  static const home = '/home';
  static const scanner = '/scanner';
  static const editor = '/editor';
  static const documents = '/documents';
  static const documentDetail = '/document-detail';
  static const ocr = '/ocr';
  static const idCardMerge = '/id-card-merge';
  static const settings = '/settings';
}
