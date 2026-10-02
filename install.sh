#!/bin/sh
# usera installer — the usera agent for macOS in one command:
#
#   curl -fsSL https://raw.githubusercontent.com/userahq/usera-releases/main/install.sh | sh
#
# Downloads the latest GitHub Release (or $USERA_VERSION, e.g. v0.1.0),
# verifies its SHA-256, installs `usera`, `userad` and `Usera.app` into
# $USERA_HOME/bin (default ~/.usera/bin), links the two binaries into
# /usr/local/bin when that is writable, and — if the agent is already
# running on this machine — restarts it on the new build. Then:
#
#   usera setup        first time on a device
#   usera update       later: the same download, from the CLI
#
# A device with no internet access installs from a release tarball copied
# onto it, with no download at all:
#
#   sh install.sh --from ./usera-0.1.12-darwin-arm64.tar.gz [--sha256 ./SHA256SUMS]
#
# The tarball is checked against SHA256SUMS when one sits next to it (or the
# file --sha256 names), and refused if it is for another platform or
# architecture. The install is marked as one from a tarball, so `usera
# update` prints this command instead of looking for a download.
#
# USERA_LINK_DIR names where the two binaries are linked (default
# /usr/local/bin, when writable); set it empty to skip linking.
set -eu

REPO="userahq/usera-releases"   # public; the app repo is private
HOME_DIR="${USERA_HOME:-$HOME/.usera}"
BIN_DIR="$HOME_DIR/bin"

say() { printf '%s\n' "$*"; }
die() { printf 'usera install: %s\n' "$*" >&2; exit 1; }

FROM=""
SUMS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) [ $# -ge 2 ] || die "--from needs a tarball path"; FROM="$2"; shift 2 ;;
    --from=*) FROM="${1#--from=}"; shift ;;
    --sha256) [ $# -ge 2 ] || die "--sha256 needs a SHA256SUMS path"; SUMS="$2"; shift 2 ;;
    --sha256=*) SUMS="${1#--sha256=}"; shift ;;
    -h|--help)
      say "usage: install.sh [--from <usera-VERSION-OS-ARCH.tar.gz> [--sha256 <SHA256SUMS>]]"
      exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done
[ -z "$SUMS" ] || [ -n "$FROM" ] || die "--sha256 only goes with --from"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  *) die "$(uname -s) is not supported yet (Windows is on the plan)" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64) ARCH="x64" ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac
# The checksum tool differs by platform; the format of SHA256SUMS does not.
if command -v sha256sum >/dev/null; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# verify <tarball> <SHA256SUMS> <asset name>
verify() {
  EXPECTED="$(grep " \*\{0,1\}$3\$" "$2" | cut -d' ' -f1 | tr 'A-F' 'a-f')"
  [ -n "$EXPECTED" ] || die "$2 does not list $3"
  ACTUAL="$($SHA256 "$1" | cut -d' ' -f1)"
  [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for $3"
}

if [ -n "$FROM" ]; then
  # Air-gapped: everything comes from the tarball on disk. Its name says
  # what it holds, the same name the Releases ship.
  [ -f "$FROM" ] || die "no tarball at $FROM"
  ASSET="$(basename "$FROM")"
  REST="${ASSET#usera-}"
  REST="${REST%.tar.gz}"
  case "$ASSET" in
    usera-*-darwin-arm64.tar.gz|usera-*-darwin-x64.tar.gz|usera-*-linux-arm64.tar.gz|usera-*-linux-x64.tar.gz) ;;
    *) die "$ASSET is not a usera release tarball (expected usera-<version>-$OS-$ARCH.tar.gz)" ;;
  esac
  T_ARCH="${REST##*-}"
  REST="${REST%-*}"
  T_OS="${REST##*-}"
  VERSION="${REST%-*}"
  [ -n "$VERSION" ] || die "$ASSET names no version"
  if [ "$T_OS" != "$OS" ] || [ "$T_ARCH" != "$ARCH" ]; then
    die "$ASSET is for $T_OS/$T_ARCH, and this device is $OS/$ARCH: copy usera-$VERSION-$OS-$ARCH.tar.gz instead"
  fi
  TAG="v$VERSION"
  if [ -z "$SUMS" ] && [ -f "$(dirname "$FROM")/SHA256SUMS" ]; then SUMS="$(dirname "$FROM")/SHA256SUMS"; fi
  if [ -n "$SUMS" ]; then
    [ -f "$SUMS" ] || die "no SHA256SUMS at $SUMS"
    verify "$FROM" "$SUMS" "$ASSET"
    say "Installing usera $VERSION ($OS/$ARCH) from $FROM, checksum verified…"
  else
    say "Installing usera $VERSION ($OS/$ARCH) from ${FROM}…"
    say "No SHA256SUMS next to the tarball, so its checksum was not verified (pass --sha256 <file> to check it)."
  fi
  cp "$FROM" "$TMP/$ASSET"
