#!/bin/bash
set -euo pipefail

# -- Resolve branch name -------------------------------------
# In GitLab CI MR pipelines, git is in detached HEAD state.
# Use CI env vars instead of git rev-parse.
if [ -n "${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}" ]; then
  # MR pipeline — use the source branch name
  BRANCH="$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
elif [ -n "${CI_COMMIT_REF_NAME:-}" ]; then
  # Push pipeline — use the ref name
  BRANCH="$CI_COMMIT_REF_NAME"
else
  # Local (non-CI) — fall back to git
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
