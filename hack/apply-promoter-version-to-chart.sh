#!/usr/bin/env bash
#
# Bump the helm chart to match a GitOps Promoter release: regenerate from the
# controller-only manifests (dist/install-without-ui.yaml, or dist/install.yaml for
# pre-0.32.0), sync controllerConfiguration, regenerate the dashboard apiserver
# templates, values image tag, appVersion, chart semver bump, Artifact Hub annotations.
#
# Prerequisites:
#   - gitops-promoter clone checked out at the release tag passed to --version
#   - dist/install-without-ui.yaml (>=0.32.0) or dist/install.yaml (<0.32.0) present in that clone
#
# kubebuilder is installed automatically (hack/install-kubebuilder.sh) if not on PATH.
#
# Usage:
#   export KUBEBUILDER_VERSION=v4.14.0   # optional; match CI
#   hack/apply-promoter-version-to-chart.sh \
#     --helm-repo /path/to/gitops-promoter-helm \
#     --gitops-promoter-repo /path/to/gitops-promoter \
#     --version v0.27.0
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_REPO=""
GITOPS_PROMOTER_REPO=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helm-repo)
      HELM_REPO="${2:?}"
      shift 2
      ;;
    --gitops-promoter-repo)
      GITOPS_PROMOTER_REPO="${2:?}"
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

if [[ -z "$HELM_REPO" || -z "$GITOPS_PROMOTER_REPO" || -z "$VERSION" ]]; then
  echo "Usage: $0 --helm-repo DIR --gitops-promoter-repo DIR --version vX.Y.Z" >&2
  exit 1
fi

HELM_REPO="$(cd "$HELM_REPO" && pwd)"
GITOPS_PROMOTER_REPO="$(cd "$GITOPS_PROMOTER_REPO" && pwd)"
CHART_DIR="${HELM_REPO}/chart"
CHART_YAML="${CHART_DIR}/Chart.yaml"
VALUES_YAML="${CHART_DIR}/values.yaml"

if [[ ! -d "$CHART_DIR" ]]; then
  echo "Error: chart directory not found: $CHART_DIR" >&2
  exit 1
fi

if ! command -v kubebuilder >/dev/null 2>&1; then
  echo "kubebuilder not on PATH; installing..."
  export INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
  bash "$SCRIPT_DIR/install-kubebuilder.sh"
  export PATH="$INSTALL_DIR:$PATH"
fi

if ! command -v kubebuilder >/dev/null 2>&1; then
  echo "Error: kubebuilder still not on PATH after install." >&2
  exit 1
fi

if sed --version >/dev/null 2>&1; then
  sed_i() { sed -i "$@"; }
else
  sed_i() { sed -i '' "$@"; }
fi

echo "Regenerating chart from kubebuilder..."
EXTRAS_BACKUP=""
if [[ -d "$CHART_DIR/templates/extras" ]]; then
  EXTRAS_BACKUP="$(mktemp -d)"
  cp -a "$CHART_DIR/templates/extras" "$EXTRAS_BACKUP/saved"
fi
bash "$SCRIPT_DIR/regenerate-helm-chart.sh" \
  --helm-repo "$HELM_REPO" \
  --gitops-promoter-repo "$GITOPS_PROMOTER_REPO"
if [[ -n "$EXTRAS_BACKUP" && -d "$EXTRAS_BACKUP/saved" ]]; then
  rm -rf "$CHART_DIR/templates/extras"
  cp -a "$EXTRAS_BACKUP/saved" "$CHART_DIR/templates/extras"
  rm -rf "$EXTRAS_BACKUP"
fi

echo "Syncing controllerConfiguration from upstream..."
(
  cd "$HELM_REPO"
  bash "$SCRIPT_DIR/update-controllerconfiguration.sh" \
    --gitops-promoter-repo "$GITOPS_PROMOTER_REPO"
)

echo "Syncing dashboard apiserver templates from upstream..."
bash "$SCRIPT_DIR/update-apiserver-templates.sh" \
  --helm-repo "$HELM_REPO" \
  --gitops-promoter-repo "$GITOPS_PROMOTER_REPO"

echo "Setting manager image tag to ${VERSION}..."
sed_i "s/^[[:space:]]*tag: .*/    tag: ${VERSION}/" "$VALUES_YAML"

echo "Reading old appVersion from Chart.yaml..."
OLD_APP="$(grep '^appVersion:' "$CHART_YAML" | tr -d '"' | awk '{print $2}')"

VERSION_WITHOUT_V="${VERSION#v}"
echo "Writing gitops_promoter_version and appVersion (${VERSION_WITHOUT_V})..."
echo "$VERSION_WITHOUT_V" >"${HELM_REPO}/gitops_promoter_version"
sed_i "s/^appVersion: .*/appVersion: ${VERSION_WITHOUT_V}/" "$CHART_YAML"

NEW_APP="$VERSION_WITHOUT_V"
echo "Bumping chart version (old app ${OLD_APP} -> new app ${NEW_APP})..."
OLD_MAJOR=$(echo "$OLD_APP" | cut -d. -f1)
OLD_MINOR=$(echo "$OLD_APP" | cut -d. -f2)
NEW_MAJOR=$(echo "$NEW_APP" | cut -d. -f1)
NEW_MINOR=$(echo "$NEW_APP" | cut -d. -f2)

CURRENT_CHART_VERSION=$(grep '^version:' "$CHART_YAML" | awk '{print $2}')
CHART_MAJOR=$(echo "$CURRENT_CHART_VERSION" | cut -d. -f1)
CHART_MINOR=$(echo "$CURRENT_CHART_VERSION" | cut -d. -f2)
CHART_PATCH=$(echo "$CURRENT_CHART_VERSION" | cut -d. -f3)

if [[ "$NEW_MAJOR" -gt "$OLD_MAJOR" ]]; then
  NEW_CHART_VERSION="$((CHART_MAJOR + 1)).0.0"
elif [[ "$NEW_MINOR" -gt "$OLD_MINOR" ]]; then
  NEW_CHART_VERSION="${CHART_MAJOR}.$((CHART_MINOR + 1)).0"
else
  NEW_CHART_VERSION="${CHART_MAJOR}.${CHART_MINOR}.$((CHART_PATCH + 1))"
fi

sed_i "s/^version: .*/version: ${NEW_CHART_VERSION}/" "$CHART_YAML"
echo "Chart version set to ${NEW_CHART_VERSION}"

echo "Updating Artifact Hub CRD annotations..."
(
  cd "$HELM_REPO"
  bash "$SCRIPT_DIR/update-artifacthub-crd-annotations.sh" \
    --gitops-promoter-repo "$GITOPS_PROMOTER_REPO"
)

echo "Done. Review with: git -C \"$HELM_REPO\" diff && helm lint \"$CHART_DIR\""
