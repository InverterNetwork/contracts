# How to run DeploymentScript.s.sol

0. Create a .env file at the root of your project if it doesn't already exist.
1. Paste the following values in your `.env` file:
```
ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PPBO_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
MMBO_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
ABO_PRIVATE_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
PROPOSAL_OWNER_PRIVATE_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
```
2. Open a tab in your terminal
3. Run the following command: `anvil`
4. Open another tab in your terminal
5. Run the following command:
`forge script scripts/deployment/DeploymentScript.s.sol --fork-url http://localhost:8545/ --broadcast`
