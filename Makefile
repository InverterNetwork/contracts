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

.PHONY: testFuzz .DEFAULT
.DEFAULT:
	@:
testFuzz: ## Run whole testsuite with a custom amount of fuzz runs
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
testE2e: ## Run e2e test suite
	@forge test -vvv --match-path "*/e2e/*"

.PHONY: testScripts
testScripts: ## Run e2e test suite
	@forge script script/deployment/DeploymentScript.s.sol

	@forge script script/factories/DeployModuleFactory.s.sol
	@forge script script/factories/DeployProposalFactory.s.sol
	
	@forge script script/modules/governance/DeployRoleAuthorizer.s.sol
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
	@solc-select use 0.8.19
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
	@echo "### Formatting..."
	@forge fmt

	@echo "### Running the scripts..."
	@make testScripts

	# Env variables to make sure the local tests runs
	# equally long compared to the CI tests
	@export FOUNDRY_FUZZ_RUNS=1024
	@export FOUNDRY_FUZZ_MAX_TEST_REJECTS=65536

	# Env variables required for the tests
	@export WALLET_DEPLOYER=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
	@export WALLET_DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
	@export DEPLOYMENT_PROPOSAL_FACTORY_TARGET=0x0000000000000000000000000000000000000001
	@export DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY=0x0000000000000000000000000000000000000001
	@export ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
	@export PPBO_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
	@export MMBO_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
	@export FMBO_PRIVATE_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
	@export ABO_PRIVATE_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
	@export PROPOSAL_OWNER_PRIVATE_KEY=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
	@export FUNDER_1_PRIVATE_KEY=0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
	@export DEPLOYMENT_PROPOSAL_FACTORY_TARGET=0x0000000000000000000000000000000000000001
	@export DEPLOYMENT_PROPOSAL_FACTORY_MODULE_FACTORY=0x0000000000000000000000000000000000000002

	@echo "### Running tests & generating the coverage report..."
	@forge coverage --report lcov
	@genhtml lcov.info --branch-coverage --output-dir coverage
	@forge snapshot

# -----------------------------------------------------------------------------
# Help Command

.PHONY: help
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
