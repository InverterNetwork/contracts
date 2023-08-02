# Script to deploy Inverter Base Contracts

# - OrchestratorFactory
forge script script/factories/DeployOrchestratorFactory.s.sol:DeployOrchestratorFactory \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ModuleFactory
forge script script/factories/DeployModuleFactory.s.sol:DeployModuleFactory \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Orchestrator
forge script script/orchestrator/DeployOrchestrator.s.sol:DeployOrchestrator \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ListAuthorizer
forge script script/modules/governance/DeployListAuthorizer.s.sol:DeployListAuthorizer \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - SingleVoteGovernance
forge script script/modules/governance/DeploySingleVoteGovernor.s.sol:DeploySingleVoteGovernor \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - MilestoneManager
forge script script/modules/DeployMilestoneManager.s.sol:DeployMilestoneManager \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - PaymentManager
forge script script/modules/DeployPaymentProcessor.s.sol:DeployPaymentProcessor \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Beacon
forge script script/proxies/DeployBeacon.s.sol:DeployBeacon \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast
