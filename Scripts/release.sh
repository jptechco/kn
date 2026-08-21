#!/bin/bash
#
# release.sh -- build, sign, notarize and staple a Kinetic Notes release, then print the appcast
# entry for it. See Scripts/README.md for the one-time setup this depends on.
#
# No credential is stored here, passed here, or printed here. notarytool reads its password from a
# keychain profile; sign_update reads the EdDSA private key from the login keychain. This script
# only ever names them.
#
# Copyright (c) 2026, the Kinetic Notes authors. Part of Kinetic Notes, GPL v3; see COPYING.txt.

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Overridable from the environment; the defaults are what this project uses.
KN_SIGN_IDENTITY="${KN_SIGN_IDENTITY:-Developer ID Application}"
KN_TEAM_ID="${KN_TEAM_ID:-4QF262Q666}"
KN_NOTARY_PROFILE="${KN_NOTARY_PROFILE:-kn-notarytool}"
# The branch a release is built from. Overridable, but see the git checks below before you do.
KN_RELEASE_BRANCH="${KN_RELEASE_BRANCH:-main}"
# Sparkle's bin/ from the release tarball. Not committed -- it is a build tool, not a dependency.
KN_SPARKLE_TOOLS="${KN_SPARKLE_TOOLS:-$REPO/Tools/Sparkle/bin}"

readonly APP="$REPO/build/Deployment/Kinetic Notes.app"
readonly DIST="$REPO/build/dist"
readonly LOG="$REPO/build/release-build.log"

die()  { printf '\n\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m  %s\n' "$*"; }
warn() { printf '    \033[33mwarn\033[0m %s\n' "$*"; }

sparkle_tool() {
	local name="$1"
	if   [ -x "$KN_SPARKLE_TOOLS/$name" ]; then printf '%s' "$KN_SPARKLE_TOOLS/$name"
	elif command -v "$name" >/dev/null 2>&1; then command -v "$name"
	else return 1
	fi
}

# ---------------------------------------------------------------- preflight

step "Preflight"

# The build takes whatever happens to be checked out, and nothing downstream looks at git again: the
# version and the build number are read back out of Info.plist, the tag is applied by hand, and
# notarization will happily sign a working copy full of uncommitted edits. So a release built from a
# branch -- or from a main that has not pulled the release PR yet -- comes out labelled with the
# *previous* release's numbers, and that is worse than an outright failure: a build number Sparkle
# has already seen is one it will never offer to anybody. The cost of finding this out downstream is
# a whole notarization round trip, so find out here instead.
#
# KN_SKIP_GIT_CHECKS=1 to build from somewhere else on purpose.
if [ -n "${KN_SKIP_GIT_CHECKS:-}" ]; then
	warn "git checks skipped (KN_SKIP_GIT_CHECKS is set) -- the artifact may not match any commit"
elif ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
	die "$REPO is not a git checkout. Set KN_SKIP_GIT_CHECKS=1 to build anyway."
