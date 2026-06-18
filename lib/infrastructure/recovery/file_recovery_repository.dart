import 'dart:convert';
import 'dart:io';

import 'package:foglietto/domain/recovery/recovery_filename.dart';
import 'package:foglietto/domain/recovery/recovery_note.dart';
import 'package:foglietto/domain/recovery/recovery_preview.dart';
import 'package:foglietto/domain/recovery/recovery_repository.dart';
import 'package:foglietto/infrastructure/paths/sandbox_path_provider.dart';
import 'package:path/path.dart' as p;

/// Produces UTC ISO-8601 timestamps. Injectable for deterministic tests.
typedef NowUtcProvider = DateTime Function();

/// Creates a [Directory] at the given path. Injectable so tests can inject
/// a [Directory] subclass that throws on [create] to verify error propagation.
typedef DirectoryFactory = Directory Function(String path);

/// Resolves the recovery [Directory] synchronously. Injectable for [saveSync]
/// tests and for the production lifecycle host (which obtains the base dir
/// at startup via `path_provider` and stores it before the first pause event).
///
/// Required when [FileRecoveryRepository.saveSync] is called. The production
/// caller (T-03 lifecycle host) provides this after an awaited
/// `getApplicationSupportDirectory()` at app startup.
typedef SyncRecoveryDirResolver = Directory Function();

/// Concrete [RecoveryRepository] that persists recovery files as flat `.txt`
/// files under `<applicationSupportDirectory>/recovery/`.
///
/// ## Save algorithm (FR-M2-10, FR-M2-11, FR-M2-12, §5.2)
///
/// 1. Creates the recovery directory recursively (only in the save path —
///    [SandboxPathProvider.recoveryDirectory] remains composition-only so the
///    M1 no-create test stays green).
/// 2. Computes a UTC ISO-8601 fixed-width filename with colons replaced by
///    `-`, e.g. `2026-06-13T19-20-05-123Z.txt`, ensuring lexicographic order
///    equals chronological order (R-16, NFR-M2-03).
/// 3. On filename collision (`existsSync()`), appends `-1`, `-2`, … before
///    `.txt` — never overwrites (EC-M2-07).
/// 4. Writes the text as UTF-8 (FR-M2-12).
/// 5. Returns the written [File].
///
/// ## Concurrency contract (BUG-004)
///
/// All async writes are serialised on a private [_writeChain] future. Each
/// [save] enqueues its resolve+write on the tail of the chain before
/// returning, so concurrent callers never interleave the
/// [_resolveFile]+[writeAsString] sequence.  A failing save does NOT poison
/// the chain: the internal chain tail swallows the error via [catchError]
/// while the future returned to the caller still propagates it normally
/// (EC-M2-09 is preserved).
///
/// [saveSync] does NOT participate in [_writeChain] — it is self-contained
/// and runs synchronously to completion before returning.
///
/// ## Error contract
///
/// [FileSystemException] from any I/O operation propagates to the caller
/// unchanged (EC-M2-09). The caller (lifecycle host) is responsible for
/// catching and logging it.
///
/// ## Precondition
///
/// The use case ([SaveBufferToRecovery]) guarantees `text.trim().isNotEmpty`
/// before calling [save] or [saveSync]. This class does not re-validate.
class FileRecoveryRepository implements RecoveryRepository {
  FileRecoveryRepository({
    required this._pathProvider,
    NowUtcProvider? nowUtc,
    DirectoryFactory? directoryFactory,
    this._syncRecoveryDir,
  }) : _nowUtc = nowUtc ?? _defaultNow,
       _directoryFactory = directoryFactory ?? _defaultDirectoryFactory;

  final SandboxPathProvider _pathProvider;
  final NowUtcProvider _nowUtc;
  final DirectoryFactory _directoryFactory;

  /// Synchronous recovery-directory resolver for [saveSync].
  ///
  /// Must be provided when [saveSync] will be called. The production T-03
  /// lifecycle host supplies this after an awaited `getApplicationSupportDirectory`
  /// at startup. Tests inject it directly as a closure over their temp dir.
  final SyncRecoveryDirResolver? _syncRecoveryDir;

  /// Serialises concurrent async saves so that [_resolveFile]+[writeAsString]
  /// is never interleaved across two callers (BUG-004 / EC-M2-07).
  ///
  /// The chain tail only swallows errors to avoid poisoning subsequent saves;
  /// the future returned to each individual caller still surfaces its own error.
  Future<void> _writeChain = Future<void>.value();

  static DateTime _defaultNow() => DateTime.now().toUtc();
  static Directory _defaultDirectoryFactory(String path) => Directory(path);

  @override
  Future<File> save(String text) {
    // Enqueue this save on the tail of the chain.  The returned future is the
    // individual op's future — callers observe THIS op's result or error.
    // The chain tail uses catchError so a failed op does not block later saves.
    final op = _writeChain.then((_) => _doSave(text));
    // Advance the chain on the void-typed projection so the catchError handler
    // is typed correctly (Future<void> does not require a return value).  The
    // original `op` future is returned to the caller and still propagates its
    // own error normally.
    _writeChain = op.then((_) {}).catchError((_) {});
    return op;
  }

  /// Performs the actual directory creation, filename resolution, and write.
  /// Must only be called from within the serialised [_writeChain].
  Future<File> _doSave(String text) async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    final dirToCreate = _directoryFactory(recoveryDir.path);
    await dirToCreate.create(recursive: true);

