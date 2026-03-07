#!/usr/bin/env bash

set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
LANDING_SYNC_TOKEN="${LANDING_SYNC_TOKEN:?LANDING_SYNC_TOKEN is required}"
LANDING_REPO="${LANDING_REPO:-miguelgarglez/momentum-landing}"
LANDING_BASE_BRANCH="${LANDING_BASE_BRANCH:-main}"
LANDING_DATA_PATH="${LANDING_DATA_PATH:-src/data/changelog.generated.json}"
LANDING_BRANCH="${LANDING_BRANCH:-codex/changelog-${RELEASE_TAG#v}}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-${GITHUB_REPOSITORY:-miguelgarglez/momentum}}"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

OUTPUT_JSON="$TEMP_DIR/changelog.generated.json"
LANDING_DIR="$TEMP_DIR/momentum-landing"
LANDING_REMOTE_URL="https://x-access-token:${LANDING_SYNC_TOKEN}@github.com/${LANDING_REPO}.git"
RELEASE_URL="https://github.com/${SOURCE_REPOSITORY}/releases/tag/${RELEASE_TAG}"

python3 scripts/export_web_changelog.py \
  --repository "$SOURCE_REPOSITORY" \
  --output "$OUTPUT_JSON"

git clone --depth 1 --branch "$LANDING_BASE_BRANCH" "$LANDING_REMOTE_URL" "$LANDING_DIR"
cp "$OUTPUT_JSON" "$LANDING_DIR/$LANDING_DATA_PATH"

pushd "$LANDING_DIR" >/dev/null

npm ci
npm run build

if git diff --quiet -- "$LANDING_DATA_PATH"; then
  echo "Landing changelog is already up to date."
  popd >/dev/null
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git checkout -B "$LANDING_BRANCH"
git add "$LANDING_DATA_PATH"
git commit -m "chore(web): sync changelog ${RELEASE_TAG#v}"
git push --force-with-lease origin "$LANDING_BRANCH"

PR_TITLE="chore(web): sync changelog ${RELEASE_TAG#v}"
PR_BODY=$(cat <<EOF
## Summary

* sync the generated Momentum changelog data for ${RELEASE_TAG}
* update the landing changelog feed used by \`/changelog\`

## Source

* release: ${RELEASE_URL}
EOF
)

EXISTING_PR_NUMBER="$(gh pr list --repo "$LANDING_REPO" --head "$LANDING_BRANCH" --json number --jq '.[0].number // ""')"

if [ -n "$EXISTING_PR_NUMBER" ]; then
  gh pr edit "$EXISTING_PR_NUMBER" \
    --repo "$LANDING_REPO" \
    --title "$PR_TITLE" \
    --body "$PR_BODY"
else
  gh pr create \
    --repo "$LANDING_REPO" \
    --base "$LANDING_BASE_BRANCH" \
    --head "$LANDING_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY"
fi

popd >/dev/null
