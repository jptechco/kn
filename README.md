# Kinetic Notes

A modern fork of Notational Velocity — the fast, keyboard-driven
note-taking app for macOS that does searching and creating in a single field.

[Notational Velocity's last release](https://notational.net/) was in 2011. That build ships `ppc`, `i386` and `x86_64` code
and has no Apple Silicon slice, so on modern Macs it runs only under Rosetta 2 — and Rosetta 2 is
being withdrawn after macOS 26 Tahoe. Kinetic Notes is that application rebuilt to run natively,
with its dead and Intel-only dependencies replaced, and nothing removed that anyone was using.

### Status
**Version: 1.7 — current stable release.**

1.7 adds an Updates pane to Preferences, refreshes Dark Mode with a Color Scheme override, and fixes
a bug where deleting a note you had searched for blanked the list. Like 1.6 it is signed with an
Apple Developer ID and notarized, so it opens normally on first launch and updates itself.

### Changelog
If you're curious, check out the [changelog](CHANGELOG.md) to see what's changed in each version.

---

## System requirements

| | |
|---|---|
| **macOS** | 13.0 Ventura or later |
| **Architectures** | Universal — `arm64` (Apple Silicon) and `x86_64` (Intel), both native |
| **Runtime dependencies** | [Sparkle](https://sparkle-project.org) 2.9.5 (MIT), bundled, for updates. Otherwise only system frameworks; no Homebrew |
| **To build** | Xcode 15 or later |

Rosetta 2 is not required or used.

---

## Installing

Download the latest release and drag **Kinetic Notes.app** to your Applications folder. That is the
whole procedure — releases are signed with an Apple Developer ID and notarized by Apple, so the
first launch is not blocked and no right-click → *Open* workaround is needed.

---

## Updates

Kinetic Notes checks for a new version once a day and can install one itself. You can also ask at
any time, with **Kinetic Notes → Check for Updates…**

**A scheduled check does not interrupt you.** When a new version turns up on its own, an
*Update Available* button appears in the toolbar and waits there. Click it when you are ready — it
opens the release notes and an Install button, and the update can be skipped or postponed from
there. Asking for a check yourself still answers straight away, since at that point you are waiting
for an answer.

Every download is verified against a signing key built into the application before it is unpacked; a
download that fails that check is discarded rather than installed. Nothing is measured — no profile
of your system is sent, and no record is kept of who was offered what. The update feed lives at
[updates.kineticnotes.org](https://updates.kineticnotes.org/appcast.xml).

> **Updating from 1.5 or earlier is a manual step, once.** Those versions contain no updater at all,
> so nothing in the update feed can reach them. 1.6 is the first version able to *receive* an
> update; it cannot be delivered as one. Download it by hand and updates take care of themselves
> afterwards.

---

## Support development

Kinetic Notes is maintained by a volunteer, and donations help fund ongoing development.

If this app has been useful to you, please consider **[making a
donation](https://www.kineticnotes.com/donate)**. Donations are completely optional and help keep
the project alive — the app is free, GPL v3, and always will be.

Thank you for supporting the project. The same link lives in the app, under
**Help → Support Development**.

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

Only `/usr/lib` entries and `@rpath/Sparkle.framework/…` should remain — Sparkle is bundled inside
the application, at `Contents/Frameworks`.

A build made this way is ad-hoc signed and is not hardened, which is deliberate: hardened runtime
enforces library validation, and two ad-hoc signatures do not count as the same team, so a hardened
ad-hoc build cannot load its own copy of Sparkle. Hardening is applied when a release is signed with
a real Developer ID instead. See [Scripts/README.md](Scripts/README.md) for how releases are built.

### A note for contributors

The interface files are compiled Interface Builder 3 nibs. **Do not let Xcode re-save
`MainMenu.nib`** — a modern Interface Builder will upgrade the format and may switch `NSTextView`
to TextKit 2, which the editor (`LinkingEditor.m`, `MultiplePageView.m`) does not use. Four nibs
(`ExporterManager`, `FindPanel`, `ImporterAccessory`, `SavedSearches`) contain only compiled
output and cannot be edited at all.

---

## License and credit

Kinetic Notes' **source code** is free software under the **GNU General Public License v3**, the
same licence as Notational Velocity. The full text is in [COPYING.txt](COPYING.txt).

**The application icon is not covered by that licence.** `Images/kinetic.icns` and
`Images/kinetic.iconset` are © 2026 jptechco, all rights reserved. The code may be forked freely;
a fork must ship its own icon.

- **Notational Velocity** was created by Zachary Schneirov. Kinetic Notes exists only
  because of his work.
- Third-party components retained from the original are credited in
  [Acknowledgments.txt](Acknowledgments.txt), including PTHotKeys (Quentin D. Carnicelli),
  RBSplitView, and ODBEditor.
- The original Notational Velocity application icon by Taylor Carrigan is not used and is not
  part of this repository; its licence did not permit commercial use.

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
