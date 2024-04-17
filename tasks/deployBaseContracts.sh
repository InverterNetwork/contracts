# Script to deploy Inverter Base Contracts

# - OrchestratorFactory_v1
forge script script/factories/DeployOrchestratorFactory_v1.s.sol:DeployOrchestratorFactory_v1 \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ModuleFactory_v1
forge script script/factories/DeployModuleFactory_v1.s.sol:DeployModuleFactory_v1 \
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

# - PaymentManager
forge script script/modules/DeployPaymentProcessor.s.sol:DeployPaymentProcessor \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Beacon
forge script script/proxies/DeployInverterBeacon_v1.s.sol:DeployInverterBeacon_v1 \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast
