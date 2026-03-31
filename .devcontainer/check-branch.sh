#!/bin/bash
set -euo pipefail

# -- Resolve branch name -------------------------------------
# Both GitLab CI MR and GitHub Actions PR pipelines run in detached
# HEAD state: git rev-parse --abbrev-ref HEAD returns "HEAD", not the
# branch name. Use platform-specific env vars to get the real branch.
#
# Priority order:
#   1. GitLab CI MR  - CI_MERGE_REQUEST_SOURCE_BRANCH_NAME
#   2. GitLab CI push/tag - CI_COMMIT_REF_NAME
#   3. GitHub Actions PR - GITHUB_HEAD_REF (source branch of the PR)
#   4. GitHub Actions push/tag - GITHUB_REF_NAME
#   5. Local fallback - git rev-parse (only works outside detached HEAD)
if [ -n "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}" ]; then
  # GitLab CI: MR pipeline - source branch of the merge request
  BRANCH="$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
elif [ -n "${CI_COMMIT_REF_NAME:-}" ]; then
  # GitLab CI: push/tag pipeline
  BRANCH="$CI_COMMIT_REF_NAME"
elif [ -n "${GITHUB_HEAD_REF:-}" ]; then
  # GitHub Actions: PR pipeline - head branch of the pull request
  BRANCH="$GITHUB_HEAD_REF"
elif [ -n "${GITHUB_REF_NAME:-}" ]; then
  # GitHub Actions: push/tag pipeline
  BRANCH="$GITHUB_REF_NAME"
else
  # Local (non-CI) - fall back to git
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

echo "🔎 Checking branch name: $BRANCH"

# -- Exempt base branches ------------------------------------
EXEMPT="^(main|master|develop|staging|production)$"
if echo "$BRANCH" | grep -qE "$EXEMPT"; then
  echo "✅ Exempt branch: $BRANCH"
  exit 0
fi

# -- Enforce naming pattern ----------------------------------
PATTERN="^(feat|fix|chore|hotfix|release|sec|docs|ci)\/[a-z0-9][a-z0-9\-]*$"

if ! echo "$BRANCH" | grep -qE "$PATTERN"; then
  echo ""
  echo "‼️ Branch '$BRANCH' violates naming convention"
  echo "   Pattern : <type>/<kebab-description>"
  echo "   Examples: feat/add-oidc-auth"
  echo "             fix/null-pointer-login"
  echo "             sec/rotate-signing-keys"
  echo "             ci/improve-preflight"
  exit 1
fi

echo "✅ Branch name OK: $BRANCH"
