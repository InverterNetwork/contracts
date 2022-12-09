# Script to deploy Inverter Base Contracts

# - ProposalFactory
forge script scripts/DeployProposalFactory.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ModuleFactory
forge script scripts/DeployModuleFactory.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Proposal
forge script scripts/DeployProposal.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - ListAuthorizer
forge script scripts/DeployListAuthorizer.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - SingleVoteGovernance
forge script scripts/DeploySingleVoteGovernance.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - MilestoneManager
forge script scripts/DeployMilestoneManager.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - PaymentManager
forge script scripts/DeployPaymentManager.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast

# - Beacon
forge script scripts/DeployBeacon.s.sol \
    --rpc-url $RPC_URL \
    --sender $WALLET_DEPLOYER \
    --private-key $WALLET_DEPLOYER_PK \
    --broadcast
