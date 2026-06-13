import 'dart:convert';
import 'dart:io';

import 'package:buffer/domain/recovery/recovery_repository.dart';
import 'package:buffer/infrastructure/paths/sandbox_path_provider.dart';

/// Produces UTC ISO-8601 timestamps. Injectable for deterministic tests.
typedef NowUtcProvider = DateTime Function();

/// Creates a [Directory] at the given path. Injectable so tests can inject
/// a [Directory] subclass that throws on [create] to verify error propagation.
typedef DirectoryFactory = Directory Function(String path);

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
/// ## Error contract
///
/// [FileSystemException] from any I/O operation propagates to the caller
/// unchanged (EC-M2-09). The caller (lifecycle host) is responsible for
/// catching and logging it.
///
/// ## Precondition
///
/// The use case ([SaveBufferToRecovery]) guarantees `text.trim().isNotEmpty`
/// before calling [save]. This class does not re-validate.
class FileRecoveryRepository implements RecoveryRepository {
  const FileRecoveryRepository({
    required this._pathProvider,
    NowUtcProvider? nowUtc,
    DirectoryFactory? directoryFactory,
  }) : _nowUtc = nowUtc ?? _defaultNow,
       _directoryFactory = directoryFactory ?? _defaultDirectoryFactory;

  final SandboxPathProvider _pathProvider;
  final NowUtcProvider _nowUtc;
  final DirectoryFactory _directoryFactory;

  static DateTime _defaultNow() => DateTime.now().toUtc();
  static Directory _defaultDirectoryFactory(String path) => Directory(path);

  @override
  Future<File> save(String text) async {
    final recoveryDir = await _pathProvider.recoveryDirectory();
    final dirToCreate = _directoryFactory(recoveryDir.path);
    await dirToCreate.create(recursive: true);

    final stem = _buildStem(_nowUtc());
    final file = _resolveFile(recoveryDir, stem);

    await file.writeAsString(text, encoding: utf8);
    return file;
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
