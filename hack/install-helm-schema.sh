#!/usr/bin/env bash
#
# Download and install the helm-schema CLI (https://github.com/dadav/helm-schema, no sudo).
# The release archive is verified against the release's checksums.txt.
#
# Default install directory is ~/.local/bin (user-writable). Override with
# INSTALL_DIR or --install-dir.
#
# Usage:
#   HELM_SCHEMA_VERSION=0.24.0 hack/install-helm-schema.sh [--install-dir DIR]
#
# After install, ensure DIR is on PATH, e.g. export PATH="$HOME/.local/bin:$PATH"
#
set -euo pipefail

VERSION="${HELM_SCHEMA_VERSION:-0.24.0}"
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

case "$(uname -s)" in
  Linux*) OS=Linux ;;
  Darwin*) OS=Darwin ;;
  *)
    echo "Error: unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH=x86_64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *)
    echo "Error: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

ARCHIVE="helm-schema_${VERSION}_${OS}_${ARCH}.tar.gz"
BASE_URL="https://github.com/dadav/helm-schema/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading helm-schema ${VERSION} for ${OS}/${ARCH}..."
curl -fsSL -o "${TMP}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"
curl -fsSL -o "${TMP}/checksums.txt" "${BASE_URL}/checksums.txt"

EXPECTED="$(awk -v f="$ARCHIVE" '$2 == f {print $1}' "${TMP}/checksums.txt")"
if [[ -z "$EXPECTED" ]]; then
  echo "Error: ${ARCHIVE} not listed in checksums.txt" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "${TMP}/${ARCHIVE}" | awk '{print $1}')"
else
  ACTUAL="$(shasum -a 256 "${TMP}/${ARCHIVE}" | awk '{print $1}')"
fi
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Error: checksum mismatch for ${ARCHIVE} (expected ${EXPECTED}, got ${ACTUAL})" >&2
  exit 1
fi

tar -xzf "${TMP}/${ARCHIVE}" -C "$TMP" helm-schema

mkdir -p "$INSTALL_DIR" || {
  echo "Error: cannot create install directory: $INSTALL_DIR" >&2
  exit 1
}
DEST="${INSTALL_DIR}/helm-schema"
if ! mv "${TMP}/helm-schema" "$DEST" 2>/dev/null; then
  echo "Error: cannot install helm-schema to $DEST (not writable?). Set INSTALL_DIR or create the directory." >&2
  exit 1
fi

echo "Installed: $DEST"
echo "Add to PATH if needed: export PATH=\"${INSTALL_DIR}:\$PATH\"" >&2
"$DEST" --version
