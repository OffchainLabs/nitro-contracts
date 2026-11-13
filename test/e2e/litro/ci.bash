#!/usr/bin/env bash
# Runs a litro test job in one container from the prebaked test image (test/e2e/litro/Dockerfile).
# litro boots L1 and L2 as the container starts. This checkout's source replaces the image's copy and is
# compiled there; hardhat and forge recompile only files whose content changed. Then the L3 node and the
# tests run inside the container.
#
# usage: test/e2e/litro/ci.bash <command>, e.g. test/e2e/litro/ci.bash yarn test:e2e
#
# env:
#   LITRO_TESTS_IMAGE   image to run; pulled, or built from the Dockerfile when it can't be pulled
#   L3                  true deploys and starts the L3 before the command (default true)
#   FEE_TOKEN_DECIMALS, FEE_TOKEN_PRICER  passed to l3.bash
set -euo pipefail
cd "$(dirname "$0")/../../.."

image=${LITRO_TESTS_IMAGE:-ghcr.io/offchainlabs/nitro-contracts-litro-tests:develop}
ct=${LITRO_TESTS_CONTAINER:-litro-tests}
repo=/home/user/nitro-contracts
t0=$(date +%s)
step() { echo "[$(($(date +%s) - t0))s] $*"; }

if ! docker image inspect "$image" >/dev/null 2>&1 && ! docker pull -q "$image"; then
  step "can't pull $image; building it"
  docker build -f test/e2e/litro/Dockerfile -t "$image" .
fi

docker rm -f "$ct" >/dev/null 2>&1 || true
docker run -d --name "$ct" "$image" >/dev/null
step "started $image"

x() {
  docker exec -i -w "$repo" -e PATH=/opt/node24/bin:/usr/local/bin:/usr/bin:/bin \
    -e FEE_TOKEN_DECIMALS="${FEE_TOKEN_DECIMALS:-}" -e FEE_TOKEN_PRICER="${FEE_TOKEN_PRICER:-}" \
    -e L3_DEPLOYMENT_PATH=/tmp/l3/l3deployment.json "$ct" bash -c "$1"
}
on_exit() {
  local rc=$?
  if [ "$rc" != 0 ]; then
    docker logs --tail 60 "$ct" 2>&1 || true
    docker exec "$ct" tail -n 60 /tmp/l3/l3node.log 2>/dev/null || true
  fi
  [ "${LITRO_TESTS_KEEP:-}" = true ] || docker rm -f "$ct" >/dev/null 2>&1 || true
}
trap on_exit EXIT

# Copy this checkout's source over the image's, then delete source files this checkout doesn't have.
# Installed packages and compile output stay, so unchanged contracts aren't recompiled.
files=$(mktemp)
list_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git ls-files --recurse-submodules
    git ls-files --others --exclude-standard
  else # e.g. a worktree whose git dir isn't mounted
    find . \( -name .git -o -path ./node_modules -o -path ./build -o -path ./cache -o -path ./out \
      -o -path ./forge-cache \) -prune -o \( -type f -o -type l \) -print | sed 's,^\./,,'
  fi
}
list_files | LC_ALL=C sort -u | while IFS= read -r f; do [ ! -e "$f" ] || printf '%s\n' "$f"; done >"$files"
# COPYFILE_DISABLE and --no-xattrs keep macOS tar from adding ._ files that solc would try to parse.
COPYFILE_DISABLE=1 tar --no-xattrs -T "$files" -cf - | x 'tar -xf -'
x 'cat >/tmp/checkout-files
  find . \( -path ./node_modules -o -path ./build -o -path ./cache -o -path ./out -o -path ./forge-cache \) -prune \
    -o -type f -print | sed "s,^\./,," | LC_ALL=C sort | LC_ALL=C comm -23 - /tmp/checkout-files |
    tr "\n" "\0" | xargs -0 -r rm -f --' <"$files"
step "copied source"

x 'sha256sum package.json yarn.lock patches/* | cmp -s - /home/user/deps.sha256 ||
  { echo "dependencies changed; installing"; yarn install --frozen-lockfile; }'
x 'yarn -s build && yarn -s build:forge:yul && test/e2e/litro/l3.bash build /tmp/l3'
step "compiled"

for i in $(seq 1 120); do
  [ "$(x 'cast chain-id --rpc-url http://127.0.0.1:8547' 2>/dev/null)" = 412346 ] && break
  [ "$i" != 120 ] || { echo "litro L2 did not start" >&2; exit 1; }
  sleep 0.5
done
step "litro up"

if [ "${L3:-true}" = true ]; then
  x 'test/e2e/litro/l3.bash deploy /tmp/l3 && test/e2e/litro/l3.bash start /tmp/l3 &&
    test/e2e/litro/l3.bash fund /tmp/l3'
  step "L3 ready"
fi

x "$(printf '%q ' "$@")"
step "done"
