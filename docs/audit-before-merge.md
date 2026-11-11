# Audit-before-merge PRs

Some contract changes are finished and reviewed but not yet audited. Keep these off `develop` until they are, so `develop` only holds audited code and a release never waits on an audit. Hold such a change in an open PR against `develop` with the `audit-before-merge` label. CI fails while the label is on, so the PR can't be merged by accident.

## Holding a change

1. Open the PR against `develop` and get it reviewed.
2. Add the `audit-before-merge` label.

## Merging once audited

When the audit is done, rebase the PR onto `develop`, get it re-reviewed, remove the label and merge it. It then goes out with the next release.

## Preparing a release

Labelled PRs never delay a release; cut it without them. To see which changes are still waiting on an audit:

```shell
gh pr list --label audit-before-merge
```
