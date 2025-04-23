# Inverter Protocol: Workflow Deployment Guide

## Introduction

This document provides instructions for deploying workflows within the Inverter Protocol. It outlines the necessary steps and environment variable configurations for successful deployment.

---

## Yield Bearing Stable Token Workflow

Follow these steps to deploy the Yield Bearing Stable Token workflow:

1.  **Prepare Environment File:**
    *   Duplicate the example environment file: `dev.yieldBearingStableWorkflow.env`
    *   Rename the duplicated file to: `yieldBearingStableWorkflow.env` (removing the `dev.` prefix).

2.  **Configure Deployment Variables:**
    *   Open the new `.env.yieldBearingStableWorkflow` file.
    *   Locate the **Workflow Deployment Parameters** section.
    *   Replace all placeholder/demo values in this section with your actual deployment-specific variables.
    *   Locate the **Etherscan API Keys** section.
    *   Replace the placeholder/demo values to your Etherscan API key.

3.  **Load Environment Variables:**
    *   Source the environment file in your terminal session. This loads the variables you configured in the previous step.
        ```bash
        source script/workflowDeploymentAndSetupScripts/yieldBearingStableWorkflow.env
        ```

4.  **Deploy and Verify the Workflow:**
    *   Execute the deployment script using `forge`. This command performs the deployment, setup, and contract verification.
    *   You will need to provide the following command-line arguments (ensure the corresponding environment variables like `$OPTIMISM_SEPOLIA_RPC_URL`, `$OPTIMISM_ETHERSCAN_API_KEY`, and `$VERIFIER_URL` are set, either from the sourced file or your shell environment):
        *   `--rpc-url`: The RPC endpoint URL for your target blockchain network (e.g., `$OPTIMISM_SEPOLIA_RPC_URL` for Optimism Sepolia).
        *   `--etherscan-api-key`: Your Etherscan API key for the target network (e.g., `$OPTIMISM_ETHERSCAN_API_KEY`).
        *   `--verifier-url`: The Etherscan API URL used for verification on the target network (e.g., `$OPTIMISM_SEPOLIA_ETHERSCAN_URL`).

    *   Run the following command:
        ```bash
        forge script script/workflowDeploymentAndSetupScripts/DeployAndSetupYieldBearingStableWorkflow.s.sol \
          --rpc-url $OPTIMISM_SEPOLIA_RPC_URL \
          -vvv \
          --broadcast \
          --etherscan-api-key $OPTIMISM_ETHERSCAN_API_KEY \
          --verifier-url $OPTIMISM_SEPOLIA_ETHERSCAN_URL \
          --verify
        ```
        *(Note: Replace `$OPTIMISM_SEPOLIA_RPC_URL`, `$OPTIMISM_ETHERSCAN_API_KEY`, and `$OPTIMISM_SEPOLIA_ETHERSCAN_URL` with the actual environment variables containing your specific URLs and key if they differ from the example names.)*

---

### Troubleshooting: Verification Failures

Contract verification can sometimes fail due to intermittent Etherscan issues. If a contract doesn't verify automatically during deployment:

1.  Identify the address (`<CONTRACT_ADDRESS>`) of the contract that failed verification (usually visible in the `forge script` output).
2.  Run the `forge verify-contract` command manually for that specific address:

    ```bash
    forge verify-contract <CONTRACT_ADDRESS> \
      --rpc-url $RPC_URL \
      --etherscan-api-key $ETHERSCAN_API_KEY \
      --verifier-url $VERIFIER_URL \
      --watch
    ```
    *(Ensure you use the same `$RPC_URL`, `$ETHERSCAN_API_KEY`, and `$VERIFIER_URL` values corresponding to the network where the contract was deployed.)*