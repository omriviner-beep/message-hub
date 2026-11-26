import 'package:shared_preferences/shared_preferences.dart';

import '../gmail/classifier.dart';

/// User preferences, persisted in SharedPreferences.
class Settings {
  final SharedPreferences _p;
  Settings(this._p);

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  List<String> _list(String k) => _p.getStringList(k) ?? const [];

  int get periodDays => _p.getInt('periodDays') ?? 30;
  set periodDays(int v) => _p.setInt('periodDays', v);

  String get gmailQuery => _p.getString('gmailQuery') ?? 'newer_than:1y -in:chats';
  set gmailQuery(String v) => _p.setString('gmailQuery', v);

  int get gmailMax => _p.getInt('gmailMax') ?? 5000;
  set gmailMax(int v) => _p.setInt('gmailMax', v);

  List<String> get myAddresses => _list('myAddresses');
  set myAddresses(List<String> v) => _p.setStringList('myAddresses', v);

  List<String> get familyAddresses => _list('familyAddresses');
  set familyAddresses(List<String> v) => _p.setStringList('familyAddresses', v);

  List<String> get familyNames => _list('familyNames');
  set familyNames(List<String> v) => _p.setStringList('familyNames', v);

  List<String> get friendAddresses => _list('friendAddresses');
  set friendAddresses(List<String> v) => _p.setStringList('friendAddresses', v);

  bool get friendsFromSent => _p.getBool('friendsFromSent') ?? true;
  set friendsFromSent(bool v) => _p.setBool('friendsFromSent', v);

  /// OAuth "Web application" client id (Android needs it as serverClientId).
  String get googleWebClientId => _p.getString('googleWebClientId') ?? '';
  set googleWebClientId(String v) => _p.setString('googleWebClientId', v);

  /// Your display name as it appears in exported WhatsApp chats (decides in vs out).
  String get waMyName => _p.getString('waMyName') ?? '';
  set waMyName(String v) => _p.setString('waMyName', v);

  ClassifierConfig classifierConfig() => ClassifierConfig(
        myAddresses: myAddresses.map((e) => e.toLowerCase()).toSet(),
        familyAddresses: familyAddresses.map((e) => e.toLowerCase()).toSet(),
        familyNames: familyNames.map((e) => e.toLowerCase()).toList(),
        friendAddresses: friendAddresses.map((e) => e.toLowerCase()).toSet(),
        friendsFromSent: friendsFromSent,
      );
}

List<String> splitList(String s) =>
    s.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
