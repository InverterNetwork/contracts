# How to run DeploymentScript.s.sol

0. Create a .env file at the root of your project if it doesn't already exist.
1. Paste the values of the `dev.env` in your `.env` file:
2. Adapt the values of the `.env` file to fit your deployment setup.
3. Open a tab in your terminal
4. Run the following command: `anvil`
5. Open another tab in your terminal
6. Run the following command:
   `forge script script/deployment/DeploymentScript.s.sol --fork-url http://localhost:8545/ --broadcast`
7. Access the communityMultisig and call setFeeManager() in the governor contract. Use the address of the newly creatd
