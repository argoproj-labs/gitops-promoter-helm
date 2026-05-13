#!/usr/bin/env bash
#
# Compare gitops_promoter_version in the helm repo to a target release tag.
# For GitHub Actions, appends update_needed=true|false to GITHUB_OUTPUT when set.
#
# Usage:
#   hack/check-promoter-version-update-needed.sh --helm-repo DIR --version v0.27.0
#
set -euo pipefail

HELM_REPO=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helm-repo)
      HELM_REPO="${2:?}"
      shift 2
      ;;
    --version)
      VERSION="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HELM_REPO" || -z "$VERSION" ]]; then
  echo "Usage: $0 --helm-repo DIR --version vX.Y.Z" >&2
  exit 1
fi

if [[ ! -d "$HELM_REPO" ]]; then
  echo "Error: --helm-repo not a directory: $HELM_REPO" >&2
  exit 1
fi

VER_FILE="${HELM_REPO}/gitops_promoter_version"
if [[ ! -f "$VER_FILE" ]]; then
  echo "Error: missing $VER_FILE" >&2
  exit 1
fi

CURRENT="$(tr -d '[:space:]' <"$VER_FILE")"
TARGET_NOPREFIX="${VERSION#v}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "current_version=$CURRENT" >>"$GITHUB_OUTPUT"
fi

if [[ "$CURRENT" == "$TARGET_NOPREFIX" ]]; then
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "update_needed=false" >>"$GITHUB_OUTPUT"
  else
    echo "No update needed: chart already tracks v${CURRENT} (target ${VERSION})."
  fi
  exit 0
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "update_needed=true" >>"$GITHUB_OUTPUT"
else
  echo "Update needed: v${CURRENT} -> ${VERSION}"
fi
exit 0
