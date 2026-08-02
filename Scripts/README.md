# Release scripts

## `release.sh`

Builds Deployment, verifies the product, signs it with Developer ID, notarizes it, staples the
ticket, zips the result, checks the zip the way a user's Mac would, and prints the `<item>` block to
paste into `docs/appcast.xml`.

```bash
Scripts/release.sh
```

It refuses to start unless the certificate, the notary profile and Sparkle's `sign_update` are all
present, so a missing prerequisite costs a second rather than a failed notarization round trip.

**It holds no credentials and prints none.** `notarytool` reads its password from a keychain
profile; `sign_update` reads the EdDSA private key from the login keychain. The script only names
them.

Settings, all overridable from the environment:

| | default |
|---|---|
| `KN_SIGN_IDENTITY` | `Developer ID Application` |
| `KN_TEAM_ID` | `4QF262Q666` |
| `KN_NOTARY_PROFILE` | `kn-notarytool` |
| `KN_SPARKLE_TOOLS` | `Tools/Sparkle/bin`, falling back to `PATH` |

It deliberately does **not** create the GitHub Release and does **not** edit the appcast. Publishing
is a decision, not a build step.

---

## One-time setup

### 1. Developer ID certificate

Developer portal → Certificates → **+** → **Developer ID Application**, with a CSR generated from
Keychain Access (*Certificate Assistant → Request a Certificate From a Certificate Authority*, saved
to disk). Or, more simply: Xcode → Settings → Accounts → *Manage Certificates…* → **+** → **Developer
ID Application**.

Do not open `Notation.xcodeproj` in Xcode while you are in there — see the hazard note in
`CLAUDE.md`.

Correct when:

```bash
security find-identity -v -p codesigning
```

lists `Developer ID Application: … (4QF262Q666)`.

### 2. Notary credentials

```bash
xcrun notarytool store-credentials "kn-notarytool" --apple-id "<apple id>" --team-id 4QF262Q666
```

It prompts for an app-specific password from appleid.apple.com. An App Store Connect API key
(`--key` / `--key-id` / `--issuer`) works too and does not expire with the Apple ID password.

### 3. Sparkle's tools

Unpack the release tarball from <https://github.com/sparkle-project/Sparkle/releases> and put its
`bin/` at `Tools/Sparkle/bin` (gitignored — these are build tools, not a dependency; the framework
itself is vendored at `Frameworks/Sparkle.framework`).

`generate_keys` creates the EdDSA keypair, storing the private key in the login keychain and
printing the public key, which belongs in `SUPublicEDKey` in `Info.plist`. That is already done for
this project; `./bin/generate_keys -p` prints the existing public key without replacing the pair.

> **Back the private key up before shipping anything.** `./bin/generate_keys -x` exports it. Store
> it offline, in two places. Losing it means no future update is installable by anyone, ever, and
> every user has to reinstall by hand. It is the one unrecoverable failure in this process.
>
> The Developer ID private key deserves the same treatment — export the certificate *and* its key
> from Keychain Access as a password-protected `.p12`. It cannot be re-downloaded, and Apple caps
> the account at five active Developer ID Application certificates.

### 4. GitHub Pages

Repository **Settings → Pages → Deploy from a branch → `main` / `/docs`**, then set the custom
domain to `updates.kineticnotes.org` and enable *Enforce HTTPS*. The DNS `CNAME` for that name
points at `jptechco.github.io`.

`release.sh` fetches `SUFeedURL` before it signs anything, so a feed that is not serving fails the
release instead of shipping a binary that silently never updates.

---

## Cutting a release

1. Land the release PR: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` set at **three sites each**
   in `project.pbxproj`, `CHANGELOG.md`'s *Unreleased* promoted, `README.md`'s status line updated,
   and `docs/release-notes/<version>.html` written.
2. Tag it: `git tag v1.6 && git push origin v1.6`
3. `Scripts/release.sh`
4. `gh release create v1.6 build/dist/Kinetic-Notes-1.6.zip --title "Kinetic Notes 1.6"`
5. Open a PR adding the printed `<item>` to `docs/appcast.xml`. Its `length` and `edSignature`
   cannot exist until the notarized zip does, which is why this is a separate step.

`sparkle:version` in that item is `CFBundleVersion` — the **build number**, not the marketing
version. Sparkle compares it against the installed build number, and this project's build numbers
are pull request numbers, which are monotonic.

Once there are several releases, Sparkle's `bin/generate_appcast` can regenerate the whole feed from
a directory of past zips and produce binary deltas as well. For one or two entries, by hand is
clearer.
