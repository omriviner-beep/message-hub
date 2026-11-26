import 'dart:convert';

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

  // ------------------------------------------------------------- categories

  Set<MailCategory> get disabledCategories =>
      {for (final n in _list('disabledCategories')) ?MailCategory.values.asNameMap()[n]};
  set disabledCategories(Set<MailCategory> v) =>
      _p.setStringList('disabledCategories', [for (final c in v) c.name]);

  List<CustomCategory> get customCategories => Taxonomy.customsFromJson(_p.getString('customCategories'));
  set customCategories(List<CustomCategory> v) =>
      _p.setString('customCategories', Taxonomy(customs: v).customsJson());

  Map<String, String> get senderOverrides => Taxonomy.overridesFromJson(_p.getString('senderOverrides'));
  set senderOverrides(Map<String, String> v) => _p.setString('senderOverrides', jsonEncode(v));

  Taxonomy taxonomy() => Taxonomy(
        disabled: disabledCategories,
        customs: customCategories,
        senderOverrides: senderOverrides,
      );

  void saveCustomCategory(CustomCategory c) {
    final list = customCategories;
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      list[i] = c;
    } else {
      list.add(c);
    }
    customCategories = list;
  }

  /// Children move up to the deleted category's parent; overrides pointing at it are dropped.
  void deleteCustomCategory(String id) {
    final list = customCategories;
    final gone = list.where((c) => c.id == id).firstOrNull;
    if (gone == null) return;
    customCategories = [
      for (final c in list)
        if (c.id != id) c.parent == id ? c.copyWith(parent: () => gone.parent) : c,
    ];
    senderOverrides = {
      for (final e in senderOverrides.entries)
        if (e.value != id) e.key: e.value,
    };
  }

  void setSenderOverride(String sender, String? key) {
    final m = senderOverrides;
    if (key == null) {
      m.remove(sender);
    } else {
      m[sender] = key;
    }
    senderOverrides = m;
  }

  ClassifierConfig classifierConfig() => ClassifierConfig(
        disabled: disabledCategories,
        myAddresses: myAddresses.map((e) => e.toLowerCase()).toSet(),
        familyAddresses: familyAddresses.map((e) => e.toLowerCase()).toSet(),
        familyNames: familyNames.map((e) => e.toLowerCase()).toList(),
        friendAddresses: friendAddresses.map((e) => e.toLowerCase()).toSet(),
        friendsFromSent: friendsFromSent,
      );
}

List<String> splitList(String s) =>
    s.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