else
	BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD || true)"
	[ "$BRANCH" = "$KN_RELEASE_BRANCH" ] || die \
		"on ${BRANCH:-a detached HEAD}, not $KN_RELEASE_BRANCH. A release builds from the merged release branch, so that the tag names a commit that outlives the pull request. See 'Cutting a release' in Scripts/README.md."

	DIRTY="$(git -C "$REPO" status --porcelain)"
	if [ -n "$DIRTY" ]; then
		printf '%s\n' "$DIRTY" >&2
		die "the working tree is not clean -- the artifact would not match any commit. Commit, stash or remove the above."
	fi

	# The one this is really here for: the release PR is merged on the remote but not pulled, so the
	# version bump is missing and the build silently carries the last release's numbers.
	git -C "$REPO" fetch --quiet origin "$KN_RELEASE_BRANCH" 2>/dev/null \
		|| warn "could not reach origin; comparing against a possibly stale origin/$KN_RELEASE_BRANCH"
	if git -C "$REPO" rev-parse --quiet --verify "origin/$KN_RELEASE_BRANCH" >/dev/null; then
		BEHIND="$(git -C "$REPO" rev-list --count "HEAD..origin/$KN_RELEASE_BRANCH")"
		AHEAD="$(git -C "$REPO" rev-list --count "origin/$KN_RELEASE_BRANCH..HEAD")"
		[ "$BEHIND" = 0 ] || die \
			"$KN_RELEASE_BRANCH is $BEHIND commit(s) behind origin -- pull before releasing, or the build carries the previous release's version."
		[ "$AHEAD" = 0 ] || die \
			"$KN_RELEASE_BRANCH is $AHEAD commit(s) ahead of origin -- the release would ship code that has not been pushed."
	fi
	ok "clean $KN_RELEASE_BRANCH, in sync with origin"
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
case "$IDENTITIES" in
	*"$KN_SIGN_IDENTITY"*) ;;
	*) die "no '$KN_SIGN_IDENTITY' certificate in the keychain. See Scripts/README.md." ;;
esac
ok "signing identity present"

xcrun notarytool history --keychain-profile "$KN_NOTARY_PROFILE" >/dev/null 2>&1 \
	|| die "no notarytool keychain profile '$KN_NOTARY_PROFILE'. See Scripts/README.md."
ok "notary profile '$KN_NOTARY_PROFILE'"

SIGN_UPDATE="$(sparkle_tool sign_update)" \
	|| die "sign_update not found. Unpack Sparkle's release tarball to $KN_SPARKLE_TOOLS, or set KN_SPARKLE_TOOLS."
ok "sign_update"

[ -x /usr/bin/python3 ] || die "/usr/bin/python3 is missing; the filename normalization step needs it."
ok "python3"

# ---------------------------------------------------------------- build

step "Building Deployment"

# never pipe xcodebuild into grep: the pipe's exit status is grep's, which hides a failed build
rm -rf "$APP"
xcodebuild -project "$REPO/Notation.xcodeproj" -target Notation -configuration Deployment build \
	> "$LOG" 2>&1 || { tail -40 "$LOG"; die "xcodebuild failed; full log in $LOG"; }

grep -q '\*\* BUILD SUCCEEDED \*\*' "$LOG" || die "no BUILD SUCCEEDED in $LOG"
# a bare 'error:' also matches deprecation text such as ...forKey:error:
if grep -qE '^[^ ]+:[0-9]+:[0-9]+: error:' "$LOG"; then
	grep -E '^[^ ]+:[0-9]+:[0-9]+: error:' "$LOG" | head -20
	die "compile errors in $LOG"
fi
[ -d "$APP" ] || die "no product at $APP"
ok "built"

MARKETING_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
FEED_URL="$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist")"
ok "version $MARKETING_VERSION ($BUILD_NUMBER)"

readonly ZIP_NAME="Kinetic-Notes-${MARKETING_VERSION// /-}.zip"

# ---------------------------------------------------------------- verify the product

step "Verifying the product"

readonly FW="$APP/Contents/Frameworks/Sparkle.framework"
[ -d "$FW" ] || die "Sparkle.framework is not in Contents/Frameworks -- the CopyFiles phase did not run"
ok "Sparkle.framework embedded"

