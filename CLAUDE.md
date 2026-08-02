# Working in this repository

Kinetic Notes is a fork of Notational Velocity. Pull requests target **this fork's `main`**
(`jptechco/kn`), never upstream `scrod/nv`.

## Versioning

Two separate numbers, both visible in the application:

**Release** — `major.minor`, no trailing zero: 1.0, 1.1, 1.5, 1.6.

- A minor release steps by `0.1` and covers a shipped body of work.
- A major release is `x.0` and happens **only when John calls one**. Never promote to a new major
  on your own judgement.
- A release still in testing carries a ` beta` suffix in its version string — `1.5 beta`.
- If the 1.x line ever reaches 1.9 without a major being declared, ask: that is the point to either
  call 2.0 or accept 1.10.

**Build** — one per merged pull request, numbered with **the pull request's own number**. PR #20 is
build 20. This makes any build traceable to the change that produced it and is monotonic for free.

The About box shows both, as `Version 1.5 beta (20)`.

### On every merged pull request

1. Add an entry under `## Unreleased` in `CHANGELOG.md`: the build number, a one-line summary, and
   a link to the PR.
2. Set `CURRENT_PROJECT_VERSION` to the PR number — **three sites** in
   `Notation.xcodeproj/project.pbxproj`, one per build configuration.

**Exception: a pull request that changes nothing inside the application bundle does not bump the
build number,** and needs no changelog entry. That covers `Scripts/`, `docs/`, `README.md`,
`CLAUDE.md` and the appcast. The build number exists to identify a *build*; moving it when the build
is byte-for-byte identical breaks that, and would leave `main` claiming a build number no shipped
binary ever carried. Anything under the app bundle — sources, nibs, `Info.plist`, strings tables,
`Acknowledgments.txt`, the vendored framework — bumps it as usual.

### When a release is cut

1. Promote `## Unreleased` in `CHANGELOG.md` to `## <version> — <YYYY-MM-DD>`.
2. Set `MARKETING_VERSION` to the new version (**three sites**, same file). Include the ` beta`
   suffix if it is a development release.
3. Update the README status line: it declares the current version, and when that version is a beta
   it also names the current stable release.

### The About box needs no nib work

*About Kinetic Notes* is the **standard AppKit panel** — `orderFrontStandardAboutPanel:`, wired in
`MainMenu.nib`. It renders `CFBundleShortVersionString` and, in parentheses, `CFBundleVersion`, both
of which come from the build settings above. Changing the displayed version therefore never requires
touching a nib. No code reads `CFBundleShortVersionString`, so a non-numeric value such as
`1.5 beta` is safe.

`+[NotationPrefs appVersion]` calls `intValue` on `CFBundleVersion`. It has no callers, and an
integer build number keeps it valid regardless.

## Licensing

The **source code** is GPL v3. The **application icon** (`Images/kinetic.icns`,
`Images/kinetic.iconset`) is © jptechco, all rights reserved, and is deliberately *outside* that
grant. Do not "tidy" that distinction away by assuming the whole tree is GPL — it is stated in both
`README.md` and `Acknowledgments.txt` and must stay stated in both.

`Acknowledgments.txt` must describe what actually ships. When a component is added or removed, check
it against the Sources phase in `Notation.xcodeproj/project.pbxproj` — **not** against keyword
matches in comments. Sparkle and OpenSSL are both still named in explanatory comments long after
they stopped being linked, and a keyword search reports them as present.

## Hazards

**Never `pkill` the application.** SIGTERM zeroes the notes database. Quit it with:

```bash
osascript -e 'tell application "Kinetic Notes" to quit'
```

**Never re-save `MainMenu.nib`.** The interface files are compiled Interface Builder 3 nibs; a
modern Interface Builder upgrades the format and may switch `NSTextView` to TextKit 2, which the
editor (`LinkingEditor.m`, `MultiplePageView.m`) does not use.

**Never pipe `xcodebuild` into `grep`.** The pipe's exit code is grep's, which masks build failures.
Redirect to a log file and search that:

```bash
xcodebuild -project Notation.xcodeproj -target Notation -configuration Deployment build > build.log 2>&1
```

Then confirm `** BUILD SUCCEEDED **` is present, and match errors on `^[^ ]+:[0-9]+:[0-9]+: error:` —
a bare `error:` also matches deprecation text such as `…forKey:error:`.

The product lands at `build/Deployment/Kinetic Notes.app`. It must stay universal
(`lipo -info` reports `x86_64 arm64`) with no libraries outside `/System/Library` and `/usr/lib`.

## Testing against real data

Round-trip changes against a **copy** of a real database, never the original. The load-bearing
assertion is that the source directory is byte-identical before and after, including on failure and
cancellation paths.

Reusable harnesses live in `~/.claude/plans/kn-harnesses/` with a README. They relink the built
object files minus `main.o` against a small test main, so they exercise the real classes headlessly.
GUI automation is blocked on this Mac — John supplies screenshots for anything visual.