    final stem = _buildStem(_nowUtc());
    final file = _resolveFile(recoveryDir, stem);

    await file.writeAsString(text, encoding: utf8);
    return file;
  }

  // --- M5 additions (list/read/delete/deleteAll/trim) ----------------------

  @override
  Future<List<RecoveryNote>> list() async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    if (!recoveryDir.existsSync()) return const [];

    final txtFiles = _listTxtFiles(recoveryDir);

    final notes = <RecoveryNote>[];
    for (final file in txtFiles) {
      final filename = p.basename(file.path);
      final savedAt = RecoveryFilename.parse(filename);
      if (savedAt == null) continue; // skip malformed — never fatal

      final head = _readHead(file);
      final preview = RecoveryPreview.truncate(head);
      notes.add(
        RecoveryNote(path: file.path, savedAt: savedAt, preview: preview),
      );
    }

    // Return newest-first (descending by savedAt parsed from filename).
    notes.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return notes;
  }

  @override
  Future<String> read(RecoveryNote note) async {
    return File(note.path).readAsString(encoding: utf8);
  }

  @override
  Future<void> delete(RecoveryNote note) async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    if (!recoveryDir.existsSync()) return;

    final file = File(note.path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteAll() async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    if (!recoveryDir.existsSync()) return;

    for (final file in _listTxtFiles(recoveryDir)) {
      await file.delete();
    }
  }

  @override
  Future<void> trim(int keep) async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    if (!recoveryDir.existsSync()) return;

    final files = _listTxtFiles(recoveryDir);
    if (files.length <= keep) return;

    // Sort lexicographically by filename (fixed-width UTC ISO-8601 names =>
    // name order == chronological order). NEVER use mtime (NFR-M5-01).
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    // Delete the oldest (smallest names) — the N-keep at the front.
    final toDelete = files.sublist(0, files.length - keep);
    for (final file in toDelete) {
      await file.delete();
    }
  }

  // --- NEW synchronous save path (Defect B, C-04) --------------------------

  /// Persists [text] to the recovery store SYNCHRONOUSLY before returning.
  ///
  /// Reuses [_buildStem] and [_resolveFile] so the filename format is
  /// byte-identical to the async [save] path (C-05, NFR-M5-01). Does NOT
  /// participate in [_writeChain] — synchronous execution is inherently atomic
  /// with respect to other callers on the same isolate thread.
  ///
  /// [FileSystemException] propagates unchanged to the caller (EC-M2-08).
  ///
  /// Requires [syncRecoveryDir] to have been provided at construction time;
  /// throws [StateError] if it was not.
  @override
  File saveSync(String text, {int keep = 10}) {
    if (_syncRecoveryDir == null) {
      throw StateError(
        'FileRecoveryRepository.saveSync requires syncRecoveryDir to be '
        'provided at construction time.',
      );
    }

    final dir = _directoryFactory(_syncRecoveryDir().path);
    dir.createSync(recursive: true);

    final stem = _buildStem(_nowUtc());
    final file = _resolveFile(dir, stem);

    file.writeAsStringSync(text, encoding: utf8);

    _trimSync(dir, keep);

    return file;
  }

  /// Retains the newest [keep] `.txt` files by LEXICOGRAPHIC filename
  /// (NFR-M5-01 — NEVER mtime). No-op when file count <= [keep].
  void _trimSync(Directory dir, int keep) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.txt')
        .toList();
    if (files.length <= keep) return;

    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final toDelete = files.sublist(0, files.length - keep);
    for (final file in toDelete) {
      file.deleteSync();
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Returns all `.txt` [File]s in [dir] without sorting (caller sorts).
  List<File> _listTxtFiles(Directory dir) {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.txt')
        .toList();
  }

  /// Reads at most [_previewReadLimit] bytes from the start of [file] as UTF-8.
  ///
  /// A bounded read avoids loading arbitrarily large files for a preview.
  /// [RecoveryPreview.truncate] then collapses newlines and hard-cuts to 80.
  static const int _previewReadLimit = 512;

  String _readHead(File file) {
    final raf = file.openSync();
    try {
      final bytes = raf.readSync(_previewReadLimit);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  }

  /// Converts [now] to the canonical filename stem, e.g. `2026-06-13T19-20-05-123Z`.
  ///
  /// Format: `YYYY-MM-DDTHH-MM-SS-mmmZ` — colons replaced by `-` so the name
  /// is filesystem-safe and lexicographic order equals chronological order.
  String _buildStem(DateTime now) {
    final y = _pad(now.year, 4);
    final mo = _pad(now.month, 2);
    final d = _pad(now.day, 2);
    final h = _pad(now.hour, 2);
    final mi = _pad(now.minute, 2);
    final s = _pad(now.second, 2);
    final ms = _pad(now.millisecond, 3);
    return '$y-$mo-${d}T$h-$mi-$s-${ms}Z';
  }

  /// Resolves the write target, appending `-1`, `-2`, … on collision.
  File _resolveFile(Directory dir, String stem) {
    var candidate = File('${dir.path}/$stem.txt');
    var suffix = 0;
    while (candidate.existsSync()) {
      suffix += 1;
      candidate = File('${dir.path}/$stem-$suffix.txt');
    }
    return candidate;
  }

  String _pad(int value, int width) => value.toString().padLeft(width, '0');
}
