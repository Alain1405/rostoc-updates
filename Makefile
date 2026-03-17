.PHONY: format lint lint-ci test-local test-script test-env test-env-regression validate-paths setup-act ai-test-smoke ai-test-full ai-test help

WORKFLOW_FILES := $(shell find .github -name '*.yml' -o -name '*.yaml')

format:
	@[ -z "$(WORKFLOW_FILES)" ] || npx --yes prettier@3 --write $(WORKFLOW_FILES)

lint:
	actionlint

# ── AI test runner targets ────────────────────────────────────────────────────
# Produces .artifacts/test/summary.{txt,json} + full.log for AI consumption.
ai-test-smoke:
	@bash scripts/ai-test smoke

ai-test-full:
	@bash scripts/ai-test full

ai-test:
	$(if $(MODE),bash scripts/ai-test $(MODE),bash scripts/ai-test smoke)

validate-paths:
	@./scripts/ci/validate_workflow_paths.sh

test-env:
	@./scripts/ci/test_env_handling.sh

test-env-regression:
	@./scripts/ci/test_env_regression.sh

lint-ci:
	actionlint -color -shellcheck shellcheck

# Local testing targets
test-local:
	@echo "📋 Available CI scripts:"
	@./scripts/ci/test_locally.sh

test-script:
	@if [ -z "$(SCRIPT)" ]; then \
		echo "❌ Error: SCRIPT variable required"; \
		echo "Usage: make test-script SCRIPT=generate_and_verify_config.sh"; \
		exit 1; \
	fi
	@./scripts/ci/test_locally.sh $(SCRIPT)

setup-act:
	@echo "⚠️  WARNING: Act has limited value for this repository"
	@echo ""
	@echo "Your CI requires macOS/Windows runners for builds, which Act cannot simulate."
	@echo "Act only supports Linux containers via Docker."
	@echo ""
	@echo "Recommended alternatives:"
	@echo "  • make test-script SCRIPT=<name>  - Test CI scripts directly (30 sec)"
	@echo "  • make lint                       - Validate workflow syntax (5 sec)"
	@echo "  • Native builds in rostoc repo    - Test actual macOS builds (20 min)"
	@echo ""
	@read -p "Still want to install Act for limited platform-agnostic testing? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "🐳 Checking Act installation..."; \
		if command -v act >/dev/null 2>&1; then \
			echo "✅ Act is already installed: $$(act --version)"; \
		else \
			echo "📦 Installing Act..."; \
			brew install act; \
		fi; \
		echo ""; \
		echo "🔧 Checking Docker..."; \
		if docker ps >/dev/null 2>&1; then \
			echo "✅ Docker is running"; \
		else \
			echo "⚠️  Docker is not running. Please start Docker Desktop."; \
			echo "   Or install Colima: brew install colima && colima start"; \
		fi; \
		echo ""; \
		if [ ! -f .actrc ]; then \
			echo "📝 Creating .actrc from template..."; \
			cp .actrc.template .actrc; \
			echo "✅ .actrc created. Edit it to customize Act settings."; \
		else \
			echo "✅ .actrc already exists"; \
		fi; \
		echo ""; \
		if [ ! -f .secrets ]; then \
			echo "📝 Creating .secrets from template..."; \
			cp .secrets.template .secrets; \
			echo "✅ .secrets created. Edit it with real or fake values for testing."; \
		else \
			echo "✅ .secrets already exists"; \
		fi; \
		echo ""; \
		echo "ℹ️  Act can only test platform-agnostic workflows like:"; \
		echo "   act -W .github/workflows/setup.yml -n"; \
		echo ""; \
		echo "❌ Build workflow will NOT work (requires macOS/Windows):"; \
		echo "   act -W .github/workflows/build.yml  # Will fail"; \
	else \
		echo "Cancelled. Use 'make test-script' instead for fast local testing."; \
	fi

help:
	@echo "Rostoc Updates - Local CI Testing Commands"
	@echo ""
	@echo "Linting & Formatting:"
	@echo "  make format              Format workflow YAML files with Prettier"
	@echo "  make lint                Lint workflows with actionlint"
	@echo "  make lint-ci             Lint workflows with colored output (CI mode)"
	@echo "  make validate-paths      Validate script paths in workflows (catches path bugs)"
	@echo "  make test-env            Test environment variable handling (regression test)"
	@echo "  make test-env-regression Run specific regression test for TAURI_CONFIG_FLAG bug"
	@echo ""
	@echo "Local Testing (PRIMARY STRATEGY):"
	@echo "  make test-local          List all available CI scripts"
	@echo "  make test-script SCRIPT=<name>  Test a specific CI script"
	@echo ""
	@echo "Optional Tools:"
	@echo "  make setup-act           Install Act (LIMITED VALUE - see warning)"
	@echo ""
	@echo "Examples:"
	@echo "  make test-script SCRIPT=generate_and_verify_config.sh"
	@echo "  make validate-paths      # Check script paths before pushing"
	@echo "  make test-env            # Test env var handling (prevents 'parameter null' errors)"
	@echo "  make test-env-regression # Verify TAURI_CONFIG_FLAG fix (2026-01-01 bug)"
	@echo ""
	@echo "💡 Pre-push checklist:"
	@echo "   make validate-paths     # Catch path bugs"
	@echo "   make test-env           # Catch env var bugs"
	@echo "   make lint               # Catch syntax errors"
	@echo ""
	@echo "  ROSTOC_APP_VARIANT=staging make test-script SCRIPT=stage_and_verify_runtime.sh"
	@echo ""
	@echo "⚠️  Note: Act cannot test build workflows (requires macOS/Windows runners)"
	@echo "   Use direct script testing + native builds in rostoc repo instead."
	@echo ""
	@echo "See docs/LOCAL_CI_TESTING.md for comprehensive guide."
