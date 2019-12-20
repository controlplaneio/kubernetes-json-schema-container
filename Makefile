.ONESHELL:
SHELL := /bin/bash

BATS_PARALLEL_JOBS := $(shell command -v parallel 2>/dev/null && echo '--jobs 20')

.PHONY: all
all: help

.PHONY: test
test: ## acceptance test
	@echo "+ Job: $@"; set -euxo pipefail;
	$(call tf-check)
	test/acceptance/bin/bats/bin/bats \
		$(BATS_PARALLEL_JOBS) \
		test/acceptance/

# ---

.PHONY: help
help: ## parse jobs and descriptions from this Makefile
	@grep -E '^[ a-zA-Z0-9_-]+:([^=]|$$)' $(MAKEFILE_LIST) \
    | grep -Ev '^(help\b[[:space:]]*:|all: help$$)' \
    | sort \
    | awk 'BEGIN {FS = ":.*?##"}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
