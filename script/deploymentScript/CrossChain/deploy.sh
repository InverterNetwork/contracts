#!/bin/bash

export HYP_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Run the hyperlane core deploy command and capture the deployed mailbox address
output=$(hyperlane core deploy --chain anvilchain1 --yes --log pretty)

echo "$output"

# Extract mailbox address from the output
mailbox_address=$(echo "$output" | grep 'mailbox:' | head -1 | sed -E 's/.*mailbox: "([^"]+)".*/\1/')

# Run the hyperlane core deploy command for the second chain
output=$(hyperlane core deploy --chain anvilchain2 --yes --log pretty)

echo "$output"


# Run the forge script and capture output
output=$(forge script script/deploymentScript/CrossChain/01-DeployReceiver.s.sol --rpc-url http://localhost:8546 --broadcast)

# Print the output (optional, for debugging)
echo "$output"

# Extract values
deployer=$(echo "$output" | grep -oE 'Deployer: +0x[0-9a-fA-F]+' | awk '{print $2}')
issuance_token=$(echo "$output" | grep -oE 'Issuance Token: +0x[0-9a-fA-F]+' | awk '{print $3}')
crosschain_token_factory=$(echo "$output" | grep -oE 'CrossChain Token Factory: +0x[0-9a-fA-F]+' | awk '{print $4}')

# Run the workflow script and capture output
workflow_output=$(forge script script/deploymentScript/CrossChain/02-DeployWorkflow.s.sol \
  --rpc-url mainnet \
  --sig "run(address, address)" \
  $mailbox_address $crosschain_token_factory \
  --broadcast)

# Print the output (optional, for debugging)
echo "$workflow_output"

# Extract Funding Manager address from the output
funding_manager=$(echo "$workflow_output" | grep -oE 'Funding Manager: +0x[0-9a-fA-F]+' | awk '{print $3}')
erc20mock_iusd=$(echo "$workflow_output" | grep -oE 'ERC20Mock iUSD: +0x[0-9a-fA-F]+' | awk '{print $3}')

# Print the result
echo "Deployer: $deployer"
echo "Mailbox address: $mailbox_address"
echo "Destination Issuance Token: $issuance_token"
echo "CrossChain Token Factory: $crosschain_token_factory"
echo "ERC20Mock iUSD: $erc20mock_iusd"
echo "Funding Manager: $funding_manager"