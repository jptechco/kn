# Changelog

Every notable change to Kinetic Notes. The newest work is at the top.

## Versioning

**Releases** are `major.minor` — 1.0, 1.1, 1.5, 1.6. A minor release steps by 0.1 and covers a
shipped body of work; a major release is `x.0` and happens only when the maintainer calls one. A
release still in testing carries a `beta` suffix, and the README names the current stable release
alongside it.

**Builds** are per pull request, numbered with the pull request's own number — so build 20 is
PR #20, and any build traces straight back to the change that produced it. The application reports
both: *Kinetic Notes → About Kinetic Notes* reads `Version 1.5 beta (20)`.

Entries merged since the last release are collected under **Unreleased** and are promoted to a
version heading when that release is cut.

## Unreleased

- **build 20** — Split this changelog out of the README and settle the versioning scheme above;
  the application now reports its development version and build in the About box.
  ([#20](https://github.com/jptechco/kn/pull/20))

## 1.5 beta — 2026-07-25

**The Carbon File Manager is gone from the way notes are stored.** Notational Velocity read and
wrote every note through it — an API Apple deprecated in 2012. 1.5 replaces it, along with the
other Mac OS X-era interfaces the application still depended on.

Two Carbon calls are kept on purpose, both measured rather than assumed: resolving the Alias
Manager record that Notational Velocity writes for its notes folder, and reading a volume's
creation date, which is used to identify a disk and which no modern API reports the same way on
APFS. Changing either would break something real — the first-run import in one case, and, in the
other, every note in an existing database appearing to have been edited elsewhere.

This release changes no file formats. Databases, note files, preferences and Keychain entries stay
compatible with 1.1 in **both** directions, which was the constraint every change below was built
and tested against.

*Files and storage*
- **Note files are addressed by path.** Every note was previously tracked by an `FSRef`, an opaque
  handle the File Manager resolved. Reading a note's metadata now takes a single `getattrlist(2)`
  call, closing a window in which a note edited in an external editor at exactly the wrong moment
  could be misread.
- **Saving is atomic in one step.** A note is written to a scratch file and renamed into place;
  the rename replaces the old file and removes the scratch file together, so an interrupted save
  can no longer leave anything behind. Notational Velocity's exchange-then-delete could, and did —
  it accumulated hundreds of stray files over the years. Any that already exist are swept at
  launch.
- **Directory scanning uses `getattrlistbulk(2)`,** which reads a whole notes folder in one or two
  calls. Filenames that fail to decode are no longer dropped from the catalog.
- **The notes folder location is recorded as an `NSURL` bookmark.** The Alias Manager record a
  previous version wrote is still read, and is converted the first time 1.5 opens the database.
  Notational Velocity's own record is read exactly as before, so the first-run import assistant is
  unaffected — and it has to be, because Notational Velocity will never write anything else.
- Moving to the Trash, revealing in the Finder, folder icons and application icons all go through
  current APIs.

*Data and security*
- **Archiving moved to `NSSecureCoding`.** Every archive written is byte-identical to what 1.1
  wrote; reading the real notes database and re-freezing it reproduces the original file exactly.
- **Keychain access moved to `SecItem`.** Existing passphrases keep working: the items stay in the
  same login keychain the previous calls used, so no one is asked for a passphrase again.

*Interface*
- **Every alert rebuilt on `NSAlert`** — 38 call sites across 15 files — with identical wording and
  button order. This also removed a latent crash: several inherited call sites passed
  already-formatted text through a second `printf` pass.
- Deprecated drawing and window APIs retired outside `RBSplitView`, which is left alone
  deliberately.
- **Typographic quotes restored.** Fourteen alerts and undo names read `quotemark%@quotemark`
  where curly quotes belong — upstream damage from a find/replace in Notational Velocity's own
  history, fixed in the sources and in all seven localizations.
- **The welcome notes are rebranded in every language.** 1.1 had done this for English only; the
  other six locales still carried Notational Velocity branding, dead links and translators'
  personal email addresses. Translator credits are kept; no translation was invented.

*Housekeeping*
- Deleted the `IsLeopardOrLater` / `IsSnowLeopardOrLater` runtime checks. At a macOS 13 floor both
  were unconditionally true, so ~30 sites across 13 files were guarding dead pre-2009 branches.

## 1.1 — 2026-07-24

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
  is credited for the first time. See [Translations](README.md#translations).

*Housekeeping*
- Removed 100+ orphaned localization files: `.strings` overlays superseded years ago by fully
  translated nibs, and the nibs of `TagEditingManager`, a feature that no longer exists.

## 1.0 — 2026-07-24

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
  Notational Velocity is never written to (see [above](README.md#coming-from-notational-velocity)).
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

## Upstream

Kinetic Notes forks Notational Velocity 2.0 β7. For history before this fork, see
[scrod/nv](https://github.com/scrod/nv).

