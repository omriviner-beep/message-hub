/// Scans WhatsApp's media folder on Android (needs "All files access").
library;

import 'dart:io';

import 'package:path/path.dart' as p;

const androidWhatsAppRoots = [
  '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media',
  '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media',
  '/storage/emulated/0/WhatsApp/Media', // Android 10 and older
  '/storage/emulated/0/WhatsApp Business/Media',
];

enum MediaKind {
  images('תמונות', ['WhatsApp Images', 'WhatsApp Business Images']),
  video('סרטונים', ['WhatsApp Video', 'WhatsApp Business Video', 'WhatsApp Video Notes']),
  voice('הודעות קוליות', ['WhatsApp Voice Notes', 'WhatsApp Business Voice Notes']),
  audio('שמע', ['WhatsApp Audio', 'WhatsApp Business Audio']),
  documents('מסמכים', ['WhatsApp Documents', 'WhatsApp Business Documents']),
  gifs('GIF', ['WhatsApp Animated Gifs', 'WhatsApp Business Animated Gifs']),
  stickers('מדבקות', ['WhatsApp Stickers', 'WhatsApp Business Stickers']),
  statuses('סטטוסים', ['.Statuses']),
  other('אחר', []);

  final String label;
  final List<String> folders;
  const MediaKind(this.label, this.folders);

  static MediaKind ofFolder(String name) =>
      MediaKind.values.firstWhere((k) => k.folders.contains(name), orElse: () => MediaKind.other);
}

class MediaFile {
  final String path;
  final int size;
  final DateTime modified;
  final MediaKind kind;
  final bool sent; // files you sent live in a "Sent" sub-folder

  const MediaFile(this.path, this.size, this.modified, this.kind, this.sent);

  String get name => p.basename(path);
}

class MediaScan {
  final List<String> roots;
  final List<MediaFile> files;

  const MediaScan(this.roots, this.files);

  int get totalBytes => files.fold(0, (s, f) => s + f.size);

  Map<MediaKind, ({int bytes, int count})> byKind() {
    final out = <MediaKind, ({int bytes, int count})>{};
    for (final f in files) {
      final cur = out[f.kind] ?? (bytes: 0, count: 0);
      out[f.kind] = (bytes: cur.bytes + f.size, count: cur.count + 1);
    }
    return out;
  }

  List<MediaFile> select({Set<MediaKind>? kinds, int? olderThanDays, int? minBytes, bool? sent, DateTime? now}) {
    final cutoff = olderThanDays == null ? null : (now ?? DateTime.now()).subtract(Duration(days: olderThanDays));
    return files
        .where((f) =>
            (kinds == null || kinds.contains(f.kind)) &&
            (cutoff == null || f.modified.isBefore(cutoff)) &&
            (minBytes == null || f.size >= minBytes) &&
            (sent == null || f.sent == sent))
        .toList()
      ..sort((a, b) => b.size.compareTo(a.size));
  }
}

/// Walks [roots] (top-level entries = media kinds). Run in an isolate: it can be slow.
MediaScan scanMedia(List<String> roots) {
  final existing = roots.where((r) => Directory(r).existsSync()).toList();
  final files = <MediaFile>[];
  for (final root in existing) {
    for (final entity in Directory(root).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.split(p.relative(entity.path, from: root));
      if (rel.length < 2 || rel.last == '.nomedia') continue;
      final stat = entity.statSync();
      files.add(MediaFile(
        entity.path,
        stat.size,
        stat.modified,
        MediaKind.ofFolder(rel.first),
        rel.length > 2 && rel[1].toLowerCase() == 'sent',
      ));
    }
  }
  return MediaScan(existing, files);
}

/// Deletes the given files; returns (deleted count, bytes freed).
Future<(int, int)> deleteMedia(List<MediaFile> files) async {
  var n = 0, bytes = 0;
  for (final f in files) {
    try {
      await File(f.path).delete();
      n++;
      bytes += f.size;
    } on FileSystemException {
      // already gone or not permitted - skip
    }
  }
  return (n, bytes);
}
