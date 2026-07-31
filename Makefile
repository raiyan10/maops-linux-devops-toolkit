SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: help validate lint check-executable quality test run cli-help clean

help:
	@echo "MAOps Linux DevOps Toolkit"
	@echo
	@echo "Available targets:"
	@echo "  validate          Validate Bash syntax"
	@echo "  lint              Run ShellCheck"
	@echo "  check-executable  Verify Git executable modes"
	@echo "  test              Run the Bats test suite"
	@echo "  quality           Run all quality checks (validate, lint, check-executable, test)"
	@echo "  run               Run 'maops system info'"
	@echo "  cli-help          Run 'maops --help'"
	@echo "  clean             Remove generated temporary files"

validate:
	@echo "Validating Bash syntax..."
	@find scripts templates bin -type f \( -name '*.sh' -o -name 'maops' \) -print0 \
		| xargs -0 -r -n 1 bash -n
	@echo "Bash syntax validation passed."

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "ShellCheck is not installed."; \
		exit 1; \
	}
	@echo "Running ShellCheck..."
	@find scripts templates bin -type f \( -name '*.sh' -o -name 'maops' \) -print0 \
		| xargs -0 -r shellcheck
	@echo "ShellCheck passed."

check-executable:
	@echo "Checking Git executable modes..."
	@missing="$$(git ls-files -s \
		| awk '($$4 ~ /\.sh$$/ || $$4 == "bin/maops") && $$1 != "100755" {print $$4}')"; \
	if [[ -n "$$missing" ]]; then \
		echo "These tracked shell files are not executable:"; \
		printf '%s\n' "$$missing"; \
		exit 1; \
	fi
	@echo "Executable-mode validation passed."

test:
	@command -v bats >/dev/null 2>&1 || { \
		echo "Bats is not installed."; \
		exit 1; \
	}
	@echo "Running Bats tests..."
	@find tests -type f -name '*.bats' -print0 | xargs -0 -r bats
	@echo "Bats tests passed."

quality: validate lint check-executable test
	@echo "All repository quality checks passed."

run:
	@./bin/maops system info

cli-help:
	@./bin/maops --help

clean:
	@find . -type f \( -name '*.tmp' -o -name '*.log' \) -delete
	@echo "Generated temporary files removed."
