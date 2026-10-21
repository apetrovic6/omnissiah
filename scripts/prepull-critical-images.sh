#!/usr/bin/env bash
#
# Warm containerd's image cache on every RKE2 node before a Longhorn or Harbor
# upgrade.
#
# Harbor is the pull-through mirror for docker.io, and two things that Harbor
# itself needs are pulled through it: Harbor's own components
# (docker.io/goharbor/*) and the Longhorn CSI driver that Harbor's CNPG
# database depends on (docker.io/longhornio/*). A node that needs a NEW image
# from either set while Harbor is down cannot pull its way out.
#
# That closed into a deadlock on 2026-10-02: a Longhorn bump rolled the CSI
# plugin DaemonSet, luna had no cached copy of the new sidecars, the driver
# deregistered there, the Harbor DB primary living on luna could not restart,
# and Harbor served nothing to the node that needed it. It took ~17 minutes to
# break out, via containerd's last-resort fallback to the upstream registry.
#
# ghcr.io is no longer mirrored (see stc/k8s-base.nix), so CNPG is already off
# this path. These two docker.io prefixes are the remaining links, and dropping
# the docker.io mirror wholesale is too high a price -- hence pre-pulling.
#
# Run AFTER `nixidy build` has rendered the new manifests and BEFORE ArgoCD
# syncs them: the list is read from the rendered manifests, so it is exactly
# the set of images the cluster is about to need.
#
# Usage:  ./scripts/prepull-critical-images.sh [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFESTS="${REPO_ROOT}/modules/noosphere/taghmata/nixidy/manifests/prod"
CONTEXT="${KUBECTL_CONTEXT:-default}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

for d in longhorn harbor; do
  [[ -d "${MANIFESTS}/${d}" ]] || {
    echo "error: ${MANIFESTS}/${d} not found -- run 'nixidy build' first" >&2
    exit 1
  }
done

# The target versions, straight out of the rendered manifests rather than out
# of the running cluster: during an upgrade those differ, and it is the new
# ones that need to be on the nodes beforehand.
mapfile -t IMAGES < <(
  grep -rhoE '(docker\.io/)?(longhornio|goharbor)/[A-Za-z0-9._-]+:[A-Za-z0-9._-]+' \
    "${MANIFESTS}/longhorn" "${MANIFESTS}/harbor" |
    sed 's|^docker\.io/||' | sort -u
)
[[ ${#IMAGES[@]} -gt 0 ]] || { echo "error: no images matched" >&2; exit 1; }

mapfile -t NODES < <(
  kubectl --context "${CONTEXT}" get nodes \
    -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
)
[[ ${#NODES[@]} -gt 0 ]] || { echo "error: no nodes found" >&2; exit 1; }

echo "${#IMAGES[@]} images -> ${#NODES[@]} nodes"
if [[ ${DRY_RUN} -eq 1 ]]; then
  printf '  %s\n' "${IMAGES[@]}"
  exit 0
fi

rc=0
for node in "${NODES[@]}"; do
  echo "=== ${node} ==="
  # shellcheck disable=SC2029  # the image list is meant to expand locally
  ssh -o ConnectTimeout=10 -o BatchMode=yes "root@${node}" \
    "bash -s ${IMAGES[*]}" <<'REMOTE' || rc=1
set -uo pipefail
CTR="/var/lib/rancher/rke2/bin/ctr -a /run/k3s/containerd/containerd.sock -n k8s.io"
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/k3s/containerd/containerd.sock
CRICTL=/var/lib/rancher/rke2/bin/crictl

present=0 pulled=0 failed=0
cached="$($CTR images ls -q 2>/dev/null || true)"
for img in "$@"; do
  full="docker.io/${img}"
  if grep -qxF "$full" <<<"$cached"; then
    present=$((present + 1))
    continue
  fi
  if "$CRICTL" pull "$full" >/dev/null 2>&1; then
    echo "  pulled   ${img}"
    pulled=$((pulled + 1))
  else
    echo "  FAILED   ${img}"
    failed=$((failed + 1))
  fi
done
echo "  ${present} already present, ${pulled} pulled, ${failed} failed"
[[ ${failed} -eq 0 ]]
REMOTE
done

exit "${rc}"
