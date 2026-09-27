#!/usr/bin/env bash
# Check: apply the triage label to a newly opened issue.
# Invoked as auto-label.sh from this action's manifest. Records a verdict and always exits 0;
# lib/report.sh fails the job.
# fails the job.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

prv_init auto-label

# Triage on the `issues` stream, never `pull_request_target`. The gate is load bearing: the `issues`
# workflow type also fires on a pull request being opened, and `github.event.issue.number` is
# absent from a pull request event context.
prv_gate 'issues' 'opened' || exit 0

# `--add-label` is a no-op when the label is present, so this never duplicates it; nothing here
# removes it, so a deliberate maintainer removal sticks.
  output=$(gh issue edit "$ISSUE_NUMBER" --repo "$GH_REPO" --add-label "$INPUT_AUTO_LABEL_NAME" 2>&1) && {
  prv_record pass "Issue #$ISSUE_NUMBER carries $INPUT_AUTO_LABEL_NAME."
  prv_note "Issue #$ISSUE_NUMBER carries $INPUT_AUTO_LABEL_NAME."
  exit 0
}

# A composite action cannot narrow permissions per check, so the calling job holds one token for
# all seven checks and the most common consumer mistake becomes a missing grant. Name it, rather
# than letting a bare 403 stand as the only clue.
if printf '%s' "$output" | grep -qiE 'HTTP 403|403 Forbidden|Resource not accessible by integration'; then
  prv_error 'Workflow misconfiguration: the calling job cannot write issues' \
    "Could not add $INPUT_AUTO_LABEL_NAME to issue #$ISSUE_NUMBER because the token was refused. Nothing about the issue is at fault. Fix: add 'issues: write' to the permissions of the job that calls this action, or set 'enable-auto-label: false' to drop this check. Note that a workflow triggered by 'pull_request' from a fork gets a read-only token that no permission block can widen."
  prv_record fail 'The calling job lacks issues: write, so the label could not be applied.'
  exit 0
fi

prv_warn "Could not add $INPUT_AUTO_LABEL_NAME to issue #$ISSUE_NUMBER. The label must exist on the remote repository. $output"
prv_record skip "Could not add $INPUT_AUTO_LABEL_NAME to issue #$ISSUE_NUMBER. The label must exist on the remote repository."
