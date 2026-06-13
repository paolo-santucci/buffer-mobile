import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buffer/domain/typography/typography_settings.dart';

/// Notifier for [TypographySettings].
///
/// M1 ships defaults only (FR-14, EC-01):
///   - fontSizeIndex == 8  → 14pt (slotList[8])
///   - useMonospaceFont == true
///
/// Stepping (+/-), pinch-to-zoom, and OS-font-scale composition are M6 scope.
class TypographyNotifier extends Notifier<TypographySettings> {
  @override
  TypographySettings build() => const TypographySettings();
}

/// Provider surfacing [TypographySettings] with canon defaults.
///
/// Not auto-disposed — typography settings must remain alive for the
/// lifetime of the app (same lifetime contract as [bufferProvider]).
final typographyProvider =
    NotifierProvider<TypographyNotifier, TypographySettings>(
      TypographyNotifier.new,
    );
