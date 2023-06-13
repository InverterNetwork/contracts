# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#                              Inverter Makefile
#
# WARNING: This file is part of the git repo. DO NOT INCLUDE SENSITIVE DATA!
#
# The Inverter smart contracts project uses this Makefile to execute common
# tasks.
#
# The Makefile supports a help command, i.e. `make help`.
#
# Expected enviroment variables are defined in the `dev.env` file.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# -----------------------------------------------------------------------------
# Common

.PHONY: clean
clean: ## Remove build artifacts
	@forge clean

.PHONY: build
build: ## Build project
	@forge build

.PHONY: update
update: ## Update dependencies
	@forge update

.PHONY: test
test: ## Run whole testsuite
	@forge test -vvv

# -----------------------------------------------------------------------------
# Individual Component Tests

.PHONY: testProposal
testProposal: ## Run proposal/ package tests
	@forge test -vvv --match-path "*/proposal/*"

.PHONY: testModules
testModules: ## Run modules/ package tests
	@forge test -vvv --match-path "*/modules/*"

.PHONY: testFactories
testFactories: ## Run factories/ package tests
	@forge test -vvv --match-path "*/factories/*"

.PHONY: testE2e
testE2e: ## Rune e2e test suite
	@forge test -vvv --match-path "*/e2e/*"

.PHONY: testScripts
testScripts: ## Rune e2e test suite
	
	@forge script script/deployment/DeploymentScript.s.sol

	@forge script script/factories/DeployModuleFactory.s.sol
	@forge script script/factories/DeployProposalFactory.s.sol
	
	@forge script script/modules/governance/DeployListAuthorizer.s.sol
	@forge script script/modules/governance/DeploySingleVoteGovernor.s.sol
	
	@forge script script/modules/paymentProcessor/DeploySimplePaymentProcessor.s.sol
	@forge script script/modules/paymentProcessor/DeployStreamingPaymentProcessor.s.sol

	@forge script script/modules/DeployMilestoneManager.s.sol
	@forge script script/modules/DeployRebasingFundingManager.s.sol

	@forge script script/proposal/DeployProposal.s.sol

	@forge script script/proxies/DeployBeacon.s.sol

	@forge script script/setup/SetupToyProposalScript.s.sol

# -----------------------------------------------------------------------------
# Static Analyzers

.PHONY: analyze-slither
analyze-slither: ## Run slither analyzer against project (requires solc-select)
	@forge build --extra-output abi --extra-output userdoc --extra-output devdoc --extra-output evm.methodIdentifiers
	@solc-select use 0.8.13
	@slither --ignore-compile src/common   || \
	slither --ignore-compile src/factories || \
	slither --ignore-compile src/generated || \
	slither --ignore-compile src/modules   || \
	slither --ignore-compile src/proposal

.PHONY: analyze-c4udit
analyze-c4udit: ## Run c4udit analyzer against project
	@c4udit src

# -----------------------------------------------------------------------------
# Reports

.PHONY: report-gas
report-gas: ## Print gas report
	@forge test --gas-report

.PHONY: report-cov
report-cov: ## Print coverage report
	@forge coverage

# -----------------------------------------------------------------------------
# Formatting

.PHONY: fmt
fmt: ## Format code
	@forge fmt

.PHONY: fmt-check
fmt-check: ## Check whether code formatted correctly
	@forge fmt --check

# -----------------------------------------------------------------------------
# Git

.PHONY: pre-commit
pre-commit: ## Git pre-commit hook
	@forge fmt
	@make testScripts
	@forge coverage --report lcov
	@genhtml lcov.info --branch-coverage --output-dir coverage
	@forge snapshot
	

# -----------------------------------------------------------------------------
# Help Command

.PHONY: help
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
