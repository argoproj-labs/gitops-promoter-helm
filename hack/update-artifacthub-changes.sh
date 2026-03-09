#!/usr/bin/env bash
#
# Update Chart.yaml with the Artifact Hub changes annotation from a GitHub release.
#
# Fetches the release body for a given gitops-promoter release tag, parses the
# Markdown changelog, and sets the artifacthub.io/changes annotation in
# chart/Chart.yaml.
#
# Usage:
#   ./hack/update-artifacthub-changes.sh --version v0.22.7 [--github-token TOKEN]
#
# The annotation format follows:
#   https://artifacthub.io/docs/topics/annotations/helm/
#
# Run from the repo root. Requires: curl, jq, python3, yq (https://github.com/mikefarah/yq)

set -euo pipefail

VERSION=""
GITHUB_TOKEN=""
REPO="argoproj-labs/gitops-promoter"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    --github-token)
      GITHUB_TOKEN="${2:?--github-token requires a value}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Error: --version is required." >&2
  exit 1
fi

CHART_YAML="$(pwd)/chart/Chart.yaml"

if [[ ! -f "$CHART_YAML" ]]; then
  echo "Error: Chart.yaml not found: $CHART_YAML" >&2
  exit 1
fi

# Fetch release body from GitHub API
if [[ -n "$GITHUB_TOKEN" ]]; then
  RELEASE_JSON=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO/releases/tags/$VERSION")
else
  RELEASE_JSON=$(curl -s \
    "https://api.github.com/repos/$REPO/releases/tags/$VERSION")
fi

RELEASE_BODY=$(echo "$RELEASE_JSON" | jq -r '.body // empty')

if [[ -z "$RELEASE_BODY" ]]; then
  echo "Warning: No release body found for $VERSION, skipping changes annotation update." >&2
  exit 0
fi

# Parse the release body into ArtifactHub changes YAML using Python.
# Sections (## Header) are mapped to ArtifactHub change kinds.
# Bullet points within a section become individual change entries.
# PR/issue links in each bullet are extracted into the links field.
CHANGES_YAML=$(python3 - "$RELEASE_BODY" << 'PYTHON_EOF'
import re
import sys

release_body = sys.argv[1]

# Map lowercase section header text (substring match) to ArtifactHub kinds
SECTION_KIND_MAP = [
    ('security',      'security'),
    ('deprecat',      'deprecated'),
    ('remov',         'removed'),
    ('bug fix',       'fixed'),
    ('bug',           'fixed'),
    ('fix',           'fixed'),
    ('patch',         'fixed'),
    ('new feature',   'added'),
    ('new',           'added'),
    ('feature',       'added'),
    ('add',           'added'),
    ('enhancement',   'added'),
    ('improvement',   'changed'),
    ('breaking',      'changed'),
    ('change',        'changed'),
    ('update',        'changed'),
    ('documentation', 'changed'),
    ('performance',   'changed'),
]

def kind_from_section(header_text):
    lower = header_text.lower()
    for keyword, kind in SECTION_KIND_MAP:
        if keyword in lower:
            return kind
    return 'changed'

def kind_from_text(text):
    lower = text.lower()
    if re.search(r'\b(fix|bug|patch|resolv|revert)\b', lower):
        return 'fixed'
    if re.search(r'\b(add|new|support|implement|introduc|feat|enabl)\b', lower):
        return 'added'
    if re.search(r'\b(remov|delet|drop)\b', lower):
        return 'removed'
    if re.search(r'\bdeprecated?\b', lower):
        return 'deprecated'
    if re.search(r'\b(security|cve|vuln)\b', lower):
        return 'security'
    return 'changed'

def yaml_string(s):
    """Quote a string for YAML if it contains special characters."""
    if any(c in s for c in (':', '#', '[', ']', '{', '}', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`', '\n')):
        # Use double-quote escaping
        escaped = s.replace('\\', '\\\\').replace('"', '\\"')
        return '"' + escaped + '"'
    return s

lines = release_body.splitlines()
changes = []
current_kind = 'changed'
in_excluded_section = False

for line in lines:
    line = line.rstrip()

    # Section header detection
    header_match = re.match(r'^#{1,3}\s+(.+)$', line)
    if header_match:
        header_text = header_match.group(1).strip()
        lower = header_text.lower()
        # Skip sections that are not change entries
        if 'new contributor' in lower or 'full changelog' in lower:
            in_excluded_section = True
            current_kind = 'changed'
            continue
        in_excluded_section = False
        current_kind = kind_from_section(header_text)
        continue

    if in_excluded_section:
        continue

    # Bullet point detection
    bullet_match = re.match(r'^[*\-]\s+(.+)$', line)
    if not bullet_match:
        continue

    entry_text = bullet_match.group(1).strip()

    # Extract GitHub PR / issue links
    links = []
    for m in re.finditer(r'https://github\.com/[^\s)\]]+/(pull|issues)/(\d+)', entry_text):
        url = m.group(0).rstrip('.,')
        pr_type = 'GitHub PR' if m.group(1) == 'pull' else 'GitHub Issue'
        links.append((pr_type, url))

    # Build clean description: remove "by @author in <url>" suffix
    description = re.sub(r'\s+by\s+@\S+.*$', '', entry_text)
    description = re.sub(r'\s+in\s+https://\S+', '', description)
    description = description.strip().rstrip('.')

    if not description:
        continue

    # For generic "what's changed" style sections, detect kind from text
    kind = current_kind
    if kind == 'changed':
        detected = kind_from_text(description)
        if detected != 'changed':
            kind = detected

    change = {'kind': kind, 'description': description, 'links': links}
    changes.append(change)

if not changes:
    sys.exit(0)

# Emit YAML
output_lines = []
for change in changes:
    output_lines.append('- kind: ' + change['kind'])
    output_lines.append('  description: ' + yaml_string(change['description']))
    if change['links']:
        output_lines.append('  links:')
        for link_name, link_url in change['links']:
            output_lines.append('    - name: ' + yaml_string(link_name))
            output_lines.append('      url: ' + link_url)

print('\n'.join(output_lines))
PYTHON_EOF
)

if [[ -z "$CHANGES_YAML" ]]; then
  echo "Warning: No changes parsed from release notes for $VERSION, skipping annotation update." >&2
  exit 0
fi

# Update Chart.yaml: set the artifacthub.io/changes annotation.
# The annotation value must be a YAML string (literal block), so we write it
# as a temporary patch file and apply it with yq.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PATCH_YAML="$TMPDIR/changes_patch.yaml"
{
  echo "annotations:"
  echo "  artifacthub.io/changes: |-"
  printf '%s\n' "$CHANGES_YAML" | sed 's/^/    /'
} > "$PATCH_YAML"

yq eval '.annotations += load("'"$PATCH_YAML"'").annotations' "$CHART_YAML" -i

echo "Updated $CHART_YAML with artifacthub.io/changes for $VERSION."
