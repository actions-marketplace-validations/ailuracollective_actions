#!/usr/bin/env bash
# Entry point for the standalone `pull-request-template` action. Resolves a type's template and writes the
# step outputs. The rule itself is in lib/template.sh, shared with the PR policy action's
# pr-body-structure check, so the two cannot drift.
#
# Invoked as pull-request-template/resolve.sh from pull-request-template/action.yml.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/template.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/template.sh"

out=${GITHUB_OUTPUT:-/dev/null}
repo=${INPUT_REPO:-${GH_REPO:-}}
runner_tmp=${RUNNER_TEMP:-/tmp}
mkdir -p "$runner_tmp"
target="$runner_tmp/pull-request-template.md"

ref=$(prv_template_ref "${INPUT_REF:-}" "${PR_BASE_SHA:-}" "${EVENT_SHA:-}")
printf 'ref=%s\n' "$ref" >> "$out"
echo "Reading templates at ref '$ref'."

# Untrusted to this action: a `type` becomes a URL path segment, so prv_template_resolve refuses
# anything that could escape the template directory before the value reaches a URL.
code=0
prv_template_resolve "${INPUT_TYPE:-}" "${INPUT_TEMPLATE_DIR:-}" "${INPUT_DEFAULT_TEMPLATE:-}" \
  "$repo" "$ref" "$target" || code=$?

if [ "$code" -eq 2 ]; then
  printf '::error::The type %s cannot be used as a template name. Use only letters, digits, dots, hyphens and underscores.\n' \
    "$(prv_escape "${INPUT_TYPE:-}")"
  printf 'path=\nsource=\nfound=false\nfile=\n' >> "$out"
  exit 1
fi

printf 'path=%s\n' "$PRV_TEMPLATE_PATH" >> "$out"
printf 'source=%s\n' "$PRV_TEMPLATE_SOURCE" >> "$out"

if [ "$code" -eq 1 ]; then
  # `source` is `none` here, not `default`: nothing was read, and reporting a source that was never
  # used would be a small lie a caller could act on.
  printf 'found=false\n' >> "$out"
  printf 'file=\n' >> "$out"
  if [ "${INPUT_FAIL_ON_MISSING:-false}" = 'true' ]; then
    printf '::error::No template at %s in %s at ref %s. Neither %s/%s.md nor the default template exists.\n' \
      "$PRV_TEMPLATE_PATH" "$repo" "$ref" "${INPUT_TEMPLATE_DIR:-}" "$(printf '%s' "${INPUT_TYPE:-}" | tr '[:upper:]' '[:lower:]')"
    exit 1
  fi
  printf '::warning::No template at %s in %s at ref %s. Continue with your own fallback; %s found is false and file is empty.\n' \
    "$PRV_TEMPLATE_PATH" "$repo" "$ref" "'found'"
  exit 0
fi

printf 'found=true\n' >> "$out"
printf 'file=%s\n' "$target" >> "$out"
echo "Found $PRV_TEMPLATE_PATH ($PRV_TEMPLATE_SOURCE)."
