#!/bin/bash
# One-shot updater for sticks whose Athena predates the built-in updater.
#
# Run it in the Setup Assistant Terminal as _mbsetupuser - nothing to copy:
#
#     curl -fsSL https://raw.githubusercontent.com/Keijo1992/athena-releases/main/u.sh | bash
#
# Finds the stick, fetches whatever the releases repo currently publishes,
# verifies it and replaces Athena.app. An existing WifiConf.plist is kept:
# losing the stick's SSID would break the Wi-Fi join.
set -uo pipefail

MANIFEST="https://github.com/Keijo1992/athena-releases/releases/latest/download/manifest.json"

say()  { printf '%s\n' "$*"; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }
# Piped through bash, stdin is the script - prompts must come from the tty.
ask()  { local r; read -r -p "$1" r < /dev/tty 2>/dev/null || r=""; printf '%s' "$r"; }

build_of() {
  /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null || true
}

say "athena-update"

# --- find the stick -----------------------------------------------------
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  shopt -s nullglob
  FOUND=(/Volumes/*/Athena.app)
  shopt -u nullglob
  case ${#FOUND[@]} in
    1) TARGET=$(dirname "${FOUND[0]}") ;;
    0) die "No Athena.app found on any mounted volume.
   Plug the stick in, or pass its path:
   curl -fsSL $MANIFEST >/dev/null; echo 'rerun with: ... | bash -s /Volumes/YOURSTICK'" ;;
    *) say "Found Athena on more than one volume:"
       i=1; for a in "${FOUND[@]}"; do say "  $i) $(dirname "$a")"; i=$((i+1)); done
       pick=$(ask "Which one? [1-${#FOUND[@]}] ")
       [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#FOUND[@]} ] \
         || die "Nothing done."
       TARGET=$(dirname "${FOUND[$((pick-1))]}") ;;
  esac
fi

[ -d "$TARGET" ] || die "Not a folder: $TARGET"
[ -w "$TARGET" ] || die "Cannot write to $TARGET - is the stick read-only?"

LIVE="$TARGET/Athena.app"
say "target:   $TARGET"
if [ -d "$LIVE" ]; then
  say "current:  build $(build_of "$LIVE" || echo unknown) - will be replaced"
else
  say "No Athena.app in $TARGET - this may be the wrong folder."
  a=$(ask "Install a fresh copy there anyway? [y/N] ")
  [ "$a" = "y" ] || [ "$a" = "Y" ] || die "Nothing done."
fi

# --- what is the latest -------------------------------------------------
say ""
say "checking for the latest build..."
# The ?t= is not decoration: GitHub's releases/latest/download/ redirect is
# CDN-cached and keeps serving the previous release for a while after a new
# one is published, which would report "already up to date" when it is not.
JSON=$(curl -fsSL --max-time 30 "$MANIFEST?t=$(date +%s)") || die "Could not reach GitHub. Is this Mac online?"

field() { printf '%s' "$JSON" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
VERSION=$(field version)
URL=$(field url)
SHA=$(field sha256)
BUILD=$(printf '%s' "$JSON" | sed -n 's/.*"build"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
[ -n "$URL" ] && [ -n "$SHA" ] && [ -n "$BUILD" ] || die "Could not read the manifest."

say "latest:   $VERSION ($BUILD)"

CURRENT=$(build_of "$LIVE")
if [ -n "$CURRENT" ] && [ "$CURRENT" -ge "$BUILD" ] 2>/dev/null; then
  say ""
  say "✓ Already at build $CURRENT. Nothing to do."
  exit 0
fi

# --- fetch and verify ---------------------------------------------------
WORK="$TARGET/.athena-update"
rm -rf "$WORK"; mkdir -p "$WORK" || die "Could not write to the stick."
trap 'rm -rf "$WORK"' EXIT

say "downloading..."
curl -fsSL --max-time 300 -o "$WORK/build.zip" "$URL" || die "Download failed. Nothing was changed."

# These builds are only ad-hoc signed, so Gatekeeper cannot tell a good one
# from a tampered one. The checksum is what does.
GOT=$(shasum -a 256 "$WORK/build.zip" | cut -d' ' -f1)
[ "$GOT" = "$SHA" ] || die "Checksum mismatch - download is corrupt. Nothing was changed.
   expected $SHA
   got      $GOT"
say "checksum: ok"

ditto -x -k "$WORK/build.zip" "$WORK/x" || die "Could not unpack. Nothing was changed."
STAGED="$WORK/x/Athena.app"
[ -x "$STAGED/Contents/MacOS/Athena" ] || die "Downloaded app is incomplete. Nothing was changed."
[ "$(build_of "$STAGED")" = "$BUILD" ] || die "Downloaded build does not match the manifest. Nothing was changed."
xattr -dr com.apple.quarantine "$STAGED" 2>/dev/null || true

# --- install ------------------------------------------------------------
# Nothing above this line touched the stick, so every failure so far was
# harmless. Only now does the old app go.
if [ -d "$LIVE" ]; then
  rm -rf "$LIVE" || die "Could not remove the old Athena.app."
fi
mv "$STAGED" "$LIVE" || die "Could not install the new Athena.app."

# The stick's own Wi-Fi settings outrank the baseline in the archive.
if [ -f "$TARGET/WifiConf.plist" ]; then
  say "kept:     your existing WifiConf.plist"
else
  # Releases carry no baseline - the repo is public and that would publish
  # the shop's SSID. A stick without one needs the network set once.
  say "note:     no WifiConf.plist on this stick - set the network in"
  say "          Athena > Settings, or the MDM check cannot get online."
fi

say ""
say "✓ Installed Athena $VERSION ($BUILD)"
say ""
say "This stick updates itself from now on: Settings > Uuendus."
say "Launch with:"
say "  $LIVE/Contents/MacOS/Athena"
