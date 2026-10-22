# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#                          Inverter Network Makefile
#
# WARNING: This file is part of the git repo. DO NOT INCLUDE SENSITIVE DATA!
#
# The Inverter Network smart contracts project uses this Makefile to execute 
# common tasks.
#
# The Makefile supports a help command, i.e. `make help`.
#
# Expected enviroment variables are defined in the `dev.env` file.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# This loads in the dev.env as the environment

ifneq (,$(wildcard ./dev.env))
    include dev.env
    export
endif

# -----------------------------------------------------------------------------
# Common
.PHONY: clean
clean: # Remove build artifacts
	@forge clean

.PHONY: install
install: # Installs the required dependencies
	@forge install

.PHONY: build
build: # Build project
	@forge build

.PHONY: list-size
list-size: # Print the size of contracts
	@{ \
	trap 'mv .test/ test/; mv .script/ script/; mv .templates/ src/templates/' EXIT; \
	mv test/ .test/; \
	mv script/ .script/; \
	mv src/templates/ .templates/; \
	forge build --sizes; \
	}

.PHONY: check-size
check-size: # Checks the size of contracts
	@{ \
	trap 'mv .test/ test/; mv .script/ script/; mv .templates/ src/templates/' EXIT; \
	mv test/ .test/; \
	mv script/ .script/; \
	mv src/templates/ .templates/; \
	forge build --sizes | awk '!/----/ && /-[0-9]+/ { print; FOUND=1} END { if (!FOUND) { print "All contracts within the limit."; exit 0 }; if (FOUND) { exit 1 } }'; \
	}

.PHONY: update
update: # Update dependencies
	@forge update

.PHONY: test
test: # Run whole test suite
	@forge test -vvv

.PHONY: testFuzz
testFuzz: # Run whole test suite with a custom amount of fuzz runs
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" -ge 1 ] 2>/dev/null; then \
		export FOUNDRY_FUZZ_RUNS=$(filter-out $@,$(MAKECMDGOALS)); \
	else \
		read -p "Fuzz runs (no input = defaults to 1024): " RUNS; \
		export FOUNDRY_FUZZ_RUNS=$$(if [ "$$RUNS" -ge 1 ] 2>/dev/null; then echo $$RUNS; else echo 1024; fi); \
	fi; \
	if [ $$FOUNDRY_FUZZ_RUNS -gt 1024 ]; then \
		export FOUNDRY_FUZZ_MAX_TEST_REJECTS=$$((FOUNDRY_FUZZ_RUNS * 50)); \
	else \
		export FOUNDRY_FUZZ_MAX_TEST_REJECTS=65536; \
	fi; \
	echo "Running tests with $${FOUNDRY_FUZZ_RUNS} fuzz runs and $${FOUNDRY_FUZZ_MAX_TEST_REJECTS} accepted test rejections..."; \
	forge test -vvv

# -----------------------------------------------------------------------------
# Individual Component Tests

.PHONY: testOrchestrator
testOrchestrator: # Run orchestrator/ package tests
	@make pre-test
	@forge test -vvv --match-path "*/orchestrator/*"

.PHONY: testModules
testModules: # Run modules/ package tests
	@make pre-test
	@forge test -vvv --match-path "*/modules/*"

.PHONY: testFactories
testFactories: # Run factories/ package tests
	@make pre-test
	@forge test -vvv --match-path "*/factories/*"

.PHONY: testE2e
testE2e: # Run e2e test suite
	@make pre-test
	@forge test -vvv --match-path "*/e2e/*"

.PHONY: testScripts
testScripts: # Run e2e test suite
	@echo "### Run scripts"

	@echo "Run TestnetDeploymentScript"
	@forge script script/deploymentScript/TestnetDeploymentScript.s.sol:TestnetDeploymentScript 

# -----------------------------------------------------------------------------
# Static Analyzers

.PHONY: analyze-slither
analyze-slither: # Run slither analyzer against project (requires solc-select)
	@forge build --extra-output abi --extra-output userdoc --extra-output devdoc --extra-output evm.methodIdentifiers
	@solc-select use 0.8.23
	@slither --ignore-compile src/common      || \
	slither --ignore-compile src/external     || \
	slither --ignore-compile src/factories    || \
	slither --ignore-compile src/modules      || \
	slither --ignore-compile src/orchestrator || \
	slither --ignore-compile src/proxies

.PHONY: analyze-c4udit
analyze-c4udit: # Run c4udit analyzer against project
	@c4udit src

# -----------------------------------------------------------------------------
# Reports

.PHONY: report-gas
report-gas: # Print gas report
	@forge test --gas-report

.PHONY: report-cov
report-cov: # Print coverage report
	@echo "### Running tests & generating the coverage report..."
	@forge coverage --report lcov
	@genhtml lcov.info --branch-coverage --output-dir coverage
	@forge snapshot

# -----------------------------------------------------------------------------
# Formatting

.PHONY: fmt
fmt: # Format code
	@forge fmt

.PHONY: fmt-check
fmt-check: # Check whether code formatted correctly
	@forge fmt --check

# -----------------------------------------------------------------------------
# Git

pre-test: # format and export correct data
	@echo "### Formatting..."
	@forge fmt

	@echo "### Env variables to make sure the local tests runs"
	@echo "### equally long compared to the CI tests"
	@export FOUNDRY_FUZZ_RUNS=1024
	@export FOUNDRY_FUZZ_MAX_TEST_REJECTS=65536

.PHONY: pre-commit
pre-commit: # Git pre-commit hook
	@echo "### Checking the contract size"
	@make check-size
	
	@echo "### Running the scripts"
	@make testScripts

	@echo "### Configure tests"
	@make pre-test

	@echo "### Running the tests"
	@forge test

# -----------------------------------------------------------------------------
# Help Command

.PHONY: help
help: # Show help for each of the Makefile recipes
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done
