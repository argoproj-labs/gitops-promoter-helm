#!/usr/bin/env bash
#
# Download and install the kubebuilder CLI to a bin directory (default /usr/local/bin).
#
# Usage:
#   KUBEBUILDER_VERSION=v4.14.0 hack/install-kubebuilder.sh [--install-dir DIR]
#
# If DIR is not writable, uses sudo mv (typical for /usr/local/bin on CI).
#
set -euo pipefail

VERSION="${KUBEBUILDER_VERSION:-v4.14.0}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

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

mkdir -p "$INSTALL_DIR"
DEST="${INSTALL_DIR}/kubebuilder"
if [[ -w "$INSTALL_DIR" ]]; then
  mv "$TMP" "$DEST"
else
  sudo mv "$TMP" "$DEST"
fi
trap - EXIT

echo "Installed: $DEST"
"$DEST" version
