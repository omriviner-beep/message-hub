/// User-editable category tree: built-in categories (which can be switched off),
/// custom categories and sub-categories, and per-sender overrides.
library;

import 'dart:convert';

import 'classifier.dart';

class CustomCategory {
  final String id; // "c_<timestamp>"
  final String name;
  final String? parent; // category key, or null for a top-level category
  final List<String> senders; // exact addresses
  final List<String> domains; // example.com also matches mail.example.com
  final List<String> keywords; // in subject (or snippet)
  final bool protected;

  const CustomCategory({
    required this.id,
    required this.name,
    this.parent,
    this.senders = const [],
    this.domains = const [],
    this.keywords = const [],
    this.protected = false,
  });

  bool get hasRules => senders.isNotEmpty || domains.isNotEmpty || keywords.isNotEmpty;

  bool matches(MailMeta m) {
    if (senders.any((s) => s.toLowerCase() == m.sender)) return true;
    final dom = domainOf(m.sender);
    if (domains.any((d) {
      final x = d.toLowerCase().replaceFirst(RegExp(r'^@'), '');
      return dom == x || dom.endsWith('.$x');
    })) {
      return true;
    }
    final text = '${m.subject} ${m.snippet}'.toLowerCase();
    return keywords.any((k) => k.trim().isNotEmpty && text.contains(k.toLowerCase()));
  }

  CustomCategory copyWith({
    String? name,
    String? Function()? parent,
    List<String>? senders,
    List<String>? domains,
    List<String>? keywords,
    bool? protected,
  }) =>
      CustomCategory(
        id: id,
        name: name ?? this.name,
        parent: parent != null ? parent() : this.parent,
        senders: senders ?? this.senders,
        domains: domains ?? this.domains,
        keywords: keywords ?? this.keywords,
        protected: protected ?? this.protected,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'parent': parent,
        'senders': senders,
        'domains': domains,
        'keywords': keywords,
        'protected': protected,
      };

  factory CustomCategory.fromJson(Map<String, Object?> j) => CustomCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        parent: j['parent'] as String?,
        senders: [...(j['senders'] as List? ?? const []).cast<String>()],
        domains: [...(j['domains'] as List? ?? const []).cast<String>()],
        keywords: [...(j['keywords'] as List? ?? const []).cast<String>()],
        protected: j['protected'] as bool? ?? false,
      );
}

class Taxonomy {
  final Set<MailCategory> disabled;
  final List<CustomCategory> customs;
  final Map<String, String> senderOverrides; // sender address -> category key

  const Taxonomy({this.disabled = const {}, this.customs = const [], this.senderOverrides = const {}});

  static final _builtIn = MailCategory.values.asNameMap();

  MailCategory? builtIn(String key) => _builtIn[key];
  CustomCategory? custom(String key) => customs.where((c) => c.id == key).firstOrNull;

  /// The category exists and is reachable (built-in and enabled, or custom under existing parents).
  bool exists(String key) {
    final b = builtIn(key);
    if (b != null) return !disabled.contains(b) || b == MailCategory.other;
    final c = custom(key);
    return c != null && (c.parent == null || exists(c.parent!));
  }

  String label(String key) => builtIn(key)?.label ?? custom(key)?.name ?? key;

  String? parentOf(String key) => custom(key)?.parent;

  List<String> childrenOf(String key) => [for (final c in customs) if (c.parent == key) c.id];

  /// Top-level keys in display order: enabled built-ins, then custom categories.
  List<String> get roots => [
        for (final b in MailCategory.values)
          if (!disabled.contains(b) || b == MailCategory.other) b.name,
        for (final c in customs)
          if (c.parent == null) c.id,
      ];

  /// The key and every descendant.
  Set<String> subtree(String key) => {key, for (final c in childrenOf(key)) ...subtree(c)};

  int depth(String key) {
    var d = 0;
    for (var p = parentOf(key); p != null && d < 10; p = parentOf(p)) {
      d++;
    }
    return d;
  }

  /// "קבלות/אמזון" - used for nested Gmail labels.
  String path(String key) {
    final parts = <String>[label(key)];
    for (var p = parentOf(key); p != null && parts.length < 10; p = parentOf(p)) {
      parts.insert(0, label(p));
    }
    return parts.join('/');
  }

  /// Mail from real people (family, friends...) - bulk cleanup asks for extra care.
  bool isProtected(String key) {
    for (String? k = key; k != null; k = parentOf(k)) {
      if (builtIn(k)?.isProtected ?? false) return true;
      if (custom(k)?.protected ?? false) return true;
    }
    return false;
  }

  /// Every key in tree order (parents before children), for pickers and lists.
  List<String> get flatTree {
    final out = <String>[];
    void walk(String k) {
      out.add(k);
      for (final c in childrenOf(k)) {
        walk(c);
      }
    }

    for (final r in roots) {
      walk(r);
    }
    return out;
  }

  // ------------------------------------------------------------------ persistence

  String customsJson() => jsonEncode([for (final c in customs) c.toJson()]);

  static List<CustomCategory> customsFromJson(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      return [for (final j in jsonDecode(s) as List) CustomCategory.fromJson((j as Map).cast<String, Object?>())];
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> overridesFromJson(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }
}
