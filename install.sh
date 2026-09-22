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
set -eu

REPO="userahq/usera-releases"   # public; the app repo is private
HOME_DIR="${USERA_HOME:-$HOME/.usera}"
BIN_DIR="$HOME_DIR/bin"

say() { printf '%s\n' "$*"; }
die() { printf 'usera install: %s\n' "$*" >&2; exit 1; }

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
command -v curl >/dev/null || die "curl is required"
# The checksum tool differs by platform; the format of SHA256SUMS does not.
if command -v sha256sum >/dev/null; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi

TAG="${USERA_VERSION:-}"
if [ -z "$TAG" ]; then
  TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$TAG" ] || die "could not read the latest release from GitHub"
fi
VERSION="${TAG#v}"
ASSET="usera-$VERSION-$OS-$ARCH.tar.gz"
BASE="https://github.com/$REPO/releases/download/$TAG"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Downloading usera $VERSION ($OS/$ARCH)…"
curl -fsSL -o "$TMP/$ASSET" "$BASE/$ASSET" || die "no build for $TAG/$ARCH at $BASE/$ASSET"
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" || die "release $TAG has no SHA256SUMS"
EXPECTED="$(grep " $ASSET\$" "$TMP/SHA256SUMS" | cut -d' ' -f1)"
[ -n "$EXPECTED" ] || die "SHA256SUMS does not list $ASSET"
ACTUAL="$($SHA256 "$TMP/$ASSET" | cut -d' ' -f1)"
[ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for $ASSET"

mkdir -p "$BIN_DIR"
# The tarball holds one directory; strip it so the binaries land in bin/.
tar -xzf "$TMP/$ASSET" -C "$TMP" && SRC="$TMP/usera-$VERSION-$OS-$ARCH"
rm -rf "$BIN_DIR/Usera.app"
cp "$SRC/usera" "$SRC/userad" "$BIN_DIR/"
[ -d "$SRC/Usera.app" ] && cp -R "$SRC/Usera.app" "$BIN_DIR/Usera.app"
chmod 755 "$BIN_DIR/usera" "$BIN_DIR/userad"
# A curl download carries no quarantine flag, but a browser download of this
# script's output might; clear it so Gatekeeper does not block the first run.
[ "$OS" = "darwin" ] && xattr -dr com.apple.quarantine "$BIN_DIR/usera" "$BIN_DIR/userad" "$BIN_DIR/Usera.app" 2>/dev/null || true

LINKED=""
if [ -w /usr/local/bin ]; then
  ln -sf "$BIN_DIR/usera" /usr/local/bin/usera
  ln -sf "$BIN_DIR/userad" /usr/local/bin/userad
  LINKED="/usr/local/bin"
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
  say "Restarting the usera agent on $VERSION…"
  "$BIN_DIR/userad" install >/dev/null
fi

say "Installed usera $VERSION to $BIN_DIR"
if [ -n "$LINKED" ]; then
  say "Linked usera and userad into $LINKED"
else
  say "Add it to your PATH:  export PATH=\"$BIN_DIR:\$PATH\""
fi
say "Next:  usera setup"
