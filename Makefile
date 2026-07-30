SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: help validate lint check-executable quality test run clean

help:
	@echo "MAOps Linux DevOps Toolkit"
	@echo
	@echo "Available targets:"
	@echo "  validate          Validate Bash syntax"
	@echo "  lint              Run ShellCheck"
	@echo "  check-executable  Verify Git executable modes"
	@echo "  quality           Run all quality checks"
	@echo "  test              Alias for quality until Bats tests are added"
	@echo "  run               Run the system information utility"
	@echo "  clean             Remove generated temporary files"

validate:
	@echo "Validating Bash syntax..."
	@find scripts templates -type f -name '*.sh' -print0 \
		| xargs -0 -r -n 1 bash -n
	@echo "Bash syntax validation passed."

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "ShellCheck is not installed."; \
		exit 1; \
	}
	@echo "Running ShellCheck..."
	@find scripts templates -type f -name '*.sh' -print0 \
		| xargs -0 -r shellcheck
	@echo "ShellCheck passed."

check-executable:
	@echo "Checking Git executable modes..."
	@missing="$$(git ls-files -s \
		| awk '$$4 ~ /\.sh$$/ && $$1 != "100755" {print $$4}')"; \
	if [[ -n "$$missing" ]]; then \
		echo "These tracked shell files are not executable:"; \
		printf '%s\n' "$$missing"; \
		exit 1; \
	fi
	@echo "Executable-mode validation passed."

quality: validate lint check-executable
	@echo "All repository quality checks passed."

test: quality

run:
	@./scripts/system/system-info.sh

clean:
	@find . -type f \( -name '*.tmp' -o -name '*.log' \) -delete
	@echo "Generated temporary files removed."