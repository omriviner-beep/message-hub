import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/db.dart';
import 'core/edition.dart';
import 'core/models.dart';
import 'core/native.dart';
import 'core/settings.dart';
import 'gmail/classifier.dart';
import 'gmail/gmail_service.dart';
import 'package:googleapis/gmail/v1.dart' show DetailedApiRequestError;
import 'whatsapp/chat_parser.dart';
import 'whatsapp/media_scanner.dart';
import 'whatsapp/wa_events.dart';

const gmailLabelPrefix = 'ניקוי';

class Progress {
  final String text;
  final double? fraction;
  const Progress(this.text, [this.fraction]);
}

class AppState extends ChangeNotifier {
  final AppDb db;
  final Settings settings;
  final GmailService gmail;

  AppState(this.db, this.settings, this.gmail);

  Progress? progress;
  String? error;
  String? notice;

  List<MailMeta> mail = [];
  String? gmailAddress;

  List<ParsedChat> waChats = [];
  List<WaNotification> waNotifications = [];
  bool waNotificationAccess = false;
  MediaScan? media;
  bool storagePermission = false;

  List<SmsRecord> sms = [];
  bool smsPermission = false;

  bool get isAndroid => Platform.isAndroid;

  void clearError() {
    error = null;
    notice = null;
    notifyListeners();
  }

  int get periodDays => settings.periodDays;
  set periodDays(int v) {
    settings.periodDays = v;
    notifyListeners();
  }

  Future<void> init() async {
    mail = await db.allMail();
    waChats = await db.importedChats();
    notifyListeners();
    if (await gmail.trySilentSignIn()) {
      gmailAddress = await gmail.email().catchError((_) => null);
    }
    if (isAndroid) {
      smsPermission = smsSupportedInEdition && await Permission.sms.isGranted;
      storagePermission = await Permission.manageExternalStorage.isGranted;
      if (waNotificationsInEdition) await refreshWhatsAppNotifications();
      if (smsPermission) await loadSms();
      if (storagePermission) await scanWhatsAppMedia();
    }
    notifyListeners();
  }

  Future<T?> _run<T>(String label, Future<T> Function() f) async {
    error = null;
    progress = Progress(label);
    notifyListeners();
    await NativeBridge.keepScreenOn(true);
    try {
      return await f();
    } catch (e) {
      final raw = '$e';
      error = '$label נכשל: ${describeError(e)}'
          '${describeError(e) == raw ? '' : '\n\nפרטים טכניים: ${raw.length > 300 ? '${raw.substring(0, 300)}…' : raw}'}';
      return null;
    } finally {
      await NativeBridge.keepScreenOn(false);
      progress = null;
      notifyListeners();
    }
  }

  void _progress(String text, [double? fraction]) {
    progress = Progress(text, fraction);
    notifyListeners();
  }

  // ----------------------------------------------------------- events for statistics

  List<MsgEvent> get gmailEvents => [
    for (final m in mail)
      MsgEvent(
        time: m.date,
        outgoing: m.isSent,
        source: Source.gmail,
        contact: m.isSent ? '' : (m.senderName.isNotEmpty ? m.senderName : m.sender),
        bytes: m.size,
      ),
  ];

  List<MsgEvent> get whatsappEvents =>
      whatsAppEvents(chats: waChats, notifications: waNotifications, myName: effectiveWaName ?? '');

  List<MsgEvent> get smsEvents => [for (final s in sms) s.toEvent()];

  List<MsgEvent> eventsFor(Set<Source> sources) => [
    if (sources.contains(Source.gmail)) ...gmailEvents,
    if (sources.contains(Source.whatsapp)) ...whatsappEvents,
    if (sources.contains(Source.sms)) ...smsEvents,
  ];

  String? get effectiveWaName => settings.waMyName.isNotEmpty ? settings.waMyName : guessMyName(waChats);

  // ----------------------------------------------------------------------- Gmail

  Future<void> connectGmail() async {
    await _run('התחברות ל-Gmail', () async {
      await gmail.signIn();
      gmailAddress = await gmail.email();
      if (gmailAddress != null && !settings.myAddresses.contains(gmailAddress)) {
        settings.myAddresses = [...settings.myAddresses, gmailAddress!];
      }
    });
    // First connection: start scanning right away.
    if (gmailAddress != null && mail.isEmpty && error == null) await scanGmail();
  }

  Future<void> disconnectGmail() => _run('ניתוק', () async {
    await gmail.signOut();
    await db.clearGmail();
    mail = [];
    gmailAddress = null;
  });

