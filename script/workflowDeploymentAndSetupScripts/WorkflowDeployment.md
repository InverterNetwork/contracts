# Inverter Protocol: Workflow Deployment Guide

## Introduction

This document provides instructions for deploying workflows within the Inverter Protocol. It outlines the necessary steps and environment variable configurations for successful deployment.

---

## Yield Bearing Stable Token Workflow

Follow these steps to deploy the Yield Bearing Stable Token workflow:

1.  **Prepare Environment File:**
    *   Duplicate the example environment file: `example.dev.navBasedPimWorkflow.env`
    *   Rename the duplicated file to: `dev.navBasedPimWorkflow.env` (removing the `example.` prefix).

2.  **Configure Deployment Variables:**
    *   Open the new `.env.navBasedPimWorkflow` file.
    *   Locate the **Workflow Deployment Parameters** section.
    *   Replace all placeholder/demo values in this section with your actual deployment-specific variables.
    *   Locate the **Etherscan API Keys** section.
    *   Replace the placeholder/demo values to your Etherscan API key.

3.  **Load Environment Variables:**
    *   Source the environment file in your terminal session. This loads the variables you configured in the previous step.
        ```bash
        source script/workflowDeploymentAndSetupScripts/dev.navBasedPimWorkflow.env
        ```

4.  **Deploy and Verify the Workflow:**
    *   Run the deployment and verification using the following `forge` command. This command will deploy the contracts, perform setup, and attempt contract verification on Etherscan:
        *   `--rpc-url`: The RPC endpoint for your target network (e.g., `$SEPOLIA_RPC_URL` for Sepolia).
        *   `-vvv`: Enables verbose output for detailed logs.
        *   `--broadcast`: Broadcasts the transactions to the network.
        *   `--etherscan-api-key`: Your Etherscan API key for the target network (e.g., `$ETHERSCAN_API_KEY`).
        *   `--verify`: Enables contract verification after deployment.
        *   `--verifier etherscan`: Specifies Etherscan as the verification service.
        *   `--chain sepolia`: Specifies the target chain (e.g., Sepolia).
    *   Run the following command:
        ```bash
        forge script script/workflowDeploymentAndSetupScripts/DeployAndSetupNavBasedPimWorkflow.s.sol \
          --rpc-url $SEPOLIA_RPC_URL \
          -vvv \
          --broadcast \
          --etherscan-api-key $ETHERSCAN_API_KEY \
          --verify \
          --verifier etherscan \
          --chain sepolia
        ```
    *   *(If you are deploying to a different network, update the environment variables, `--chain` argument, and replace `$SEPOLIA_RPC_URL` with the appropriate environment variables for your specific network and keys.)*

---

### Troubleshooting: Verification Failures

Contract verification can sometimes fail due to intermittent Etherscan issues. If a contract doesn't verify automatically during deployment:

1.  Identify the address (`<CONTRACT_ADDRESS>`) of the contract that failed verification (usually visible in the `forge script` output).
2.  Run the `forge verify-contract` command manually for that specific address. Below is an example for Sepolia:

    ```bash
    forge verify-contract <CONTRACT_ADDRESS> \
      --rpc-url $SEPOLIA_RPC_URL \
      --etherscan-api-key $ETHERSCAN_API_KEY \
      --verifier etherscan \
      --chain sepolia \
      --watch
    ```
    *(Ensure you use the same `$RPC_URL`, `$ETHERSCAN_API_KEY`, and `chain` values corresponding to the network where the contract was deployed.)*