# every Mach-O that ships must carry both slices, not just the main binary
check_universal() {
	local f="$1" info
	info="$(lipo -info "$f" 2>&1 || true)"
	case "$info" in
		*x86_64*arm64*|*arm64*x86_64*) ;;
		*) die "not universal: $f ($info)" ;;
	esac
}
check_universal "$APP/Contents/MacOS/Kinetic Notes"
check_universal "$FW/Versions/B/Sparkle"
[ -f "$FW/Versions/B/Autoupdate" ] && check_universal "$FW/Versions/B/Autoupdate"
for x in "$FW"/Versions/B/XPCServices/*.xpc "$FW"/Versions/B/*.app; do
	[ -e "$x" ] || continue
	exe="$x/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$x/Contents/Info.plist")"
	[ -f "$exe" ] && check_universal "$exe"
done
ok "universal (x86_64 arm64)"

# nothing outside the system may be linked, except Sparkle by rpath.
# Only the tab-indented lines are dependencies: otool -L prints an unindented header per
# architecture, and this is a universal binary, so there is one for each slice.
foreign_libs() {
	otool -L "$1" | grep '^[[:space:]]' \
		| grep -vE '/System/Library/|/usr/lib/|@rpath/Sparkle\.framework/' || true
}
if [ -n "$(foreign_libs "$APP/Contents/MacOS/Kinetic Notes")" ]; then
	foreign_libs "$APP/Contents/MacOS/Kinetic Notes"
	die "links something outside /System/Library and /usr/lib"
fi
ok "no non-system libraries"

# a typo'd feed is frozen into every shipped binary and silently never updates anyone
case "$FEED_URL" in
	https://*) ;;
	*) die "SUFeedURL is not https: $FEED_URL" ;;
esac
curl -sfI --max-time 20 "$FEED_URL" >/dev/null \
	|| die "SUFeedURL does not resolve: $FEED_URL (is GitHub Pages enabled and the DNS live?)"
ok "feed reachable: $FEED_URL"

# Both release-notes files must already exist, and this is the earliest point that can be checked --
# MARKETING_VERSION is not known until the build has run. Failing here costs nothing; failing after
# notarization costs a whole round trip. The .html is what the appcast's releaseNotesLink points at,
# and nothing downstream would notice it pointing at a 404. The .md is the GitHub release body.
for ext in html md; do
	[ -f "$REPO/docs/release-notes/$MARKETING_VERSION.$ext" ] \
		|| die "docs/release-notes/$MARKETING_VERSION.$ext is missing -- write the release notes first."
done
ok "release notes present (.html for Sparkle, .md for the GitHub release)"

# ---------------------------------------------------------------- normalize filenames

step "Normalizing resource filenames"

# Nine shipped .nvhelp names are non-ASCII, and they must be NFD *before* codesign seals them.
#
# CodeResources seals the byte form of each name. ditto and unzip reproduce it faithfully, but
# Archive Utility -- what a user gets by double-clicking the download in Finder -- rewrites names
# to NFD, because macOS ditto/zip cannot set the zip UTF-8 language-encoding flag (bit 11) and the
# system Info-ZIP has no UNICODE_SUPPORT, so -UN=UTF8 is rejected. An NFC name therefore arrives
# decomposed, no longer matches the seal, and Gatekeeper reports "a sealed resource is missing or
# invalid". NFD survives that rewrite unchanged, so sealing NFD is stable under every extractor.
# (jptechco/kn#34: es.lproj was NFC and broke; it/fr/pt were already NFD and did not.)
#
# This runs on the build product, not the source tree: git's core.precomposeunicode rewrites NFD
# to NFC on the way in, so the sources cannot hold the decomposed form.
RENAMED="$(/usr/bin/python3 - "$APP" <<'NORMALIZE'
import os, sys, unicodedata
root = sys.argv[1]; n = 0
for dirpath, dirnames, filenames in os.walk(root, topdown=False):
    for name in dirnames + filenames:
        nfd = unicodedata.normalize('NFD', name)
        if nfd == name:
            continue
        # two hops: APFS is normalization-insensitive, so NFC -> NFD in one rename is a no-op
        tmp = os.path.join(dirpath, '.nfd-tmp-%d' % n)
        os.rename(os.path.join(dirpath, name), tmp)
        os.rename(tmp, os.path.join(dirpath, nfd))
        n += 1
print(n)
NORMALIZE
)" || die "filename normalization failed"
ok "$RENAMED name(s) decomposed"

# ---------------------------------------------------------------- sign

step "Signing"

# strictly inside out. Not --deep: it is deprecated, and it would apply the app's entitlements to
# nested code. No --entitlements on nested items, which also clears any stray get-task-allow that
# would fail notarization.
sign() { codesign --force --timestamp --options runtime --sign "$KN_SIGN_IDENTITY" "$@"; }

for x in "$FW"/Versions/B/XPCServices/*.xpc; do [ -e "$x" ] && sign "$x"; done
for a in "$FW"/Versions/B/*.app;             do [ -e "$a" ] && sign "$a"; done
[ -f "$FW/Versions/B/Autoupdate" ]        && sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B"
sign --entitlements "$REPO/KineticNotes.entitlements" "$APP"
ok "signed inside out"

step "Verifying the signature"

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2

# Read the signature ONCE and assert against that text. Asking codesign again for each assertion
# means re-reading a bundle that was written moments ago, and it has been seen to answer
# inconsistently between two calls a few milliseconds apart -- which failed this step on a build
# whose signature was in fact correct. One read cannot disagree with itself.
SIGINFO="$(codesign -dvv "$APP" 2>&1 || true)"

case "$SIGINFO" in
	*"TeamIdentifier=$KN_TEAM_ID"*) ;;
	*) printf '%s\n' "$SIGINFO" >&2; die "signed with the wrong team (expected $KN_TEAM_ID)" ;;
esac
case "$SIGINFO" in
	*runtime*) ;;
	*) printf '%s\n' "$SIGINFO" >&2; die "hardened runtime flag not set -- notarization will be rejected" ;;
esac
ok "Developer ID $KN_TEAM_ID, hardened runtime"

ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
case "$ENT" in
	*com.apple.security.automation.apple-events*) ;;
	*) printf '%s\n' "$ENT" >&2; die "apple-events entitlement missing -- the external editor would break silently" ;;
esac
case "$ENT" in
	*get-task-allow*) printf '%s\n' "$ENT" >&2; die "get-task-allow is present -- notarization will be rejected" ;;
esac
ok "entitlements correct"

# ---------------------------------------------------------------- notarize

step "Notarizing"

mkdir -p "$DIST"
rm -f "$DIST/notarize.zip" "$DIST/$ZIP_NAME"

# ditto, not zip: it preserves the symlinks and the _CodeSignature seals.
# --sequesterRsrc: every file in the build product carries a com.apple.provenance xattr, which
# ditto would otherwise archive as AppleDouble "._" entries *inside* the bundle. --sequesterRsrc
# parks them under __MACOSX/ instead, where no extractor can leave them behind as unsealed
# detritus -- see the distributable zip below for why that matters. The xattr cannot simply be
# stripped first: xattr -d exits 0 on com.apple.provenance and the attribute survives.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/notarize.zip"

set +e
SUBMIT="$(xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$KN_NOTARY_PROFILE" --wait 2>&1)"
SUBMIT_RC=$?
set -e
printf '%s\n' "$SUBMIT"

if [ $SUBMIT_RC -ne 0 ] || ! printf '%s' "$SUBMIT" | grep -q 'status: Accepted'; then
	ID="$(printf '%s' "$SUBMIT" | awk '/^ *id: /{print $2; exit}')"
	[ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$KN_NOTARY_PROFILE" || true
	die "notarization failed"
fi
ok "accepted"

# ---------------------------------------------------------------- staple

step "Stapling"

# the ticket goes into the .app; stapler cannot write one into a zip
xcrun stapler staple "$APP"
ok "stapled"

# re-zip AFTER stapling: the zip submitted above is not the distributable.
# --sequesterRsrc is load-bearing here. Without it the AppleDouble entries land inside the bundle,
# and Archive Utility cannot reattach the six that sit beside symlinks in Sparkle.framework/ --
# you cannot set an xattr on a symlink -- so it leaves them on disk as real files, and Gatekeeper
# reports "unsealed contents present in the root directory of an embedded framework".
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP_NAME"
rm -f "$DIST/notarize.zip"
ok "$ZIP_NAME"

# ---------------------------------------------------------------- assess as a user's Mac would

step "Assessing the distributable"

# Check the archive's structure before extracting it, because `ditto -x -k` below is precisely the
# one extractor that hides both ways this zip can betray the signature. It reattaches AppleDouble
# metadata and it preserves names byte-for-byte; Archive Utility and unzip do neither, and between
# them they are what almost every user actually runs. 1.7 passed the checks below this line and
# still failed to open on a stranger's Mac (jptechco/kn#34).
#
# Two invariants make the artifact safe under *every* extractor:
#   - no AppleDouble entry inside the bundle, so none can be left behind as unsealed detritus
#   - every name already NFD, so a decomposing extractor is a no-op and the seal still matches
/usr/bin/python3 - "$DIST/$ZIP_NAME" <<'AUDIT' || die "the distributable zip would break its own signature"
import sys, unicodedata, zipfile

names = [i.filename for i in zipfile.ZipFile(sys.argv[1]).infolist()]
bad = False

inside = [n for n in names
          if not n.startswith('__MACOSX/') and ('/._' in n or n.startswith('._'))]
if inside:
    bad = True
    print('AppleDouble entries inside the bundle (%d); --sequesterRsrc is missing:' % len(inside))
    for n in inside[:5]:
        print('   ', n)

# names are stored without the UTF-8 flag, so zipfile hands them back cp437-decoded; undo that
composed = []
for n in names:
    try:
        n = n.encode('cp437').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    if unicodedata.normalize('NFD', n) != n:
        composed.append(n)
if composed:
    bad = True
    print('entry names not in NFD (%d); the normalization step did not run:' % len(composed))
    for n in composed[:5]:
        print('   ', n)

sys.exit(1 if bad else 0)
AUDIT
ok "no AppleDouble inside the bundle, all names NFD"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
ditto -x -k "$DIST/$ZIP_NAME" "$SCRATCH"

ASSESS="$(spctl -a -vvv -t install "$SCRATCH/Kinetic Notes.app" 2>&1 || true)"
case "$ASSESS" in
	*accepted*) ;;
	*) printf '%s\n' "$ASSESS" >&2; die "Gatekeeper rejected the artifact" ;;
esac
xcrun stapler validate "$SCRATCH/Kinetic Notes.app" >/dev/null \
	|| die "stapled ticket does not validate"
ok "Gatekeeper: accepted, Notarized Developer ID"

# ---------------------------------------------------------------- the appcast entry

step "Appcast entry"

SIGNATURE_LINE="$("$SIGN_UPDATE" "$DIST/$ZIP_NAME")"
ED_SIG="$(printf '%s' "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIG" ] && [ -n "$LENGTH" ] || die "could not parse sign_update output: $SIGNATURE_LINE"

TAG="v$MARKETING_VERSION"
cat <<XML

Paste into docs/appcast.xml, inside <channel>, newest first:

    <item>
      <title>$MARKETING_VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://updates.kineticnotes.org/release-notes/$MARKETING_VERSION.html</sparkle:releaseNotesLink>
      <link>https://github.com/jptechco/kn</link>
      <enclosure
        url="https://github.com/jptechco/kn/releases/download/$TAG/$ZIP_NAME"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>

XML

step "Done"
printf '    artifact:  %s\n' "$DIST/$ZIP_NAME"
# .md, not .html. Each release has both, for two consumers that want opposite things: Sparkle loads
# the .html into a web view, so it wants a whole styled document; GitHub renders a release body as
# Markdown, so handing it that document prints the <title> and <style> as visible text -- and turns
# the CSS @media query into an @-mention of github.com/media, as the 1.7 release page still shows.
printf '    next:      gh release create %s "%s" --title "Kinetic Notes %s" --notes-file docs/release-notes/%s.md\n' \
	"$TAG" "$DIST/$ZIP_NAME" "$MARKETING_VERSION" "$MARKETING_VERSION"
printf '    then:      add the <item> above to docs/appcast.xml and open a PR\n\n'
