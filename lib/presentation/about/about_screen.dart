// TASK-11 (M6): AboutScreen — upstream metadata screen at route /about.
//
// Spec refs: FR-M6-10, FR-M6-11, EC-03, EC-10, NFR-M6-06
// Canon ref: .claude/docs/canon/ui-design-bible.md
//
// Upstream URLs (canon/spec/appearance-and-shell.md §51):
//   issue_url: https://gitlab.gnome.org/cheywood/buffer/-/issues
//   website:   https://gitlab.gnome.org/cheywood/buffer/
//
// CANON GAP: The UI Design Bible (ui-design-bible.md) is silent on About-screen
// layout — the upstream desktop app uses adw::AboutDialog which has no direct
// Flutter equivalent. Decision: Material Scaffold + ListView of ListTiles,
// matching the secondary-screen pattern established by RecoveryScreen.
// <!-- CANON GAP: OQ-M6-12 — about-screen layout. Bible has no About-screen
//      anatomy. Using Material Scaffold + ListView of informational ListTiles,
//      consistent with the secondary-screen pattern (D-007). -->
//
// Seam design (TDD requirement): two injectable interfaces allow tests to
// mock platform channels without ever hitting the real platform:
//   - [PackageInfoSeam]: abstracts package_info_plus lookups.
//   - [UrlLauncherSeam]: abstracts url_launcher canLaunchUrl / launchUrl.
// Production defaults are provided as top-level constants so callers never need
// to pass them explicitly.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:buffer/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Seam interfaces
// ---------------------------------------------------------------------------

/// Abstracts [PackageInfo.fromPlatform] so widget tests can inject a fake.
abstract interface class PackageInfoSeam {
  /// Returns the app version string (e.g. '1.2.3').
  ///
  /// Returns an empty string when the version is unavailable (EC-10).
  Future<String> appVersion();
}

/// Abstracts [canLaunchUrl] / [launchUrl] so widget tests can inject a fake.
abstract interface class UrlLauncherSeam {
  /// Returns true when the system can open [uri].
  Future<bool> canLaunch(Uri uri);

  /// Opens [uri] in the system browser.
  Future<void> launch(Uri uri);
}

// ---------------------------------------------------------------------------
// Production implementations
// ---------------------------------------------------------------------------

/// Production [PackageInfoSeam] backed by [PackageInfo.fromPlatform].
class RealPackageInfoSeam implements PackageInfoSeam {
  const RealPackageInfoSeam();

  @override
  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      // EC-10: empty/absent version → render without throwing.
      return '';
    }
  }
}

/// Production [UrlLauncherSeam] backed by [url_launcher].
class RealUrlLauncherSeam implements UrlLauncherSeam {
  const RealUrlLauncherSeam();

  @override
  Future<bool> canLaunch(Uri uri) => canLaunchUrl(uri);

  @override
  Future<void> launch(Uri uri) => launchUrl(uri);
}

// ---------------------------------------------------------------------------
// Upstream URL constants
// Source: canon/spec/appearance-and-shell.md §51 (application.rs:show_about)
// ---------------------------------------------------------------------------

