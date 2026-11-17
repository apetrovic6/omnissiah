#!/usr/bin/env bash
# Render the taghmata manifests and, when they differ from what is committed,
# open (or update) a pull request with the result.
#
# The manifests ArgoCD applies are a rendered copy committed under
# modules/noosphere/taghmata/nixidy/manifests. They go stale whenever a chart
# version moves (every flake input update) or a source change is not rendered.
# This puts the re-render in front of a human as a pull request: merging it is
# the deploy, and until then nothing reaches the cluster.
#
# One commit per application, so each can be reviewed and reverted alone, plus
# one for the regenerated CRD option modules.
#
# The pull request is created by pushing to refs/for/<branch> (Forgejo's AGit
# flow), which needs push access and no API token. The topic is fixed, so a
# pull request that is still open is updated in place, not duplicated.
#
# Usage:  ./rituals/render-manifests-pr.sh [--no-push]
#   --no-push   make the commits and print the description, push nothing
#
# Expects a clean checkout of the target branch with git identity configured.
set -euo pipefail

ENV_NAME=${ENV_NAME:-prod}
TARGET=${TARGET:-master}
TOPIC=${TOPIC:-ci-rendered-manifests}
MANIFESTS=modules/noosphere/taghmata/nixidy/manifests/$ENV_NAME
GENERATED=modules/taghmata/nixidy/_generated

push=1
[ "${1:-}" = "--no-push" ] && push=0

cd "$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "error: the checkout has uncommitted changes; refusing to mix them into the render" >&2
  exit 1
fi
base=$(git rev-parse --short HEAD)

echo "::group::regenerate CRD option modules"
nix run ".#gen-crd"
# The generator writes nixfmt-style output; the repository is alejandra.
nix fmt -- "$GENERATED" >/dev/null 2>&1
echo "::endgroup::"

echo "::group::render $ENV_NAME"
nix run ".#render-$ENV_NAME"
echo "::endgroup::"

if [ -z "$(git status --porcelain -- "$MANIFESTS" "$GENERATED")" ]; then
  echo "the committed manifests and CRD options match the sources at $base; nothing to do"
  exit 0
fi

summary=$(mktemp)

# Chart versions that moved, read from the labels the charts put on their
# objects. Only charts with a version on both sides: a label that merely
# disappears belongs to a removed file, not to an upgrade.
charts=$(git diff -U0 -- "$MANIFESTS" \
  | grep -E '^[-+][[:space:]]+(helm\.sh/chart|chart): ' \
  | sed -E 's/^([-+])[[:space:]]+(helm\.sh\/chart|chart): /\1 /' \
  | sort -u \
  | awk '{
      sign = $1; label = $2; name = label; sub(/-v?[0-9][0-9A-Za-z.+-]*$/, "", name)
      version = substr(label, length(name) + 2)
      if (sign == "-") old[name] = version; else new[name] = version
    }
    END { for (n in old) if (n in new && old[n] != new[n]) print n ": " old[n] " -> " new[n] }' \
  | sort || true)

if [ -n "$(git status --porcelain -- "$GENERATED")" ]; then
  git add -A -- "$GENERATED"
  files=$(git diff --cached --name-only | wc -l)
  git commit -q -m "chore(nixidy): regenerate CRD options"
  echo "- CRD option modules: $files file(s)" >>"$summary"
fi

# Applications are the first-level directories of the manifests.
apps=$(git status --porcelain -- "$MANIFESTS" \
  | sed -E 's/^.{3}//; s/^.* -> //' \
  | sed "s#^$MANIFESTS/##" | cut -d/ -f1 | sort -u)

for app in $apps; do
  git add -A -- "$MANIFESTS/$app"
  git diff --cached --quiet && continue
  changed=$(git diff --cached --name-only --diff-filter=M | wc -l)
  added=$(git diff --cached --name-only --diff-filter=A | wc -l)
  removed=$(git diff --cached --name-only --diff-filter=D | wc -l)
  git commit -q -m "chore($app): render manifests"
  line="- \`$app\`: $changed changed"
  [ "$added" -gt 0 ] && line="$line, $added added"
  [ "$removed" -gt 0 ] && line="$line, **$removed removed**"
  echo "$line" >>"$summary"
done

if [ -n "$(git status --porcelain -- "$MANIFESTS" "$GENERATED")" ]; then
  echo "error: changes left uncommitted after the per-application commits:" >&2
  git status --porcelain -- "$MANIFESTS" "$GENERATED" >&2
  exit 1
fi

description=$(
  echo "The manifests committed in \`$MANIFESTS\` were not what the sources at $base render. This is the re-render."
  echo
  echo "Merging deploys it: ArgoCD syncs from \`$TARGET\`, with auto-sync and prune. Removed files are objects ArgoCD will prune."
  echo
  echo "One commit per application:"
  echo
  cat "$summary"
  if [ -n "$charts" ]; then
    echo
    echo "Chart versions:"
    echo
    echo "$charts" | sed 's/^/- /'
  fi
)
rm -f "$summary"

echo
echo "$description"
echo
git log --oneline "$base..HEAD"

if [ "$push" = 0 ]; then
  echo
  echo "--no-push: nothing pushed"
  exit 0
fi

# force-push: every run starts from the current tip of the target branch, so
# an open pull request from an earlier run is replaced, not appended to.
git push origin "HEAD:refs/for/$TARGET" \
  -o "topic=$TOPIC" \
  -o "title=chore(taghmata): render manifests" \
  -o "description=$description" \
  -o force-push=true
