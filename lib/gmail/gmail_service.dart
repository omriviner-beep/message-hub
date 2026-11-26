/// Gmail API access: sign-in, metadata scan, trash/archive/label.
library;

import 'dart:async';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gm;
import 'package:http/http.dart' as http;

import 'classifier.dart';

/// gmail.modify: read, label, archive, move to Trash. It cannot delete permanently.
const gmailScopes = [gm.GmailApi.gmailModifyScope];

// OAuth client ids are injected at build time, see README:
//   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

const _headers = ['From', 'Subject', 'List-Unsubscribe', 'To', 'Cc'];

/// Parses `"Name" <a@b.com>` / `a@b.com` into (name, lower-case address).
(String, String) parseAddress(String raw) {
  final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$').firstMatch(raw);
  if (m != null) return (m.group(1)!.trim(), m.group(2)!.trim().toLowerCase());
  return ('', raw.trim().toLowerCase());
}

Set<String> parseAddressList(String raw) => {
      for (final part in raw.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*$)')))
        if (part.contains('@')) parseAddress(part).$2,
    };

MailMeta mailFromApi(gm.Message msg) {
  final h = {for (final x in msg.payload?.headers ?? <gm.MessagePartHeader>[]) x.name!.toLowerCase(): x.value ?? ''};
  final (name, addr) = parseAddress(h['from'] ?? '');
  return MailMeta(
    id: msg.id!,
    sender: addr,
    senderName: name,
    subject: h['subject'] ?? '',
    snippet: msg.snippet ?? '',
    date: DateTime.fromMillisecondsSinceEpoch(int.tryParse(msg.internalDate ?? '') ?? 0),
    labels: msg.labelIds ?? const [],
    listUnsubscribe: h['list-unsubscribe'] ?? '',
    size: msg.sizeEstimate ?? 0,
  );
}

/// Spaces out request starts so all workers together stay under a rate.
///
/// Gmail allows ~15,000 quota units per user per minute; messages.get and
/// messages.trash cost 5 units each, so 40 requests/second = 12,000 units/minute.
class RateLimiter {
  final Duration interval;
  final Future<void> Function(Duration) _sleep;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);

  RateLimiter({int perSecond = 40, Future<void> Function(Duration)? sleep})
      : interval = Duration(microseconds: 1000000 ~/ perSecond),
        _sleep = sleep ?? Future.delayed;

  Future<void> acquire() async {
    final now = DateTime.now();
    final start = _next.isAfter(now) ? _next : now;
    _next = start.add(interval);
    final wait = start.difference(now);
    if (wait > Duration.zero) await _sleep(wait);
  }

  /// Everyone pauses (used after a quota error, since the quota is per minute).
  void pauseFor(Duration d) {
    final until = DateTime.now().add(d);
    if (until.isAfter(_next)) _next = until;
  }
}

bool isQuotaError(Object e) {
  if (e is! gm.DetailedApiRequestError) return false;
  if (e.status == 429) return true;
  final text = '${e.message} ${e.errors.map((x) => x.reason).join(' ')}'.toLowerCase();
  return e.status == 403 && (text.contains('quota') || text.contains('ratelimit'));
}

bool _isTransient(Object e) => e is gm.DetailedApiRequestError && (e.status ?? 0) >= 500;

/// Runs [task] over [items] with at most [parallel] in flight, throttled by [limiter].
/// Quota errors pause all workers for a minute (the quota window) and retry.
Future<List<R>> pooled<T, R>(
  List<T> items,
  Future<R> Function(T) task, {
  int parallel = 8,
  RateLimiter? limiter,
  void Function(int done)? onProgress,
  void Function(Duration wait)? onQuotaWait,
  Duration quotaPause = const Duration(seconds: 60),
  int maxRetries = 5,
}) async {
  final results = <R>[];
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      for (var attempt = 0;; attempt++) {
        await limiter?.acquire();
        try {
          results.add(await task(item));
          break;
        } catch (e) {
          if (attempt >= maxRetries) rethrow;
          if (isQuotaError(e)) {
            onQuotaWait?.call(quotaPause);
            if (limiter != null) {
              limiter.pauseFor(quotaPause);
            } else {
              await Future.delayed(quotaPause);
            }
          } else if (_isTransient(e)) {
            await Future.delayed(Duration(seconds: 1 << attempt));
          } else {
            rethrow;
          }
        }
      }
      onProgress?.call(++done);
    }
  }

  await Future.wait(List.generate(parallel, (_) => worker()));
  return results;
}

class GmailService {
  /// Supplies the Web client id entered in Settings (used when no --dart-define was given).
  final String Function() webClientId;
  GmailService({String Function()? webClientId}) : webClientId = webClientId ?? (() => '');

  /// Shared by every call so scans and cleanups together respect the quota.
  final limiter = RateLimiter();

  /// Called when Google's per-minute quota is hit and the service is waiting.
  void Function(Duration wait)? onQuotaWait;

  GoogleSignInAccount? account;
  gm.GmailApi? _api;
  http.Client? _client;
  bool _initialized = false;