const _kIssueUrl = 'https://buffer.paolosantucci.com/bug/';
const _kWebsiteUrl = 'https://buffer.paolosantucci.com/';

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// About screen — displays upstream metadata: name, developer, version,
/// GPL-3.0 license, issue-tracker link, and website link.
///
/// Route: `/about` (registered in TASK-16 — [app.dart]).
///
/// Tap targets for URL rows are guarded by [UrlLauncherSeam.canLaunch]:
/// - `canLaunchUrl` → true: row is tappable; tap calls [launchUrl] (EC-03).
/// - `canLaunchUrl` → false: row is disabled / no-op; no exception (EC-03).
///
/// Version is fetched via [PackageInfoSeam.appVersion]; an empty result is
/// rendered without throwing (EC-10).
class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    PackageInfoSeam? packageInfoSeam,
    UrlLauncherSeam? launcherSeam,
  }) : _packageInfoSeam = packageInfoSeam ?? const RealPackageInfoSeam(),
       _launcherSeam = launcherSeam ?? const RealUrlLauncherSeam();

  final PackageInfoSeam _packageInfoSeam;
  final UrlLauncherSeam _launcherSeam;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // <!-- CANON GAP: OQ-M6-12 — secondary-screen app-bar.
    //      Same pattern as RecoveryScreen (D-007). -->
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: FutureBuilder<String>(
        future: _packageInfoSeam.appVersion(),
        builder: (context, snapshot) {
          // EC-10: render gracefully even before version resolves or when empty.
          final version = snapshot.data ?? '';
          return _AboutBody(
            version: version,
            l10n: l10n,
            launcherSeam: _launcherSeam,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body widget (extracted for const + narrow rebuild scope)
// ---------------------------------------------------------------------------

class _AboutBody extends StatelessWidget {
  const _AboutBody({
    required this.version,
    required this.l10n,
    required this.launcherSeam,
  });

  final String version;
  final AppLocalizations l10n;
  final UrlLauncherSeam launcherSeam;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // App name — "Buffer" via ARB appTitle (upstream `application_name`).
        ListTile(title: Text(l10n.appTitle)),
        const Divider(height: 1),

        // Original Developer — "Chris Heywood" from ARB `aboutOriginalDeveloper`.
        ListTile(title: Text(l10n.aboutOriginalDeveloper)),
        const Divider(height: 1),

        // Developer — "Paolo Santucci" from ARB `aboutDeveloper`.
        ListTile(title: Text(l10n.aboutDeveloper)),
        const Divider(height: 1),

        // Version — label from ARB, value from PackageInfo (EC-10: may be empty).
        ListTile(
          title: Text(l10n.aboutVersion),
          subtitle: version.isNotEmpty ? Text(version) : null,
        ),
        const Divider(height: 1),

        // License — GPL-3.0 from ARB `aboutLicense` (NFR-M6-06).
        ListTile(title: Text(l10n.aboutLicense)),
        const Divider(height: 1),

        // Issue tracker — ARB label; URL is a literal (not localized).
        _UrlTile(
          label: l10n.aboutIssues,
          url: _kIssueUrl,
          launcherSeam: launcherSeam,
        ),
        const Divider(height: 1),

        // Website — ARB label; URL is a literal (not localized).
        _UrlTile(
          label: l10n.aboutWebsite,
          url: _kWebsiteUrl,
          launcherSeam: launcherSeam,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// URL tile (async canLaunch guard, EC-03)
// ---------------------------------------------------------------------------

/// A [ListTile] that asynchronously checks [UrlLauncherSeam.canLaunch] before
/// enabling its tap target.
///
/// EC-03: `canLaunchUrl` → false → tile is disabled/no-op; no exception.
class _UrlTile extends StatefulWidget {
  const _UrlTile({
    required this.label,
    required this.url,
    required this.launcherSeam,
  });

  final String label;
  final String url;
  final UrlLauncherSeam launcherSeam;

  @override
  State<_UrlTile> createState() => _UrlTileState();
}

class _UrlTileState extends State<_UrlTile> {
  bool _canLaunch = false;

  @override
  void initState() {
    super.initState();
    _checkCanLaunch();
  }

  Future<void> _checkCanLaunch() async {
    final uri = Uri.parse(widget.url);
    final result = await widget.launcherSeam.canLaunch(uri);
    if (mounted) {
      setState(() => _canLaunch = result);
    }
  }

  Future<void> _launch() async {
    if (!_canLaunch) return; // EC-03: no-op when disabled.
    await widget.launcherSeam.launch(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.label),
      // EC-03: null onTap → tile is disabled (no visual tap response).
      onTap: _canLaunch ? _launch : null,
      trailing: _canLaunch ? const Icon(Icons.open_in_new, size: 20.0) : null,
    );
  }
}
