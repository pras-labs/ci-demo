.DEFAULT_GOAL := help
.PHONY: help setup hooks check clean devpod-up devpod-ssh ci-local \
        build test lint vet fmt fmt-check \
        sca license-check sbom preflight all doctor

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
  	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Full local setup (run once)
	@echo "🏗️ Installing mise tools..."
	mise install
	@echo "🏗️ Installing npm dependencies (commitlint)..."
	npm ci
	$(MAKE) hooks
	@echo "✅ Setup complete"
	mise ls --current --local
	@npx --no-install commitlint --version

hooks: ## Install git hooks
	pre-commit install
	pre-commit install --hook-type commit-msg
	pre-commit install --hook-type pre-push
	pre-commit install-hooks

check: ## Run all pre-commit checks
	pre-commit run --all-files

lint-commits: ## Lint last commit message
	npx --no-install commitlint --from HEAD~1 --to HEAD --verbose

clean: ## Remove caches, reports, and build artifacts
	pre-commit clean
	pre-commit gc
	rm -rf node_modules .cache/npm bin/ coverage.out reports/

devpod-up: ## Start devcontainer via DevPod (VS Code)
	devpod up . --ide vscode

devpod-ssh: ## SSH into devcontainer via DevPod
	devpod up . --ide none
	devpod ssh .

ci-local: ## Simulate CI pre-flight locally (devcontainer CLI)
	devcontainer up --workspace-folder .
	devcontainer exec --workspace-folder . -- make check

# -- Go ----------------------------------------
GO_BIN := bin/ci-demo

build: ## Build Go binary
	go build -o $(GO_BIN) .

test: ## Run Go tests
	go test -race -coverprofile=coverage.out ./...

test-report: test ## Run tests with HTML coverage report
	go tool cover -html=coverage.out -o reports/coverage.html

lint: ## Run golangci-lint
	golangci-lint run ./...

vet: ## Run go vet
	go vet ./...

fmt: ## Format Go code
	gofmt -w .
	goimports -w .

fmt-check: ## Check Go formatting (CI mode)
	@test -z "$$(gofmt -l .)" || (echo "Files need formatting:"; gofmt -l .; exit 1)

# -- SCA ----------------------------------------
SCA_REPORT_DIR := reports/sca

$(SCA_REPORT_DIR):
	mkdir -p $(SCA_REPORT_DIR)

sca: $(SCA_REPORT_DIR) ## Scan dependencies for vulnerabilities (Trivy)
	trivy fs --scanners vuln --severity HIGH,CRITICAL --exit-code 1 .
	trivy fs --scanners vuln --format json --output $(SCA_REPORT_DIR)/trivy-vuln.json .

license-check: $(SCA_REPORT_DIR) ## Check dependency licenses (Trivy)
	trivy fs --scanners license --severity UNKNOWN,HIGH,CRITICAL .
	trivy fs --scanners license --format json --output $(SCA_REPORT_DIR)/trivy-license.json .

sbom: $(SCA_REPORT_DIR) ## Generate SBOM (CycloneDX)
	trivy fs --format cyclonedx --output $(SCA_REPORT_DIR)/sbom.cdx.json .
	echo "📦 SBOM generated ($(wc -l < $(SCA_REPORT_DIR)/sbom.cdx.json) lines)"

# -- Aggregates --------------------------------
preflight: fmt-check vet lint check sast-secrets ## Quick preflight before push
	@echo "✅ Preflight passed"

all: preflight test sca sast ## Full CI simulation locally
	@echo "✅ All checks passed"

doctor: ## Check all required tools are installed
	@echo "Checking tools..."
	@command -v mise >/dev/null && echo "✅ mise" || echo "❌ mise missing (install: https://mise.jdx.dev)"
	@command -v go >/dev/null && echo "✅ go $$(go version | awk '{print $$3}')" || echo "❌ go missing"
	@command -v python3 >/dev/null && echo "✅ python3" || echo "❌ python3 missing"
	@command -v npx >/dev/null && echo "✅ node/npx" || echo "❌ node missing"
	@command -v uv >/dev/null && echo "✅ uv" || echo "❌ uv missing"
	@command -v golangci-lint >/dev/null && echo "✅ golangci-lint" || echo "❌ golangci-lint missing"
	@command -v gitleaks >/dev/null && echo "✅ gitleaks" || echo "❌ gitleaks missing"
	@command -v hadolint >/dev/null && echo "✅ hadolint" || echo "❌ hadolint missing"
	@command -v trivy >/dev/null && echo "✅ trivy" || echo "❌ trivy missing"
	@command -v trufflehog >/dev/null && echo "✅ trufflehog" || echo "❌ trufflehog missing"
	@command -v cosign >/dev/null && echo "✅ cosign" || echo "❌ cosign missing"
	@command -v pre-commit >/dev/null && echo "✅ pre-commit" || echo "❌ pre-commit missing"
	@command -v bandit >/dev/null && echo "✅ bandit" || echo "❌ bandit missing"
	@command -v checkov >/dev/null && echo "✅ checkov" || echo "❌ checkov missing"

