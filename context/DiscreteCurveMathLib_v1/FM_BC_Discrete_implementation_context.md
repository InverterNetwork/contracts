# Implementation Context

## Assumptions

- the first iteration of the module will use static fees

## Interface

The `FM_BC_Discrete_Redeeming_VirtualSupply` contract will inherit from the following contracts. This section lists the functions defined in these parent contracts and indicates whether they provide a base implementation or if the function must be implemented/overridden by `FM_BC_Discrete_Redeeming_VirtualSupply`.

### 1. `IFundingManager_v1.sol`

All functions are interface declarations and **must be implemented** by `FM_BC_Discrete_Redeeming_VirtualSupply`.

- `token() external view returns (IERC20)`
- `transferOrchestratorToken(address to, uint amount) external`

### 2. `VirtualIssuanceSupplyBase_v1.sol`

**Functions with Base Implementation (can be used or overridden):**

- `supportsInterface(bytes4 interfaceId) public view virtual returns (bool)`
- `getVirtualIssuanceSupply() external view virtual returns (uint)`
- `_addVirtualIssuanceAmount(uint _amount) internal virtual`
- `_subVirtualIssuanceAmount(uint _amount) internal virtual`
- `_setVirtualIssuanceSupply(uint _virtualSupply) internal virtual`

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply`:**

- `setVirtualIssuanceSupply(uint _virtualSupply) external virtual` (Abstract in base)

### 3. `VirtualCollateralSupplyBase_v1.sol`

**Functions with Base Implementation (can be used or overridden):**

- `supportsInterface(bytes4 interfaceId) public view virtual returns (bool)`
- `getVirtualCollateralSupply() external view virtual returns (uint)`
- `_addVirtualCollateralAmount(uint _amount) internal virtual`
- `_subVirtualCollateralAmount(uint _amount) internal virtual`
- `_setVirtualCollateralSupply(uint _virtualSupply) internal virtual`

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply`:**

- `setVirtualCollateralSupply(uint _virtualSupply) external virtual` (Abstract in base)

### 4. `RedeemingBondingCurveBase_v1.sol`

**Functions with Base Implementation (can be used or overridden):**

- `supportsInterface(bytes4 interfaceId) public view virtual override returns (bool)`
- `sellTo(address _receiver, uint _depositAmount, uint _minAmountOut) public virtual`
- `sell(uint _depositAmount, uint _minAmountOut) public virtual`
- `openSell() external virtual onlyOrchestratorAdmin`
- `closeSell() external virtual onlyOrchestratorAdmin`
- `setSellFee(uint _fee) external virtual onlyOrchestratorAdmin`
- `calculateSaleReturn(uint _depositAmount) public view virtual returns (uint redeemAmount)`
- `_sellOrder(address _receiver, uint _depositAmount, uint _minAmountOut) internal virtual returns (uint totalCollateralTokenMovedOut, uint issuanceFeeAmount)`
- `_sellingIsEnabledModifier() internal view`
- `_setSellFee(uint _fee) internal virtual`

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply`:**

- `getStaticPriceForSelling() external view virtual returns (uint)` (Abstract in base)
- `_redeemTokensFormulaWrapper(uint _depositAmount) internal view virtual returns (uint)` (Abstract in base)
- `_handleCollateralTokensAfterSell(address _receiver, uint _collateralTokenAmount) internal virtual` (Abstract in base)

_(Note: `RedeemingBondingCurveBase_v1` inherits from `BondingCurveBase_v1`, which may contain other functions not listed here if they are not directly overridden or made abstract in `RedeemingBondingCurveBase_v1` itself. This list focuses on functions explicitly present or declared abstract in the specified inheritance chain.)_
