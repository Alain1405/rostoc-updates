.PHONY: format lint lint-ci test-local test-script setup-act help

WORKFLOW_FILES := $(shell find .github -name '*.yml' -o -name '*.yaml')

format:
	@[ -z "$(WORKFLOW_FILES)" ] || npx --yes prettier@3 --write $(WORKFLOW_FILES)

lint:
	actionlint

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
	@echo "🐳 Checking Act installation..."
	@if command -v act >/dev/null 2>&1; then \
		echo "✅ Act is already installed: $$(act --version)"; \
	else \
		echo "📦 Installing Act..."; \
		brew install act; \
	fi
	@echo ""
	@echo "🔧 Checking Docker..."
	@if docker ps >/dev/null 2>&1; then \
		echo "✅ Docker is running"; \
	else \
		echo "⚠️  Docker is not running. Please start Docker Desktop."; \
		echo "   Or install Colima: brew install colima && colima start"; \
	fi
	@echo ""
	@if [ ! -f .actrc ]; then \
		echo "📝 Creating .actrc from template..."; \
		cp .actrc.template .actrc; \
		echo "✅ .actrc created. Edit it to customize Act settings."; \
	else \
		echo "✅ .actrc already exists"; \
	fi
	@echo ""
	@if [ ! -f .secrets ]; then \
		echo "📝 Creating .secrets from template..."; \
		cp .secrets.template .secrets; \
		echo "✅ .secrets created. Edit it with real or fake values for testing."; \
	else \
		echo "✅ .secrets already exists"; \
	fi
	@echo ""
	@echo "🎉 Setup complete! Try running:"
	@echo "   make test-local                    # List available scripts"
	@echo "   make test-script SCRIPT=<name>     # Test a specific script"
	@echo "   act -l                             # List available workflows"

help:
	@echo "Rostoc Updates - Local CI Testing Commands"
	@echo ""
	@echo "Linting & Formatting:"
	@echo "  make format              Format workflow YAML files with Prettier"
	@echo "  make lint                Lint workflows with actionlint"
	@echo "  make lint-ci             Lint workflows with colored output (CI mode)"
	@echo ""
	@echo "Local Testing:"
	@echo "  make test-local          List all available CI scripts"
	@echo "  make test-script SCRIPT=<name>  Test a specific CI script"
	@echo "  make setup-act           Install and configure Act for workflow testing"
	@echo ""
	@echo "Examples:"
	@echo "  make test-script SCRIPT=generate_and_verify_config.sh"
	@echo "  ROSTOC_APP_VARIANT=staging make test-script SCRIPT=stage_and_verify_runtime.sh"
	@echo "  act -l                   # List workflows (requires setup-act)"
	@echo "  act -W .github/workflows/setup.yml -n  # Dry-run setup workflow"
	@echo ""
	@echo "See docs/LOCAL_CI_TESTING.md for comprehensive guide."
