import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// What each snapshot says about itself. Readable without the password, so a
/// device can tell whether it has anything to do without decrypting.
class SnapshotHeader {
  final String rev;

  /// Every revision this one descends from, oldest first (capped).
  final List<String> chain;
  final String device;
  final DateTime at;
  final int dbVersion;

  /// The data's compatibility level (HybridSync.dataCompat of the app that
  /// wrote it). Files from before it existed are level 1.
  final int compat;

  /// Version of the app that wrote it ("1.15.14"), to tell the user which one
  /// to install. Null in files from before it existed.
  final String? appVersion;

  /// What the content is: [payloadDatabase], or null for the full backup JSON
  /// of the files from before it existed.
  final String? payload;

  const SnapshotHeader({
    required this.rev,
    required this.chain,
    required this.device,
    required this.at,
    required this.dbVersion,
    this.compat = 1,
    this.appVersion,
    this.payload,
  });

  Map<String, dynamic> toJson() => {
    'rev': rev,
    'chain': chain,
    'device': device,
    'at': at.toUtc().toIso8601String(),
    'dbVersion': dbVersion,
    'compat': compat,
    'appVersion': ?appVersion,
    'payload': ?payload,
  };

  factory SnapshotHeader.fromJson(Map<String, dynamic> json) => SnapshotHeader(
    rev: json['rev'] as String,
    chain: (json['chain'] as List).cast<String>(),
    device: json['device'] as String,
    at: DateTime.parse(json['at'] as String).toLocal(),
    dbVersion: json['dbVersion'] as int,
    compat: json['compat'] as int? ?? 1,
    appVersion: json['appVersion'] as String?,
    payload: json['payload'] as String?,
  );
}

const payloadDatabase = 'sqlite';

/// The database file itself and the portable preferences, as one payload:
/// the length of the preferences (4 bytes), the preferences, the file.
Uint8List packDatabase(String preferences, Uint8List database) {
  final prefs = utf8.encode(preferences);
  final packed = Uint8List(4 + prefs.length + database.length);
  ByteData.sublistView(packed).setUint32(0, prefs.length);
  packed.setRange(4, 4 + prefs.length, prefs);
  packed.setRange(4 + prefs.length, packed.length, database);
  return packed;
}

/// Throws [FormatException] on anything that [packDatabase] did not write.
({String preferences, Uint8List database}) unpackDatabase(Uint8List packed) {
  if (packed.length < 4) throw const FormatException('Empty database payload');
  final length = ByteData.sublistView(packed).getUint32(0);
  if (4 + length > packed.length) {
    throw const FormatException('Damaged database payload');
  }
  return (
    preferences: utf8.decode(Uint8List.sublistView(packed, 4, 4 + length)),
    database: Uint8List.sublistView(packed, 4 + length),
  );
}

/// Whether [remote] was written by an app this one cannot follow: a newer
/// database schema, or data whose meaning changed in a way older apps would
/// read or write wrong ([compat] raised). Such a device only reads, until the
/// app is updated: writing would send data the newer devices misread, or
/// replace theirs with an older shape.
bool needsNewerApp(
  SnapshotHeader remote, {
  required int compat,
  required int dbVersion,
}) => remote.compat > compat || remote.dbVersion > dbVersion;

enum SyncAction { nothing, push, apply, conflict }

/// The whole sync protocol. [localChain] ends in the revision this device last
/// wrote or applied (empty when it never synced). [dirty] = the user changed
/// something here since then. Changes on both sides are never merged nor
/// silently dropped: that is a [SyncAction.conflict], for the user to decide.
SyncAction decideSync({
  required List<String> localChain,
  required bool dirty,
  required SnapshotHeader? remote,
  required bool localIsEmpty,
}) {
  final base = localChain.isEmpty ? null : localChain.last;
  // The database is gone (a new one was created) though the folder has data:
  // receive it. Sending the empty one would wipe the other devices. Only if the
  // user changed something since then is it a question.
  if (remote != null && localIsEmpty) {
    return dirty ? SyncAction.conflict : SyncAction.apply;
  }
  if (remote == null) {
    return dirty || base == null ? SyncAction.push : SyncAction.nothing;
  }
  if (remote.rev == base) {
    return dirty ? SyncAction.push : SyncAction.nothing;
  }
  if (base == null) return SyncAction.conflict;
  if (remote.chain.contains(base)) {
    return dirty ? SyncAction.conflict : SyncAction.apply;
  }
  // Older than what this device already has (an old copy came back).
  if (localChain.contains(remote.rev)) return SyncAction.push;
  // Both sides moved on while apart.
  return SyncAction.conflict;
}

