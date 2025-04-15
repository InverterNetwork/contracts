# Prerequisites

## Install Hyperlane

https://docs.hyperlane.xyz/docs/reference/cli

```
npm install -g @hyperlane-xyz/cli
```

# Anvil Chain #1
```
anvil --port 8545 --chain-id 31337
```

# Anvil Chain #2
```
anvil --port 8546 --chain-id 31338
```

# Initialize Chains for Hyperlane
Let's create a custom chain config, run on both Anvil chains (anvilchain1, anvilchain2):

```
hyperlane registry init
```

Next, let's configure, deploy and test your custom chains core contracts.

From your local environment, set the private key or seed phrase of your funded deployer address to `HYP_KEY`. For example: `export HYP_KEY='<YOUR_PRIVATE_KEY>'`

```
export HYP_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Hyperlane Core components needs to be initialized

```
hyperlane core init
```

# Deploy

Run batch script to deploy contracts on both chains

```
bash script/deploymentScript/CrossChain/deploy.sh 
```

Then Run relayer in another terminal window

```
export HYP_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
hyperlane relayer --chains anvilchain1,anvilchain2 --verbosity trace
```

# Run

Inverter protocol, hyperlane core components are ready to be tested

You can run minting on anvilchain1 and it will trigger minting on destination chain anvilchain2.
You can check the balance on anvilchain2.

```
forge script script/deploymentScript/CrossChain/04-Mint.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/05-CheckDestination.s.sol --rpc-url http://localhost:8546 --broadcast
```

# Reference

Following commands are here as reference;

```
hyperlane core deploy --chain anvilchain1 --yes --log pretty
hyperlane core deploy --chain anvilchain2 --yes --log pretty

forge script script/deploymentScript/CrossChain/01-DeployReceiver.s.sol --rpc-url http://localhost:8546 --broadcast

forge script script/deploymentScript/CrossChain/02-DeployWorkflow.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/03-Mint.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/04-CheckDestination.s.sol --rpc-url http://localhost:8546 --broadcast
```