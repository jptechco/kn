# Kinetic Notes

A modern fork of Notational Velocity — the fast, keyboard-driven
note-taking app for macOS that does searching and creating in a single field.

[Notational Velocity's last release](https://notational.net/) was in 2011. That build ships `ppc`, `i386` and `x86_64` code
and has no Apple Silicon slice, so on modern Macs it runs only under Rosetta 2 — and Rosetta 2 is
being withdrawn after macOS 26 Tahoe. Kinetic Notes is that application rebuilt to run natively,
with its dead and Intel-only dependencies replaced, and nothing removed that anyone was using.

### Status
**Version: 1.5 beta — feature complete, in testing.**
The current stable release is **1.1**.

1.5 replaces the application's Carbon-era internals; the storage formats are unchanged and verified
compatible in both directions, but the file-handling code underneath them is new, so it is going out
as a beta first.

### Changelog
If you're curious, check out the [changelog](CHANGELOG.md) to see what's changed in each version.

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

> On a genuine first launch, Kinetic Notes offers to import an existing Notational Velocity notes
> directory, encrypted ones included. It *copies*, never moves, and does not write to Notational
> Velocity's data at any point.

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

- **Notational Velocity** was created by Zachary Schneirov. Kinetic Notes exists only
  because of his work.
- Third-party components retained from the original are credited in
  [Acknowledgments.txt](Acknowledgments.txt), including PTHotKeys (Quentin D. Carnicelli),
  RBSplitView, and ODBEditor.
- The original Notational Velocity application icon by Taylor Carrigan is **not** used here and
  is not part of this repository; its licence did not permit commercial use. Kinetic Notes ships
  its own icon, also copyrighted by jptechco.

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

**Interested in adding another translation?**  Post the details in [issues](https://github.com/jptechco/kn/issues)
