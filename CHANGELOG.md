# Changelog

Every notable change to Kinetic Notes. The newest work is at the top.

## Versioning

**Releases** are `major.minor` — 1.0, 1.1, 1.5, 1.6. A minor release steps by 0.1 and covers a
shipped body of work; a major release is `x.0` and happens only when the maintainer calls one. A
release still in testing carries a `beta` suffix, and the README names the current stable release
alongside it.

**Builds** are per pull request, numbered with the pull request's own number — so build 22 is
PR #22, and any build traces straight back to the change that produced it. The application reports
both: *Kinetic Notes → About Kinetic Notes* reads `Version 1.5 (22)`.

Entries merged since the last release are collected under **Unreleased** and are promoted to a
version heading when that release is cut.

## Unreleased

- **The title bar is stacked again, the way Notational Velocity had it** — the window's title on its
  own row, the search field on a full-width row beneath it.

  This was never a design decision anyone made: it is what the window has always asked for. macOS 11
  redefined how toolbars are drawn, defaulting every window to a single row and folding the title and
  the search field together side by side. Kinetic Notes now asks for the older arrangement
  explicitly.

  The side-by-side layout is still available: *Settings → General → **Show the search field beside
  the window title***. The switch takes effect immediately, with no relaunch.
  ([#25](https://github.com/jptechco/kn/pull/25))
- **Hiding and re-showing the toolbar no longer renames the window "Notation".** The window title is
  restored from the application's own name. The bug was invisible while the title sat beside the
  search field, and obvious once it has a row to itself.
  ([#25](https://github.com/jptechco/kn/pull/25))
- **Kinetic Notes updates itself.** *Check for Updates…* works again, and the application looks for
  a new version once a day on its own. Every download is verified against a signing key built into
  the application before it is unpacked, and a download that fails that check is discarded rather
  than installed.

  **A scheduled check does not interrupt you.** Notational Velocity's updater — and Sparkle's own
  default — put a window on screen the moment it found something, which in practice meant seconds
  after launch, when you had opened the application to do something else. Instead, an *Update
  Available* button appears in the toolbar and waits; clicking it opens the usual release notes and
  Install dialog, where the update can also be skipped or deferred. Choosing *Check for Updates…*
  yourself still answers immediately, because at that point you are waiting for an answer. Hiding
  the toolbar hides the button along with it; the menu item is unaffected.

  Nothing is measured. No profile of the system is sent, and no record is kept of who was offered
  what. The only network request is for the update feed itself.

  Notational Velocity bundled Sparkle 1.5b6 (2008), which was built for ppc/i386/x86_64 and so could
  never load on Apple Silicon; it was removed in the rebrand, and the menu item has been hidden ever
  since. This is Sparkle 2.9.5, bundled as the application's only non-system framework.

  **Anyone running 1.5 or earlier must update to 1.6 by hand.** Those versions contain no updater at
  all, so nothing in the update feed can reach them. 1.6 is the first version able to receive an
  update; it cannot be delivered as one.
  ([#24](https://github.com/jptechco/kn/pull/24))
- **The *Check for Updates…* menu item is translated into every language the application ships.** It
  had been left in English in the Spanish interface — invisible until now, because the item itself
  was hidden.
  ([#24](https://github.com/jptechco/kn/pull/24))
- **The application can be supported by donation.** *Help → Support Development* explains that
  Kinetic Notes is maintained by a volunteer, that donations are optional, and opens the project's
  donation page in a browser. It is the only network activity the item performs: nothing is measured, and no
  record is kept of who was asked or what they chose. The README carries the same invitation, and the
  repository has a Sponsor button. The item and its dialog are localized into all seven languages
  the application ships.
  ([#23](https://github.com/jptechco/kn/pull/23))
- **The Help menu's *Kinetic Notes Web Site* item opens the product site,** kineticnotes.org, rather
  than the source repository — which is what *Development Web Site*, beneath it, is for.
  ([#23](https://github.com/jptechco/kn/pull/23))

## 1.5 — 2026-07-27

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
- **The note list's column headers are opaque again.** macOS 11 stopped drawing a background behind
  them and nothing in the application drew one instead, so once the list was long enough to scroll,
  note titles showed straight through the headings. The list's grid lines now follow the system
  appearance too, instead of being fixed at a near-white grey that was wrong on a dark background.
  ([#22](https://github.com/jptechco/kn/pull/22))

*Housekeeping*
- Deleted the `IsLeopardOrLater` / `IsSnowLeopardOrLater` runtime checks. At a macOS 13 floor both
  were unconditionally true, so ~30 sites across 13 files were guarding dead pre-2009 branches.
- **The application icon is reserved outside the GPL.** `Images/kinetic.icns` is © jptechco, all
  rights reserved; the source code remains GPL v3. Notational Velocity's own icon is no longer
  shipped, and `Acknowledgments.txt` now describes what the application actually contains.
  ([#21](https://github.com/jptechco/kn/pull/21))
- **This changelog was split out of the README,** and the versioning scheme above was settled. The
  application reports its version and build in the About box.
  ([#20](https://github.com/jptechco/kn/pull/20))

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

