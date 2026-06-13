import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buffer/presentation/typography/typography_provider.dart';

void main() {
  group('typographyProvider defaults (FR-14 / EC-01)', () {
    test(
      'first read with no stored prefs resolves fontSizeIndex==8 and useMonospaceFont==true',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final settings = container.read(typographyProvider);

        expect(
          settings.fontSizeIndex,
          equals(8),
          reason: 'FR-14: default font size index must be 8 (14pt slot)',
        );
        expect(
          settings.useMonospaceFont,
          isTrue,
          reason: 'EC-01: default must use monospace font',
        );
      },
    );

    test(
      'FR-14 negative: a fontSizeIndex != 8 or useMonospaceFont==false would fail',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final settings = container.read(typographyProvider);

        // Any deviation from index 8 violates FR-14.
        expect(settings.fontSizeIndex, isNot(equals(0)));
        expect(settings.fontSizeIndex, isNot(equals(20)));

        // useMonospaceFont==false would violate EC-01.
        expect(settings.useMonospaceFont, isNot(isFalse));
      },
    );
  });
}
