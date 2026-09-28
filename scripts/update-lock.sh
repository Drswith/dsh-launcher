#!/usr/bin/env bash
# Pin the runtime to one dsh version and refresh runtime/pnpm-lock.yaml with the
# bundled pnpm:
#   make lock                             # re-resolve the pinned version
#   make lock DSH_VERSION=0.1.6-alpha.2   # pin any published version
# Re-resolving the pinned version keeps the committed resolutions; a new pin
# resolves the whole tree from scratch.
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/toolchain.sh"

[ -n "$DSH_VERSION" ] || die "DSH_VERSION is empty and runtime/package.json pins no dsh"
for file in package.json pnpm-workspace.yaml; do
  [ -f "$RUNTIME_PROJECT/$file" ] || die "missing $RUNTIME_PROJECT/$file"
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dsh-launcher-lock.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/toolchain" "$WORK/project"
install_node "$WORK/toolchain"
install_pnpm "$WORK/toolchain"

cp "$RUNTIME_PROJECT/package.json" "$RUNTIME_PROJECT/pnpm-workspace.yaml" "$WORK/project/"
# Across dsh versions the old lock would keep stale peers: pnpm holds on to the
# resolutions of auto-installed peers even when the new plugins' ranges exclude
# them (dsh 0.1.6-alpha.2 kept dsh-attachment 0.1.5-rc.2 and failed to boot).
if [ -f "$RUNTIME_PROJECT/pnpm-lock.yaml" ] && [ "$DSH_VERSION" = "$LOCKED_DSH_VERSION" ]; then
  cp "$RUNTIME_PROJECT/pnpm-lock.yaml" "$WORK/project/"
fi
# Change only the dsh pin; other package.json fields stay as committed.
"$WORK/toolchain/node/bin/node" -e '
  const fs = require("node:fs")
  const [file, version] = process.argv.slice(1)
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"))
  manifest.dependencies = { ...manifest.dependencies, "@deepseek-ai/dsh": version }
  fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n")
' "$WORK/project/package.json" "$DSH_VERSION"

log "resolving @deepseek-ai/dsh@$DSH_VERSION with pnpm $PNPM_VERSION (currently locked: ${LOCKED_DSH_VERSION:-none})"
run_pnpm "$WORK/toolchain" "$WORK/project" "$WORK/pnpm-state" install --lockfile-only --reporter=append-only

cp "$WORK/project/package.json" "$WORK/project/pnpm-lock.yaml" "$RUNTIME_PROJECT/"
packages="$(grep -c 'resolution: {integrity' "$RUNTIME_PROJECT/pnpm-lock.yaml")"
log "runtime locked to dsh $DSH_VERSION ($packages packages); commit runtime/package.json and runtime/pnpm-lock.yaml"
