# Anvil Chain #1
```
anvil --port 8545 --chain-id 31337
```

# Anvil Chain #2
```
anvil --port 8546 --chain-id 31338
```



Let’s create a custom chain config, run on both Anvil chains:

```
hyperlane registry init
```

Next, let’s configure, deploy and test your custom chain’s core contracts.

From your local environment, set the private key or seed phrase of your funded deployer address to `HYP_KEY`. For example: `export HYP_KEY='<YOUR_PRIVATE_KEY>'`

```
export HYP_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

```
hyperlane core init
```

```
hyperlane core deploy
```

You can also run a relayer in the background with

```
hyperlane relayer --chains anvilchain1,anvilchain2 --verbosity trace
```

```
forge script script/deploymentScript/CrossChain/01-DeployWorkflow.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/02-DeployReceiver.s.sol --rpc-url http://localhost:8546 --broadcast

forge script script/deploymentScript/CrossChain/03-TokenBridgeSettings.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/04-Mint.s.sol --rpc-url mainnet --broadcast

forge script script/deploymentScript/CrossChain/05-CheckDestination.s.sol --rpc-url http://localhost:8546 --broadcast
```