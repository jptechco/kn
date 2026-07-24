# Kinetic Notes

A modern fork of [Notational Velocity](https://notational.net/) — the fast, keyboard-driven
note-taking app for macOS that does searching and creating in a single field.

Notational Velocity's last release was in 2011. That build ships `ppc`, `i386` and `x86_64` code
and has no Apple Silicon slice, so on modern Macs it runs only under Rosetta 2 — and Rosetta 2 is
being withdrawn after macOS 26 Tahoe. Kinetic Notes is that application rebuilt to run natively,
with its dead and Intel-only dependencies replaced, and nothing removed that anyone was using.

**Status: 1.0 — production ready, development ongoing.** See [Version history](#version-history)
for what has landed.

---

## System requirements

| | |
|---|---|
| **macOS** | 13.0 Ventura or later |
| **Architectures** | Universal — `arm64` (Apple Silicon) and `x86_64` (Intel), both native |
| **Runtime dependencies** | None. Only system frameworks; nothing bundled, no Homebrew |
| **To build** | Xcode 15 or later |

Rosetta 2 is not required or used.

---

## Installing

1. Download the latest release and drag **Kinetic Notes.app** to your Applications folder.
2. The first launch will be blocked, because release builds are currently only ad-hoc signed:

   > "Kinetic Notes" cannot be opened because Apple cannot verify it is free of malware.

   Right-click the app and choose **Open**, then confirm. You only need to do this once.
   Alternatively: **System Settings → Privacy & Security**, scroll to Security, click
   **Open Anyway**.

This step will disappear once the project has an Apple Developer ID to sign and notarize with.

---

## Coming from Notational Velocity?

**Your existing notes are safe, and Notational Velocity keeps working.** Kinetic Notes is
deliberately a separate application, not an upgrade in place:

- It stores notes in `~/Library/Application Support/Kinetic Notes/`, not in Notational Velocity's
  `Notational Data` folder.
- It uses its own Keychain item for encrypted databases, so changing a passphrase here can never
  affect the one Notational Velocity depends on.
- It has its own bundle identifier and preferences.

You can keep both installed indefinitely.

> **Note:** the first-run import assistant, which copies your Notational Velocity notes into
> Kinetic Notes' own store, is still in development. Until it ships, Kinetic Notes starts with an
> empty database. When it does ship it will *copy*, never move, and will not write to Notational
> Velocity's data at any point — including when the source database is encrypted.

---

## Version history

### 1.1 — in development

**Spanish is back, and the rebrand now reaches every language.**

*Localization*
- **Spanish added as a seventh shipping locale.** A Spanish translation contributed years ago was
  never wired into the build and was left behind under its old directory name. It now ships as
  `es`, and it is complete: the alert and dialog text it originally covered, all four welcome
  notes, and — new in this release — the menus, Preferences and every panel, which had been
  committed as untranslated copies of the English nibs.
- The rebrand from Notational Velocity, which previously covered only English, is applied across
  every locale: alert text, the welcome notes, and the hotkey panel's prompt.
- Translators are credited in-app again. A German, French, Italian or Portuguese About box has
  always named its translator; the Chinese credit had been dropped and is restored, and Spanish
  is credited for the first time. See [Translations](#translations).

*Housekeeping*
- Removed 100+ orphaned localization files: `.strings` overlays superseded years ago by fully
  translated nibs, and the nibs of `TagEditingManager`, a feature that no longer exists.

### 1.0

**Runs natively on Apple Silicon.** The headline change: the app is now a universal `arm64` +
`x86_64` binary with no external dependencies.

*Build and architecture*
- Universal build; deployment target raised from macOS 10.9 to macOS 13.0.
- Fixed the two `IMP` function-pointer casts that modern Clang rejects, in `GlobalPrefs.m` and
  `LinkingEditor.m`.
- Fixed a pointer-returned-as-`BOOL` bug in `NotesTableView.m` that only manifests on `x86_64`,
  where `BOOL` is `signed char` rather than `bool`.
- Removed the obsolete `-whatsloaded` linker flag and the `-sectorder` section-ordering flags,
  neither of which the current linker supports, along with the `.launchorder`/`.freqorder` files.

*Dependencies removed*
- **OpenSSL → CommonCrypto.** Database encryption no longer links Homebrew's `libcrypto`.
  AES-256-CBC output is byte-for-byte identical to the previous OpenSSL implementation, verified
  against the `openssl` command line across empty, sub-block, exact-block and multi-block inputs,
  so **existing encrypted databases still open**. Base64 now uses Foundation.
- **AutoHyperlinks (Adium, 2008) → `NSDataDetector`.** This framework had no Apple Silicon slice,
  so a naive port would have silently lost automatic URL linking in note bodies. `NSDataDetector`
  detects a superset of what it did, including bare `www.` hosts and email addresses.
- **Sparkle 1.5b6 (2008) removed.** Also Intel/PowerPC-only. Automatic updates are switched off
  and the menu item hidden until there is a signing identity to sign an appcast with.

*Identity*
- Renamed to Kinetic Notes throughout, with a new application icon.
- Separate notes directory, Keychain service, bundle identifier and preferences domain, so that
  Notational Velocity is never written to (see [above](#coming-from-notational-velocity)).
- URL scheme is `kineticnotes://`. Kinetic Notes deliberately does *not* claim `nv://`, which an
  installed Notational Velocity registers.
- The Help menu's website items, which pointed at an undefined localized string and so did
  nothing at all, now open this repository.

*Features*
- **First-run import assistant.** On a genuine first launch, Kinetic Notes offers to copy an
  existing Notational Velocity notes directory, including encrypted databases. The offer reports
  how many notes were found where that can be determined without the passphrase. Notational
  Velocity's own directory is only ever read, never written.
- **Dark Mode.** Notes that stored a baked-in foreground colour rendered as black text on the
  dark editor background, making them unreadable; that, the empty-editor panel and the list
  preview text now follow the system appearance.
- **Simplenote sync removed.** Its server was shut down over a decade ago, so the feature could
  not work at all.

### Upstream

Kinetic Notes forks Notational Velocity 2.0 β7. For history before this fork, see
[scrod/nv](https://github.com/scrod/nv).

---

## Building from source

Requires Xcode 15 or later.

```bash
xcodebuild -project Notation.xcodeproj -target Notation -configuration Deployment build
```

The application is written to `build/Deployment/Kinetic Notes.app`. Confirm it came out universal:

```bash
lipo -info "build/Deployment/Kinetic Notes.app/Contents/MacOS/Kinetic Notes"
```

That should report `x86_64 arm64`. To confirm it has no external dependencies:

```bash
otool -L "build/Deployment/Kinetic Notes.app/Contents/MacOS/Kinetic Notes" | grep -v /System/Library
```

Only `/usr/lib` entries should remain.

### A note for contributors

The interface files are compiled Interface Builder 3 nibs. **Do not let Xcode re-save
`MainMenu.nib`** — a modern Interface Builder will upgrade the format and may switch `NSTextView`
to TextKit 2, which the editor (`LinkingEditor.m`, `MultiplePageView.m`) does not use. Four nibs
(`ExporterManager`, `FindPanel`, `ImporterAccessory`, `SavedSearches`) contain only compiled
output and cannot be edited at all.

---

## License and credit

Kinetic Notes is free software under the **GNU General Public License v3**, the same licence as
Notational Velocity. The full text is in [COPYING.txt](COPYING.txt).

- **Notational Velocity** is copyright © 2009–2011 Zachary Schneirov. Kinetic Notes exists only
  because of that work.
- Third-party components retained from the original are credited in
  [Acknowledgments.txt](Acknowledgments.txt), including PTHotKeys (Quentin D. Carnicelli),
  RBSplitView, and ODBEditor.
- The original Notational Velocity application icon by Taylor Carrigan is **not** used here and
  is not part of this repository; its licence does not permit commercial use. Kinetic Notes ships
  its own icon.

### Translations

Kinetic Notes ships the interface translations contributed to Notational Velocity, and is grateful
to the people who wrote them:

| Language | Translator |
|---|---|
| Spanish | Iago Ramos, OpenAI |
| French | David Bosman |
| Portuguese | Daniel R. Souza |
| German | Benedikt Hopmann |
| Chinese (Simplified) | Tunghsiao Liu |
| Italian | Paolo Tramannoni |