else
  command -v curl >/dev/null || die "curl is required (on a device with no internet access, use --from <tarball>)"

  # USERA_RELEASES_URL names a mirror instead of GitHub: a directory serving
  # latest.json (GitHub's release shape; only tag_name is read here) and
  # <tag>/<asset> + <tag>/SHA256SUMS. `usera update` reads the same variable.
  MIRROR="${USERA_RELEASES_URL:-}"
  MIRROR="${MIRROR%/}"
  if [ -n "$MIRROR" ]; then LATEST="$MIRROR/latest.json"; else LATEST="https://api.github.com/repos/$REPO/releases/latest"; fi
  TAG="${USERA_VERSION:-}"
  if [ -z "$TAG" ]; then
    TAG="$(curl -fsSL "$LATEST" \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$TAG" ] || die "could not read the latest release from $LATEST (on a device with no internet access, use --from <tarball>)"
  fi
  VERSION="${TAG#v}"
  ASSET="usera-$VERSION-$OS-$ARCH.tar.gz"
  if [ -n "$MIRROR" ]; then BASE="$MIRROR/$TAG"; else BASE="https://github.com/$REPO/releases/download/$TAG"; fi

  say "Downloading usera $VERSION ($OS/$ARCH)…"
  curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" || die "no build for $TAG/$ARCH at $BASE/$ASSET"
  curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || die "release $TAG has no SHA256SUMS"
  verify "$TMP/$ASSET" "$TMP/SHA256SUMS" "$ASSET"
fi

mkdir -p "$BIN_DIR"
# The tarball holds one directory; strip it so the binaries land in bin/.
tar -xzf "$TMP/$ASSET" -C "$TMP" || die "could not unpack $ASSET"
SRC="$TMP/usera-$VERSION-$OS-$ARCH"
for b in usera userad; do
  [ -f "$SRC/$b" ] || die "$ASSET has no $b in usera-$VERSION-$OS-$ARCH/"
done
rm -rf "$BIN_DIR/Usera.app"
if [ "$OS" = "linux" ]; then
  # Linux refuses to write over a running executable ("Text file busy"), and
  # userad is running on any machine being updated: copy each binary beside
  # it and rename it into place, as `usera update` does.
  for b in usera userad; do
    cp "$SRC/$b" "$BIN_DIR/.$b.new" && mv -f "$BIN_DIR/.$b.new" "$BIN_DIR/$b"
  done
else
  cp "$SRC/usera" "$SRC/userad" "$BIN_DIR/"
fi
[ -d "$SRC/Usera.app" ] && cp -R "$SRC/Usera.app" "$BIN_DIR/Usera.app"
chmod 755 "$BIN_DIR/usera" "$BIN_DIR/userad"
# A curl download carries no quarantine flag, but a browser download of this
# script's output might; clear it so Gatekeeper does not block the first run.
[ "$OS" = "darwin" ] && xattr -dr com.apple.quarantine "$BIN_DIR/usera" "$BIN_DIR/userad" "$BIN_DIR/Usera.app" 2>/dev/null || true

# Mark how this install was made: `usera update` reads the marker and, on a
# device that installs from tarballs, prints the --from command instead of
# looking for a download. A download install clears it.
if [ -n "$FROM" ]; then
  printf 'Installed from %s on %s. Delete this file to let `usera update` download releases.\n' \
    "$ASSET" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HOME_DIR/airgapped"
else
  rm -f "$HOME_DIR/airgapped"
fi

LINKED=""
LINK_DIR="${USERA_LINK_DIR-/usr/local/bin}"
if [ -n "$LINK_DIR" ] && [ -w "$LINK_DIR" ]; then
  ln -sf "$BIN_DIR/usera" "$LINK_DIR/usera"
  ln -sf "$BIN_DIR/userad" "$LINK_DIR/userad"
  LINKED="$LINK_DIR"
fi

# Already running here? Re-install the service so it restarts on this build
# (userad install writes the service definition for its own path and restarts
# it): a launchd agent on macOS, a systemd user unit on Linux.
installed() {
  if [ "$OS" = "darwin" ]; then
    launchctl print "gui/$(id -u)/ai.usera.sensor" >/dev/null 2>&1
  else
    command -v systemctl >/dev/null && systemctl --user is-enabled --quiet usera-sensor.service 2>/dev/null
  fi
}
if installed; then
  say "Restarting the usera agent on ${VERSION}…"
  "$BIN_DIR/userad" install >/dev/null
fi

say "Installed usera $VERSION to $BIN_DIR"
if [ -n "$LINKED" ]; then
  say "Linked usera and userad into $LINKED"
else
  say "Add it to your PATH:  export PATH=\"$BIN_DIR:\$PATH\""
fi
say "Next:  usera setup"
