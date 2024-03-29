# How to run DeployLocal.s.sol

0. Create a .env file at the root of your project if it doesn't already exist.
1. Paste the following values in your `.env` file:

```
#DEPLOYER
export DEPLOYER_ADDRESS=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
export DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

2. Open a tab in your terminal
3. Run the following command: `anvil`
4. Open another tab in your terminal
5. Run the following command:
   `forge script script/deployment/DeployLocal.s.sol --fork-url http://localhost:8545/ --broadcast`