  Future<void> scanGmail({bool refresh = false}) => _run('סריקת Gmail', () async {
    double? fraction;
    gmail.onQuotaWait = (w) =>
        _progress('הגענו למכסת הבקשות של Google לדקה. ממשיך בעוד ${w.inSeconds} שניות...', fraction);
    try {
      final cfg = settings.classifierConfig();
      // Sent mail rarely changes who your friends are - collect it once.
      if (cfg.friendsFromSent && (refresh || (await db.contacted()).isEmpty)) {
        _progress('אוסף כתובות מתיקיית "נשלח"...');
        try {
          await db.addContacted(await gmail.contactedAddresses());
        } catch (_) {
          // Only improves "friends" detection - never worth failing the scan over.
        }
      }
      _progress('מחפש הודעות...');
      final ids = await gmail.listIds(settings.gmailQuery, max: settings.gmailMax);
      final known = refresh ? <String>{} : await db.knownMailIds();
      final fresh = ids.where((i) => !known.contains(i)).toList();
      notice = fresh.isEmpty
          ? 'אין הודעות חדשות לסריקה (נמצאו ${ids.length} הודעות לפי השאילתה, כולן כבר נסרקו). '
                'כדי לסרוק הודעות ישנות יותר, שנה את שאילתת החיפוש במסך ההגדרות.'
          : null;
      final clf = MailClassifier(cfg, contacted: await db.contacted());
      final tax = taxonomy;
      for (var i = 0; i < fresh.length; i += 100) {
        final chunk = fresh.sublist(i, (i + 100).clamp(0, fresh.length));
        final got = await gmail.fetchMeta(
          chunk,
          onProgress: (d) {
            fraction = (i + d) / fresh.length;
            _progress('מוריד כותרות ${i + d}/${fresh.length}', fraction);
          },
        );
        for (final m in got) {
          m.category = clf.classifyKey(m, tax);
        }
        // Saved per chunk: an interrupted scan resumes where it stopped.
        await db.upsertMail(got);
        final gotIds = {for (final g in got) g.id};
          mail = [...mail.where((m) => !gotIds.contains(m.id)), ...got];
        notifyListeners();
      }
      await reclassify();
    } finally {
      gmail.onQuotaWait = null;
    }
  });

  Future<void> reclassify() async {
    final clf = MailClassifier(settings.classifierConfig(), contacted: await db.contacted());
    final tax = taxonomy;
    final all = await db.allMail();
    for (final m in all) {
      m.category = clf.classifyKey(m, tax);
    }
    await db.upsertMail(all);
    mail = all;
    notifyListeners();
  }

  Taxonomy get taxonomy => settings.taxonomy();

  /// Mail per category key, counting each message once under its own key.
  Map<String, List<MailMeta>> mailByCategory() {
    final out = <String, List<MailMeta>>{};
    for (final m in mail) {
      if (!m.isSent) out.putIfAbsent(m.category ?? MailCategory.other.name, () => []).add(m);
    }
    return out;
  }

  // ------------------------------------------------------- category editing

  Future<void> saveCustomCategory(CustomCategory c) async {
    settings.saveCustomCategory(c);
    await reclassify();
  }

  Future<void> deleteCustomCategory(String id) async {
    settings.deleteCustomCategory(id);
    await reclassify();
  }

  Future<void> setCategoryEnabled(MailCategory c, bool enabled) async {
    final d = settings.disabledCategories;
    enabled ? d.remove(c) : d.add(c);
    settings.disabledCategories = d;
    await reclassify();
  }

  /// "Always file this sender under ..." (null clears it).
  Future<void> setSenderCategory(String sender, String? key) async {
    settings.setSenderOverride(sender, key);
    await reclassify();
  }

