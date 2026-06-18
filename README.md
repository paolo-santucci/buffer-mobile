# Foglietto

A mobile port of **[Buffer](https://gitlab.gnome.org/cheywood/buffer)** — the minimal
ephemeral text editor for GNOME, originally created by **Chris Heywood** — adapted to
Flutter for Android and iOS.

The app opens to a blank page. The user types. The text is gone when the app closes.
The last 10 notes are silently preserved and recoverable.

> **Unofficial project.** Foglietto is a community-built port and is **not affiliated
> with, endorsed by, or maintained by** Chris Heywood or the GNOME project.

## Credits

Foglietto is based on **Buffer**, the original GNOME desktop application created and
maintained by **Chris Heywood**:

- Original source: <https://gitlab.gnome.org/cheywood/buffer>
- The original is written in Rust (GTK / libadwaita). Foglietto ports parts of that
  work to Flutter (Dart), with substantial portions rewritten to suit the differences of
  mobile platforms.

The original idea, design, and name are Chris Heywood's. This port only aims to bring the
same experience to mobile devices.

## What it does

- Opens instantly to a blank editing space — no files, no setup, no friction.
- Text is **ephemeral**: it disappears when the app is closed.
- The **last 10 notes** are silently preserved in the background and can be recovered.

## License

Licensed under the **[GNU General Public License v3.0](LICENSE) (GPLv3)**.

- Original Buffer code: © **Chris Heywood**.
- Mobile-specific changes and additions: © **Paolo Santucci**.

## Platform targets

- **Android**
- **iOS**