  bool get signedIn => account != null;

  Future<void> _init() async {
    if (_initialized) return;
    final server = _serverClientId.isNotEmpty ? _serverClientId : webClientId().trim();
    if (Platform.isAndroid && server.isEmpty) {
      throw StateError('חסר Web Client ID של Google. הזן אותו במסך ההגדרות (ראה README).');
    }
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && _iosClientId.isNotEmpty ? _iosClientId : null,
      serverClientId: server.isEmpty ? null : server,
    );
    _initialized = true;
  }

  /// Silent sign-in on startup; returns false if the user must tap "connect".
  Future<bool> trySilentSignIn() async {
    try {
      await _init();
      account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return false;
      final authz = await account!.authorizationClient.authorizationForScopes(gmailScopes);
      if (authz == null) return false;
      _setClient(authz);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signIn() async {
    await _init();
    account = await GoogleSignIn.instance.authenticate(scopeHint: gmailScopes);
    final authz = await account!.authorizationClient.authorizationForScopes(gmailScopes) ??
        await account!.authorizationClient.authorizeScopes(gmailScopes);
    _setClient(authz);
  }

  Future<void> signOut() async {
    _client?.close();
    _api = null;
    account = null;
    await GoogleSignIn.instance.disconnect();
  }

  void _setClient(GoogleSignInClientAuthorization authz) {
    _client?.close();
    _client = authz.authClient(scopes: gmailScopes);
    _api = gm.GmailApi(_client!);
  }

  /// Access tokens live ~1 hour; refresh silently before every long operation.
  Future<gm.GmailApi> _fresh() async {
    final acc = account;
    if (acc == null) throw StateError('לא מחובר ל-Gmail');
    final authz = await acc.authorizationClient.authorizationForScopes(gmailScopes) ??
        await acc.authorizationClient.authorizeScopes(gmailScopes);
    _setClient(authz);
    return _api!;
  }

  Future<String?> email() async => (await (await _fresh()).users.getProfile('me')).emailAddress;

  Future<List<String>> listIds(String query, {int max = 5000, List<String>? labelIds}) async {
    final api = await _fresh();
    final ids = <String>[];
    String? token;
    do {
      final r = await api.users.messages.list('me',
          q: query.isEmpty ? null : query, maxResults: 500, pageToken: token, labelIds: labelIds);
      ids.addAll((r.messages ?? []).map((m) => m.id!));
      token = r.nextPageToken;
    } while (token != null && ids.length < max);
    return ids.length > max ? ids.sublist(0, max) : ids;
  }

  Future<List<gm.Message>> _getMeta(List<String> ids, {void Function(int)? onProgress}) async {
    final api = await _fresh();
    return pooled(ids, (id) => api.users.messages.get('me', id, format: 'metadata', metadataHeaders: _headers),
        limiter: limiter, onProgress: onProgress, onQuotaWait: onQuotaWait);
  }

  Future<List<MailMeta>> fetchMeta(List<String> ids, {void Function(int)? onProgress}) async =>
      (await _getMeta(ids, onProgress: onProgress)).map(mailFromApi).toList();

  /// Addresses you wrote to - a strong "this is a real friend" signal.
  Future<Set<String>> contactedAddresses({int max = 500}) async {
    final ids = await listIds('', max: max, labelIds: ['SENT']);
    final out = <String>{};
    for (final m in await _getMeta(ids)) {
      for (final h in m.payload?.headers ?? <gm.MessagePartHeader>[]) {
        final n = h.name!.toLowerCase();
        if (n == 'to' || n == 'cc') out.addAll(parseAddressList(h.value ?? ''));
      }
    }
    return out;
  }

  Future<void> trash(List<String> ids, {void Function(int)? onProgress}) async {
    final api = await _fresh();
    await pooled(ids, (id) => api.users.messages.trash('me', id),
        limiter: limiter, onProgress: onProgress, onQuotaWait: onQuotaWait);
  }

  Future<void> modify(List<String> ids, {List<String> add = const [], List<String> remove = const []}) async {
    final api = await _fresh();
    for (var i = 0; i < ids.length; i += 1000) {
      await api.users.messages.batchModify(
        gm.BatchModifyMessagesRequest(
            ids: ids.sublist(i, (i + 1000).clamp(0, ids.length)), addLabelIds: add, removeLabelIds: remove),
        'me',
      );
    }
  }

  Future<void> archive(List<String> ids) => modify(ids, remove: ['INBOX']);

  Future<Map<String, String>> ensureLabels(List<String> names) async {
    final api = await _fresh();
    final existing = {for (final l in (await api.users.labels.list('me')).labels ?? <gm.Label>[]) l.name!: l.id!};
    for (final n in names) {
      if (!existing.containsKey(n)) {
        final created = await api.users.labels.create(
            gm.Label(name: n, labelListVisibility: 'labelShow', messageListVisibility: 'show'), 'me');
        existing[n] = created.id!;
      }
    }
    return existing;
  }
}