SAST_REPORT_DIR := reports/sast

$(SAST_REPORT_DIR):
	mkdir -p $(SAST_REPORT_DIR)

sast-secrets: $(SAST_REPORT_DIR) ## Scan for secrets (gitleaks + trufflehog)
	@echo "-> gitleaks..."
	gitleaks detect --source . --redact --verbose
	@echo "-> trufflehog..."
	trufflehog git file://. --only-verified --no-update

sast-semgrep: $(SAST_REPORT_DIR) ## Run Semgrep SAST
	@echo "-> semgrep..."
	docker run --rm -v "$(PWD):/src" semgrep/semgrep:latest \
	 semgrep scan \
	  --config "p/owasp-top-ten" \
	  --config "p/secrets" \
	  --config "p/dockerfile" \
	  --config "p/kubernetes" \
	  --json-output /src/$(SAST_REPORT_DIR)/semgrep.json \
	  --error \
	  /src

sast-bandit: $(SAST_REPORT_DIR) ## Run Bandit (Python only)
	@PY_FILES=$$(find . -name "*.py" \
	 -not -path "./.venv/*" \
	 -not -path "./node_modules/*" | head -1); \
	if [ -z "$$PY_FILES" ]; then \
	 echo "No Python files, skipping"; \
	else \
	 bandit -r . --severity-level medium \
	  --exclude .venv,node_modules,.git \
	  --format json \
	  --output $(SAST_REPORT_DIR)/bandit.json .; \
	fi

sast-checkov: $(SAST_REPORT_DIR) ## Run Checkov (IaC)
	checkov -d . \
	 --framework dockerfile,kubernetes,gitlab_ci \
	 --output cli --compact \
	 --soft-fail-on MEDIUM \
	 --hard-fail-on HIGH,CRITICAL \
	 --skip-check CKV_DOCKER_2,CKV_DOCKER_7

sast-diff: $(SAST_REPORT_DIR) ## SAST on changed files only (mirrors MR pipeline)
	@echo "-> Scanning changed files vs main..."
	@git fetch origin main 2>/dev/null; \
	CHANGED=$$(git diff --name-only origin/main..HEAD 2>/dev/null || \
	 git diff --name-only HEAD~1..HEAD); \
	echo "Changed files: $$CHANGED"; \
	docker run --rm -v "$(PWD):/src" semgrep/semgrep:latest \
	 semgrep scan \
	  --config "p/owasp-top-ten" \
	  --config "p/secrets" \
	  --error \
	  $$CHANGED

sast: sast-secrets sast-semgrep sast-bandit sast-checkov ## Run all SAST checks
	@echo "✅ All SAST checks done - reports in $(SAST_REPORT_DIR)/"

sast-report: ## Summarize last SAST run
	@echo "-- SAST Report Summary -----------------"
	@[ -f $(SAST_REPORT_DIR)/semgrep.json ] && \
		echo "Semgrep: $$(cat $(SAST_REPORT_DIR)/semgrep.json | \
		python3 -c 'import sys,json; \
		d=json.load(sys.stdin); \
		print(str(len(d.get("results",[])))+" findings")')" \
		|| echo "Semgrep: no report yet"
	@[ -f $(SAST_REPORT_DIR)/bandit.json ] && \
		echo "Bandit:  $$(cat $(SAST_REPORT_DIR)/bandit.json | \
		python3 -c 'import sys,json; \
		d=json.load(sys.stdin); \
		print(str(len(d.get("results",[])))+" findings")')" \
		|| echo "Bandit:  no report yet"
	@echo "---------------------------------------"
