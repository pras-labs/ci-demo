#!/bin/bash
set -euo pipefail

echo ""
echo "+=====================================+"
echo "| Setting up dev environment...       |"
echo "+=====================================+"

# -- Activate mise in current shell ---------
export PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:$PATH"
mise trust
eval "$(mise activate bash)" || true

# -- Install project deps (commitlint etc.) --
echo "🏗️ Installing npm dependencies..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
(cd "$PROJECT_DIR" && npm ci)

# -- Git hooks ------------------------------
# Skip git hooks installation when running in CI
if [ -z "${CI:-}" ]; then
  echo "🏗️ Installing git hooks..."
  pre-commit install
  pre-commit install --hook-type commit-msg
  pre-commit install --hook-type pre-push
else
  echo "⏭️ Skipping git hook install (CI mode)"
fi

# -- Pre-download hook envs (first commit faster) --
echo "🗃️ Pre-caching pre-commit environments..."
pre-commit install-hooks

# -- Git config defaults --------------------
git config --global core.autocrlf false
git config --global pull.rebase true
git config --global init.defaultBranch main

# -- Verify tools ---------------------------
echo ""
echo "-- Tool versions ----------------------"
mise ls --current --local
echo "  commitlint : $(npx --no-install commitlint --version)"
echo "---------------------------------------"

echo ""
echo "✅ Setup complete! Run 'make check' to verify."
echo ""
