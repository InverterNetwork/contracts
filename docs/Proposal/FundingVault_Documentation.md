# FundingVault.sol

## Things to know

1. **Subject to change:** The FundingVault is an [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) vault managing the accounting for funder deposits.
2. After funding a particular proposal, the depositors receive newly minted ERC20 receipt tokens (similar to the concept of LP tokens) that represent their funding.
3. These receipt tokens can be burned to receive back the funding, in proportion of available funds.

**All functions defined in FundingVault.sol are internal and hence cannot be interacted with, externally.**

4. The default public/external functions available from [OpenZeppelin's implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol) of ERC-4626 are open-sourced and if you want to, you can refer to the code to get an idea of how to interact with the ERC-4626 public/external functions.