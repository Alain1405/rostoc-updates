.PHONY: format lint lint-ci

WORKFLOW_FILES := $(shell find .github -name '*.yml' -o -name '*.yaml')

format:
	@[ -z "$(WORKFLOW_FILES)" ] || npx --yes prettier@3 --write $(WORKFLOW_FILES)

lint:
	actionlint

lint-ci:
	actionlint -color -shellcheck shellcheck
