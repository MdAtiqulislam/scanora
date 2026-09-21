import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService extends GetxService {
  late SharedPreferences _prefs;

  Future<StorageService> init() async {
    _prefs = await SharedPreferences.getInstance();
    return this;
  }

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(key) ?? defaultValue;
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  List<String> getList(String key) => _prefs.getStringList(key) ?? [];
  Future<bool> setList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  Future<bool> remove(String key) => _prefs.remove(key);
}
