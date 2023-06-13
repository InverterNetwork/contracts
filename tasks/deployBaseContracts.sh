# Script to deploy Inverter Base Contracts

# - ProposalFactory
forge script script/factories/DeployProposalFactory.s.sol:DeployProposalFactory \
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

# - Proposal
forge script script/proposal/DeployProposal.s.sol:DeployProposal \
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
