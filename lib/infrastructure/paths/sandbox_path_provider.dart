import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the application-support base directory.
///
/// Defaults to [getApplicationSupportDirectory]; tests inject a stub so that
/// no platform channel is invoked.
typedef AppSupportDirResolver = Future<Directory> Function();

/// Provides sandboxed directory paths for the buffer app.
///
/// M1 contract: path composition only — no directory creation, no file I/O.
/// [MissingPlatformDirectoryException] from the resolver propagates unchanged.
class SandboxPathProvider {
  const SandboxPathProvider({AppSupportDirResolver? resolver})
    : _resolver = resolver ?? getApplicationSupportDirectory;

  final AppSupportDirResolver _resolver;

  /// Returns the [Directory] where recovery files are stored.
  ///
  /// Composes `<applicationSupportDirectory>/recovery` using [p.join] so that
  /// a trailing slash on the base produces exactly one path separator (EC-09).
  ///
  /// Does NOT create the directory (M1 — composition only).
  Future<Directory> recoveryDirectory() async {
    final base = await _resolver();
    return Directory(p.join(base.path, 'recovery'));
  }
}
