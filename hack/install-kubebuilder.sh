#!/usr/bin/env bash
#
# Download and install the kubebuilder CLI (no sudo).
#
# Default install directory is ~/.local/bin (user-writable). Override with
# INSTALL_DIR or --install-dir (e.g. /usr/local/bin on systems where you own it).
#
# Usage:
#   KUBEBUILDER_VERSION=v4.14.0 hack/install-kubebuilder.sh [--install-dir DIR]
#
# After install, ensure DIR is on PATH, e.g. export PATH="$HOME/.local/bin:$PATH"
#
set -euo pipefail

VERSION="${KUBEBUILDER_VERSION:-v4.14.0}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      INSTALL_DIR="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if command -v go >/dev/null 2>&1; then
  GOOS=$(go env GOOS)
  GOARCH=$(go env GOARCH)
else
  case "$(uname -s)" in
    Linux*) GOOS=linux ;;
    Darwin*) GOOS=darwin ;;
    *)
      echo "Error: cannot detect GOOS (install Go or run on Linux/macOS)." >&2
      exit 1
      ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *)
      echo "Error: cannot detect GOARCH from uname -m: $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

URL="https://github.com/kubernetes-sigs/kubebuilder/releases/download/${VERSION}/kubebuilder_${GOOS}_${GOARCH}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Downloading kubebuilder ${VERSION} for ${GOOS}/${GOARCH}..."
curl -fsSL -o "$TMP" "$URL"
chmod +x "$TMP"

mkdir -p "$INSTALL_DIR" || {
  echo "Error: cannot create install directory: $INSTALL_DIR" >&2
  exit 1
}
DEST="${INSTALL_DIR}/kubebuilder"
if ! mv "$TMP" "$DEST" 2>/dev/null; then
  echo "Error: cannot install kubebuilder to $DEST (not writable?). Set INSTALL_DIR or create the directory." >&2
  exit 1
fi
trap - EXIT

echo "Installed: $DEST"
echo "Add to PATH if needed: export PATH=\"${INSTALL_DIR}:\$PATH\"" >&2
"$DEST" version
