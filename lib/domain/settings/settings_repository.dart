// VERIFY: OQ-B1 — key strings on AppSettings must be confirmed against the
// upstream GNOME Buffer gschema before TASK-13 implements this interface.
import 'package:foglietto/domain/settings/app_settings.dart';

/// Port (repository interface) for persisting and retrieving [AppSettings].
///
/// Contract:
/// - [load] always returns a valid [AppSettings]. If no persisted settings
///   exist for a given key, the field's default value is used — this method
///   never throws due to missing keys.
/// - [save] is the single mutation point for all settings. Implementations
///   must write every field atomically; partial writes are forbidden.
abstract interface class SettingsRepository {
  /// Loads persisted settings.
  ///
  /// Returns [AppSettings] with defaults for any keys absent from the store.
  /// Never throws on missing keys.
  Future<AppSettings> load();

  /// Persists [settings] to the backing store.
  ///
  /// Writes every field sequentially (single mutation point for callers).
  /// Implementations may issue one write per field internally; partial writes
  /// across a crash between two writes are acceptable given the recovery model.
  Future<void> save(AppSettings settings);
}
