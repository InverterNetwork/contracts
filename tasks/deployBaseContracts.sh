# Script to deploy Inverter Base Contracts

# - ProposalFactory
forge script scripts/factories/DeployProposalFactory.s.sol:DeployProposalFactory \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ModuleFactory
forge script scripts/factories/DeployModuleFactory.s.sol:DeployModuleFactory \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Proposal
forge script scripts/proposal/DeployProposal.s.sol:DeployProposal \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ListAuthorizer
forge script scripts/modules/governance/DeployListAuthorizer.s.sol:DeployListAuthorizer \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - SingleVoteGovernance
forge script scripts/modules/governance/DeploySingleVoteGovernor.s.sol:DeploySingleVoteGovernor \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - MilestoneManager
forge script scripts/modules/DeployMilestoneManager.s.sol:DeployMilestoneManager \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - PaymentManager
forge script scripts/DeployPaymentManager.s.sol \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Beacon
forge script scripts/proxies/DeployBeacon.s.sol:DeployBeacon \
    --fork-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast
