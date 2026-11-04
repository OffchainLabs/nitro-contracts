# Awaiting-release PRs

Some contract changes, such as small quality-of-life fixes, aren't worth a release of their own. Keep these in an open PR against `develop` with the `awaiting-release` label until a release they can go into. CI fails while the label is on, so the PR can't be merged by accident.

## Holding a change

1. Open the PR against `develop` and get it reviewed.
2. Add the `awaiting-release` label.
3. In the PR description, say when it should be included, for example "with the next release that changes the Outbox".

## Preparing a release

List the waiting PRs:

```shell
gh pr list --label awaiting-release
```

For each one, either leave it waiting or include it: rebase it onto `develop`, get it re-reviewed, remove the label and merge it.
