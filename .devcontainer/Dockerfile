FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

LABEL maintainer="pras-labs" \
  description="Dev + CI runner image for ci-demo"

# Set SHELL early — all subsequent RUN uses pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System packages (minimal — mise handles the rest)
RUN apt-get update && apt-get install --no-install-recommends --yes \
  curl git jq make ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER vscode
WORKDIR /home/vscode

# Create cache dirs (owned by vscode since USER already switched)
RUN mkdir -p .cache/pre-commit .cache/npm

# Install mise (pinned install script — consider checksum in prod)
RUN curl -fsSL https://mise.run | sh
ENV PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:${PATH}"

# Copy tool manifest first (layer cache — only rebuilds when versions change)
COPY --chown=vscode:vscode .mise.toml .

# Install all tools defined in .mise.toml
RUN mise install --yes && mise reshim

# Derive node path dynamically instead of hardcoding version
ENV PATH="/home/vscode/.local/share/mise/shims:${PATH}"

# Install commitlint
COPY --chown=vscode:vscode package.json package-lock.json /home/vscode/app/
RUN pushd /home/vscode/app && npm ci --ignore-scripts \
  && ln -sf /home/vscode/app/node_modules/.bin/commitlint /home/vscode/.local/bin/commitlint

# Smoke test — fail build if any tool is broken
RUN gitleaks version && \
  hadolint --version && \
  trivy --version && \
  pre-commit --version && \
  commitlint --version && \
  trufflehog --version && \
  bandit --version && \
  checkov --version && \
  cosign version

# # TODO: Pre-warm Cache in the Docker Image
# # TRADE-OFF: Image rebuilds when .pre-commit-config.yaml changes — but that's exactly when you want it, and the CI cache block disappears entirely.
# # Prepare pre-commit configuration
#
# COPY .pre-commit-config.yaml /tmp/.pre-commit-config.yaml
#
# # Pre-install all hook environments into the image layer
# RUN PRE_COMMIT_HOME=/opt/pre-commit-cache \
#   pre-commit install-hooks \
#   --config /tmp/.pre-commit-config.yaml
#
# ENV PRE_COMMIT_HOME=/opt/pre-commit-cache
