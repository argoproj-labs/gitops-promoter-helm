#!/usr/bin/env bash
#
# Print the latest GitHub release tag for argoproj-labs/gitops-promoter (e.g. v0.27.0).
#
# Usage:
#   hack/fetch-promoter-latest-release.sh
#
# Environment:
#   GITHUB_TOKEN  Optional; reduces rate limits on api.github.com.
#
set -euo pipefail

URL="https://api.github.com/repos/argoproj-labs/gitops-promoter/releases/latest"
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  TAG="$(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" "$URL" | jq -r .tag_name)"
else
  TAG="$(curl -fsSL "$URL" | jq -r .tag_name)"
fi

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "Error: failed to resolve latest release tag from GitHub API." >&2
  exit 1
fi

echo "$TAG"