/// A daily backup in the sync folder: `aupp_backup_2026-10-30_celular.enc`.
/// One set per device, so that two devices never write the same file (Syncthing
/// would make conflict copies). Its conflict copies don't match and are ignored.
class DailyBackup {
  final String name;
  final DateTime day;
  final String device;

  const DailyBackup(this.name, this.day, this.device);

  static final _pattern = RegExp(
    r'^(?:aupp|oinkoin)_backup_(\d{4})-(\d{2})-(\d{2})_([a-z0-9-]+)\.enc$',
  );

  static String nameFor(DateTime day, String device) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'aupp_backup_${day.year}-${two(day.month)}-${two(day.day)}'
        '_$device.enc';
  }

  static DailyBackup? parse(String name) {
    final match = _pattern.firstMatch(name);
    if (match == null) return null;
    return DailyBackup(
      name,
      DateTime(
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
      ),
      match[4]!,
    );
  }
}

/// A backup goes after 90 days, but each device always keeps its 10 latest: an
/// app left unused for months still has them.
List<String> backupsToDelete(
  Iterable<String> names,
  DateTime today, {
  int maxAgeDays = 90,
  int keepAtLeast = 10,
}) {
  final byDevice = <String, List<DailyBackup>>{};
  for (final backup in names.map(DailyBackup.parse).nonNulls) {
    byDevice.putIfAbsent(backup.device, () => []).add(backup);
  }
  final limit = DateTime(today.year, today.month, today.day - maxAgeDays);
  return [
    for (final backups in byDevice.values)
      ...(backups..sort((a, b) => b.day.compareTo(a.day)))
          .skip(keepAtLeast)
          .where((backup) => backup.day.isBefore(limit))
          .map((backup) => backup.name),
  ];
}

const _format = 'aupp-sync-1';

/// Snapshots written before the app was called AUPP.
const _legacyFormat = 'oinkoin-sync-1';
const _iterations = 210000;

Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List.generate(length, (_) => random.nextInt(256)),
  );
}

/// Arguments of [deriveKey] (a plain record, to run in an isolate).
typedef KeyRequest = ({String password, Uint8List salt});

Uint8List deriveKey(KeyRequest request) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(request.salt, _iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(request.password)));
}

GCMBlockCipher _cipher(
  bool encrypt,
  Uint8List key,
  Uint8List nonce,
  Uint8List header,
) => GCMBlockCipher(AESEngine())
  ..init(encrypt, AEADParameters(KeyParameter(key), 128, nonce, header));

/// Arguments of [sealSnapshot].
typedef SealRequest = ({
  Uint8List plain,
  SnapshotHeader header,
  Uint8List key,
  Uint8List salt,
});

/// Gzip + AES-256-GCM. The header is authenticated together with the content.
String sealSnapshot(SealRequest request) {
  final nonce = randomBytes(12);
  final header = jsonEncode(request.header.toJson());
  final sealed = _cipher(
    true,
    request.key,
    nonce,
    Uint8List.fromList(utf8.encode(header)),
  ).process(Uint8List.fromList(gzip.encode(request.plain)));
  return jsonEncode({
    'format': _format,
    'header': header,
    'salt': base64Encode(request.salt),
    'nonce': base64Encode(nonce),
    'data': base64Encode(sealed),
  });
}

/// A snapshot as read from the folder, not decrypted yet.
class SealedSnapshot {
  final SnapshotHeader header;
  final String _headerText;
  final Uint8List salt;
  final Uint8List _nonce;
  final Uint8List _data;

  SealedSnapshot._(
    this.header,
    this._headerText,
    this.salt,
    this._nonce,
    this._data,
  );

  /// Throws [FormatException] on anything else, like a half-written file.
  factory SealedSnapshot.parse(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['format'] != _format && json['format'] != _legacyFormat) {
        throw const FormatException('Unknown snapshot format');
      }
      final headerText = json['header'] as String;
      return SealedSnapshot._(
        SnapshotHeader.fromJson(
          jsonDecode(headerText) as Map<String, dynamic>,
        ),
        headerText,
        base64Decode(json['salt'] as String),
        base64Decode(json['nonce'] as String),
        base64Decode(json['data'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid snapshot: $e');
    }
  }

  /// Arguments for [openSnapshot].
  OpenRequest openWith(Uint8List key) => (
    key: key,
    nonce: _nonce,
    header: Uint8List.fromList(utf8.encode(_headerText)),
    data: _data,
  );
}

typedef OpenRequest = ({
  Uint8List key,
  Uint8List nonce,
  Uint8List header,
  Uint8List data,
});

/// The content, or throws when the password is wrong or the file was altered
/// ([InvalidCipherTextException]).
Uint8List openSnapshot(OpenRequest request) {
  final opened = _cipher(
    false,
    request.key,
    request.nonce,
    request.header,
  ).process(request.data);
  return Uint8List.fromList(gzip.decode(opened));
}
