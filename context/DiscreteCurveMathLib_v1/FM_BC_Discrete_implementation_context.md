# Implementation Context

## Assumptions

- the first iteration of the module will use static fees

## Interface

The `FM_BC_Discrete_Redeeming_VirtualSupply_v1` contract will inherit from the following contracts. This section lists the functions defined in these parent contracts and indicates whether they provide a base implementation or if the function must be implemented/overridden by `FM_BC_Discrete_Redeeming_VirtualSupply_v1`.

### 1. `IFundingManager_v1.sol`

All functions are interface declarations and **must be implemented** by `FM_BC_Discrete_Redeeming_VirtualSupply_v1`.

- `token() external view returns (IERC20)`
- `transferOrchestratorToken(address to, uint amount) external`

### 2. `VirtualIssuanceSupplyBase_v1.sol`

**Functions with Base Implementation (can be used or overridden):**

- `supportsInterface(bytes4 interfaceId) public view virtual returns (bool)`
- `getVirtualIssuanceSupply() external view virtual returns (uint)`
- `_addVirtualIssuanceAmount(uint _amount) internal virtual`
- `_subVirtualIssuanceAmount(uint _amount) internal virtual`
- `_setVirtualIssuanceSupply(uint _virtualSupply) internal virtual`

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply_v1`:**

- `setVirtualIssuanceSupply(uint _virtualSupply) external virtual` (Abstract in base)

### 3. `VirtualCollateralSupplyBase_v1.sol`

**Functions with Base Implementation (can be used or overridden):**

- `supportsInterface(bytes4 interfaceId) public view virtual returns (bool)`
- `getVirtualCollateralSupply() external view virtual returns (uint)`
- `_addVirtualCollateralAmount(uint _amount) internal virtual`
- `_subVirtualCollateralAmount(uint _amount) internal virtual`
- `_setVirtualCollateralSupply(uint _virtualSupply) internal virtual`

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply_v1`:**

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

**Functions Requiring Implementation by `FM_BC_Discrete_Redeeming_VirtualSupply_v1`:**

- `getStaticPriceForSelling() external view virtual returns (uint)` (Abstract in base)
- `_redeemTokensFormulaWrapper(uint _depositAmount) internal view virtual returns (uint)` (Abstract in base)
- `_handleCollateralTokensAfterSell(address _receiver, uint _collateralTokenAmount) internal virtual` (Abstract in base)

_(Note: `RedeemingBondingCurveBase_v1` inherits from `BondingCurveBase_v1`, which may contain other functions not listed here if they are not directly overridden or made abstract in `RedeemingBondingCurveBase_v1` itself. This list focuses on functions explicitly present or declared abstract in the specified inheritance chain.)_

## Inheritance implementation comparison `FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol`

The `FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol` contract implements the same inheritance chain as `FM_BC_Discrete_Redeeming_VirtualSupply_v1`. Here's how it handles the functions we've been discussing:

### `supportsInterface(bytes4 interfaceId)`

- **Implementation**: It explicitly overrides `VirtualIssuanceSupplyBase_v1`, `VirtualCollateralSupplyBase_v1`, and `RedeemingBondingCurveBase_v1`. It then checks for its own interface (`IFM_BC_Bancor_Redeeming_VirtualSupply_v1`), `IFundingManager_v1`, and calls `super.supportsInterface(interfaceId)`. This confirms our approach of explicitly listing all overridden contracts.

### `getStaticPriceForBuying()`

- **Implementation**: It explicitly overrides `BondingCurveBase_v1` and `IBondingCurveBase_v1`. This confirms the need for explicit overrides when a function is declared in both a base contract and an interface it implements.

### `_handleCollateralTokensBeforeBuy(address _provider, uint _amount)`

- **Implementation**: It uses `__Module_orchestrator.fundingManager().token().safeTransferFrom(_provider, address(this), _amount);` to transfer collateral tokens.

### `_handleIssuanceTokensAfterBuy(address _receiver, uint _issuanceTokenAmount)`

- **Implementation**: It uses `_mint(_receiver, _issuanceTokenAmount);` to mint tokens to the receiver.

### `_issueTokensFormulaWrapper(uint depositAmount_)`

- **Implementation**: It uses `formula.calculatePurchaseReturn(...)` to calculate the mint amount based on the Bancor formula, handling decimal conversions.

### `_redeemTokensFormulaWrapper(uint depositAmount_)`

- **Implementation**: It uses `formula.calculateSaleReturn(...)` to calculate the redeem amount based on the Bancor formula, handling decimal conversions.

### `_handleCollateralTokensAfterSell(address _receiver, uint _collateralTokenAmount)`

- **Implementation**: It uses `token().safeTransfer(_receiver, _collateralTokenAmount);` to transfer collateral tokens to the receiver.

This analysis confirms that our current approach of adding empty `revert("NOT IMPLEMENTED")` functions for all abstract functions in the inheritance chain is correct for the initial setup. The explicit `override(...)` syntax is also validated by this example.