  /// Never touches starred mail; Gmail-"important" only if [includeImportant].
  /// [categories] are keys; pass `taxonomy.subtree(key)` to include sub-categories.
  List<MailMeta> selectMail({
    Set<String>? categories,
    Set<String>? senders,
    int? olderThanDays,
    bool unreadOnly = false,
    bool includeImportant = false,
    bool includeStarred = false,
    bool inboxOnly = false,
  }) {
    final cutoff = olderThanDays == null ? null : DateTime.now().subtract(Duration(days: olderThanDays));
    return mail
        .where(
          (m) =>
              (includeStarred || !m.isStarred) &&
              (includeImportant || !m.isImportant) &&
              (categories == null || categories.contains(m.category)) &&
              (senders == null || senders.contains(m.sender)) &&
              (cutoff == null || m.date.isBefore(cutoff)) &&
              (!unreadOnly || m.isUnread) &&
              (!inboxOnly || m.inInbox),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> trashMail(List<MailMeta> msgs) => _run('העברה לאשפה', () async {
    final ids = msgs.map((m) => m.id).toList();
    await gmail.trash(ids, onProgress: (d) => _progress('מעביר לאשפה $d/${ids.length}', d / ids.length));
    await db.deleteMail(ids);
    final gone = ids.toSet();
    mail = mail.where((m) => !gone.contains(m.id)).toList();
  });

  Future<void> archiveMail(List<MailMeta> msgs) => _run('ארכוב', () async {
    await gmail.archive(msgs.map((m) => m.id).toList());
    for (final m in msgs) {
      m.labels.remove('INBOX');
    }
    await db.upsertMail(msgs);
  });

  Future<void> labelMail() => _run('הוספת תוויות', () async {
    final tax = taxonomy;
    final groups = <String, List<String>>{};
    for (final m in mail) {
      if (m.category != null && m.category != MailCategory.other.name && !m.isSent) {
        groups.putIfAbsent(m.category!, () => []).add(m.id);
      }
    }
    // Nested labels: "ניקוי/קבלות/אמזון" needs "ניקוי/קבלות" to exist as well.
    final names = {for (final k in groups.keys) k: '$gmailLabelPrefix/${tax.path(k)}'};
    final all = <String>{gmailLabelPrefix};
    for (final n in names.values) {
      final parts = n.split('/');
      for (var i = 1; i <= parts.length; i++) {
        all.add(parts.take(i).join('/'));
      }
    }
    final ids = await gmail.ensureLabels(all.toList()..sort((a, b) => a.length.compareTo(b.length)));
    for (final e in groups.entries) {
      _progress('מתייג ${tax.label(e.key)}...');
      await gmail.modify(e.value, add: [ids[names[e.key]]!]);
    }
  });

  // -------------------------------------------------------------------- WhatsApp

  /// Imports exported chats: plain .txt, or .zip ("with media" exports).
  Future<int> importWhatsAppChats(List<({String name, Uint8List bytes})> files) async {
    return await _run('ייבוא צ\'אטים', () async {
          var added = 0;
          for (final f in files) {
            String? text;
            var attachments = 0;
            if (f.name.toLowerCase().endsWith('.zip')) {
              final archive = ZipDecoder().decodeBytes(f.bytes);
              for (final entry in archive.files) {
                if (!entry.isFile) continue;
                if (entry.name.toLowerCase().endsWith('.txt') && text == null) {
                  text = _decodeUtf8(entry.content);
                } else {
                  attachments += entry.size;
                }
              }
            } else {
              text = _decodeUtf8(f.bytes);
            }
            if (text == null) continue;
            final chat = parseChat(text, chatName: chatNameFromFile(f.name), attachmentBytes: attachments);
            if (chat.messages.isEmpty) {
              throw FormatException('לא זוהו הודעות בקובץ ${f.name}');
            }
            added += await db.importChat(chat);
          }
          waChats = await db.importedChats();
          return added;
        }) ??
        0;
  }

  Future<void> deleteImportedChat(String name) async {
    await db.deleteChat(name);
    waChats = await db.importedChats();
    notifyListeners();
  }

  Future<void> refreshWhatsAppNotifications() async {
    if (!isAndroid || !waNotificationsInEdition) return;
    waNotificationAccess = await NativeBridge.notificationAccessGranted();
    waNotifications = await NativeBridge.whatsAppNotifications();
    notifyListeners();
  }

  Future<bool> requestStoragePermission() async {
    storagePermission = (await Permission.manageExternalStorage.request()).isGranted;
    notifyListeners();
    return storagePermission;
  }

  Future<void> scanWhatsAppMedia() => _run('סריקת מדיה של וואטסאפ', () async {
    media = await compute(scanMedia, androidWhatsAppRoots);
  });

  Future<(int, int)> deleteWhatsAppMedia(List<MediaFile> files) async {
    final r = await _run('מחיקת קבצים', () async {
      final res = await deleteMedia(files);
      media = await compute(scanMedia, androidWhatsAppRoots);
      return res;
    });
    return r ?? (0, 0);
  }

  // ------------------------------------------------------------------------- SMS

  Future<void> requestSmsPermission() async {
    final res = await [Permission.sms, Permission.contacts].request();
    smsPermission = res[Permission.sms]?.isGranted ?? false;
    if (smsPermission) await loadSms();
    notifyListeners();
  }

  Future<void> loadSms() => _run('קריאת SMS', () async {
    sms = await NativeBridge.readSms();
  });
}

String _decodeUtf8(List<int> bytes) {
  // Strip UTF-8 BOM if present; tolerate malformed sequences.
  final b = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? bytes.sublist(3) : bytes;
  return const Utf8Decoder(allowMalformed: true).convert(b);
}

/// Short, human error text (no "Bad state:" / exception class noise).
String describeError(Object e) {
  if (isQuotaError(e)) {
    return 'חריגה ממכסת הבקשות של Google. ההודעות שכבר הורדו נשמרו. נסה שוב בעוד דקה והסריקה תמשיך מאותה נקודה.';
  }
  if (isTransientError(e)) {
    return 'אין חיבור יציב לאינטרנט (או שהשרת של Google לא ענה). ההודעות שכבר הורדו נשמרו. בדוק את החיבור ולחץ שוב על סריקה, והיא תמשיך מאותה נקודה.';
  }
  if (e is DetailedApiRequestError) return '${e.message ?? 'שגיאה'} (${e.status})';
  if (e is StateError) return e.message;
  if (e is FormatException) return e.message;
  return '$e';
}
