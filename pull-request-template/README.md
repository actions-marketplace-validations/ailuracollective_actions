# pull-request-template

Resolves the pull request template for a given **type** at a given **git ref**, downloads it, and
exposes the resolved path, the ref it read, and whether the file actually exists.

It is a standalone helper for your own job. The PR policy action
([`ailuracollective/actions/pr`](../../pr/action.yml)) does **not** call it as a step, and that is
deliberate — see
[Why the two surfaces share code](#why-the-two-surfaces-share-code-instead-of-a-second-copy).

## Usage

```yaml
jobs:
  template-check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Resolve the template for this PR's type
        id: template
        uses: ailuracollective/actions/pull-request-template@v1
        with:
          type: feat
          # Pin the ref yourself whenever the default is not what you want.
          ref: ${{ github.event.pull_request.base.sha }}

      - name: Fail when the template is missing
        run: |
          if [ "${{ steps.template.outputs.found }}" != 'true' ]; then
            echo "No template at ${{ steps.template.outputs.path }}"
            exit 1
          fi

      - name: Show the headings the template requires
        run: grep '^## ' '${{ steps.template.outputs.file }}'
```

`fail-on-missing: true` replaces that guard with a failed step.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `type` | — (required) | PR type label, e.g. `feat`. |
| `ref` | `''` | Git ref to read at. Empty falls back to the PR base sha, then to `github.sha`. |
| `repo` | `''` | `owner/repo` holding the template. Empty uses the current repository. |
| `template-dir` | `.github/PULL_REQUEST_TEMPLATE` | Directory holding the per-type templates. |
| `default-template` | `.github/PULL_REQUEST_TEMPLATE.md` | Template used when the dedicated one is absent. |
| `fail-on-missing` | `false` | Fail the step when no template exists. |

## Outputs

| Output | Meaning |
| --- | --- |
| `path` | Resolved repository-relative path. Set even when nothing exists there. |
| `source` | `dedicated` or `default`, telling which rule matched. |
| `found` | `true` when the path exists at the resolved ref. |
| `ref` | The ref actually read, after the fallback chain. |
| `file` | Local path of the downloaded template, or empty. |

## The resolution rule

Try `<template-dir>/<type>.md` first, case-folded, and fall back to `<default-template>` when it is
absent. There is no per-type table, so giving a new type its own sections is a matter of dropping
`<template-dir>/<newtype>.md` into the repository — nothing here needs to change, and a type with no
file silently inherits the default template. `type` is restricted to letters, digits, dots, hyphens
and underscores, because it becomes a URL path segment.

This is the same rule `lib/template.sh` implements once for both surfaces, so the two agree by construction.

## The ref fallback chain, and why it is ordered that way

`ref` → `github.event.pull_request.base.sha` → `github.sha`.

The order is the safety property. On a fork pull request, `github.event.pull_request.base.sha` is a
commit in the base repository that the fork author cannot move, while `github.sha` is the PR head and
therefore attacker-controlled. The PR base sha is preferred so an unconfigured call cannot be
redirected to a template the PR author wrote. Outside a pull request event the base sha is empty and
`github.sha` is used, which is the base branch tip on `issues` and `push`.

Pin `ref` explicitly whenever the call happens on an event where `github.sha` is not a commit you
control.

## Why the two surfaces share code instead of a second copy

Both surfaces resolve a template by the same rule, so the rule lives once, in
`lib/template.sh`, and both source it. The PR policy's `pr/pr-body-structure.sh` reports a verdict;
`pull-request-template/resolve.sh` writes step outputs. Different reporting contracts, one rule.

This action used to inline the whole thing — 138 lines of bash — with the duplication described as
the price of not being able to reference a sibling action. That justification no longer holds: a root
composite action *can* reach a subdirectory of its own repository, because the whole repository is
downloaded at a tag and `github.action_path` locates it. The deeper reason to extract was simpler:
the inlined copy was **never executed by the test harness**, so 138 published lines were unverified.
`pull-request-template/resolve.sh` is now covered by 20 assertions, including the path-traversal guard and
every rung of the ref chain.

The one filesystem assumption this makes is that `github.action_path` points at `pull-request-template`,
so `../..` reaches the repository root. The harness asserts that every script any step in any
manifest invokes exists on disk, resolved the same way, and separately asserts that the path pattern
matched every step — because a path check that matches nothing passes vacuously.

## Requirements

`gh` and `jq` are preinstalled on `ubuntu-latest`. The action needs `contents: read` (or a token you
pass through, if you fork the environment) and never checks out the pull request itself, so untrusted
fork code never reaches the runner.
