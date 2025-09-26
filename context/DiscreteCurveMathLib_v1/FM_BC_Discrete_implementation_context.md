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

### 5. `FM_BC_Discrete_Redeeming_VirtualSupply_v1` Specific Functions

The `FM_BC_Discrete_Redeeming_VirtualSupply_v1` contract will implement the following key functions, which are central to its role in managing the discrete bonding curve:

- `reconfigureSegments(PackedSegment[] memory newSegments) external`: This function allows an authorized entity to update the curve's segment configuration. It includes an invariance check to ensure the new curve shape is consistent with the current virtual collateral supply.
  - **Note on Collateral Management**: Unlike previous designs, this function does not directly handle collateral token transfers (injection or withdrawal). Collateral injection is achieved by directly transferring tokens to the FM contract and then updating the `virtualCollateralSupply` via `setVirtualCollateralSupply`. Collateral withdrawal is achieved by calling `transferOrchestratorToken` and subsequently updating `virtualCollateralSupply` via `setVirtualCollateralSupply`.

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

## Fees

There are two types of fees: protocol fees and project fees.

Both are used in

A) read functions: `calculatePurchaseReturn` (`BondingCurveBase_v1.sol`) and `calculateSaleReturn` (`RedeemingBondingCurveBase_v1.sol`)

B) write functions: as well as in the buy and sell functions.

### Read Functions: Status Quo

#### Protocol Fees

- is retrieved from the `FeeManager` contract via `_getFunctionFeesAndTreasuryAddresses` defined in `src/modules/fundingManager/bondingCurve/abstracts/BondingCurveBase_v1.sol`
- relies on `src/modules/base/Module_v1.sol`
- `_getFunctionFeesAndTreasuryAddresses` is virtual function and can be overriden in the child contracts

#### Project Fees

- `buyFee` is state var on `src/modules/fundingManager/bondingCurve/abstracts/BondingCurveBase_v1.sol`
- `sellFee` is state var on `src/modules/fundingManager/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol`

### Read Functions: New Expected Behavior

#### Project Fees

- in `BondingCurveBase_v1.sol` and `RedeemingBondingCurveBase_v1.sol` we add two new getters: `_getBuyFee()` and `_getSellFee()`
- these should return the state variables `buyFee` and `sellFee` respectively
- they should be virtual functions

- in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` we override the two new getters
- for now they are supposed to return the hardcoded constant `PROJECT_BUY_FEE_BPS` and `PROJECT_SELL_FEE_BPS` respectively

#### Protocol Fees

Implementation:

- in `init` get protocol fees & treasury address from `FeeManager` via calling the inherited `_getFunctionFeesAndTreasuryAddresses` (via super)
- store issuance fee and collateral fee in state
- override `_getFunctionFeesAndTreasuryAddresses` to retrieve cached values so that the default call that happens within `calculatePurchaseReturn` and `calculateSaleReturn` uses cached values
- update logic triggered when project fees are withdrawn

Tests:

- init gets protocol fees and treasury address from `FeeManager` and stores in state
- overriden `_getFunctionFeesAndTreasuryAddresses` retrieves correct protocol fees and treasury addresses from `_protocolFeeCache` struct.

##### Test Setup:

You're absolutely right to focus on how the `FeeManager_v1` needs to be configured in our tests. Based on its implementation:

**Key `FeeManager_v1` Configuration Points for Our Tests:**

1.  **Workflow Treasury:** The `FeeManager` uses a single treasury address per `workflow` (our `_orchestrator` address). This treasury will receive both collateral and issuance protocol fees.

    - **Test Action:** We'll call `feeManager.setWorkflowTreasury(address(_orchestrator), designatedProtocolTreasury);` where `designatedProtocolTreasury` is an address we define for testing.
    - Our FM's cached `_protocolCollateralTreasury` and `_protocolIssuanceTreasury` will both point to this `designatedProtocolTreasury`.

2.  **Workflow-Specific Fees:** Fees are set based on a combination of `workflow` (Orchestrator), `module` (our FM's address), and `functionSelector`.
    - **For Buy Operations (using `_buyOrder` selector):**
      - `feeManager.setCollateralWorkflowFee(address(_orchestrator), address(fm), buyOrderSelector, true, collateralBuyFeeBps);`
      - `feeManager.setIssuanceWorkflowFee(address(_orchestrator), address(fm), buyOrderSelector, true, issuanceBuyFeeBps);`
    - **For Sell Operations (using `_sellOrder` selector):**
      - `feeManager.setIssuanceWorkflowFee(address(_orchestrator), address(fm), sellOrderSelector, true, issuanceSellFeeBps);`
      - `feeManager.setCollateralWorkflowFee(address(_orchestrator), address(fm), sellOrderSelector, true, collateralSellFeeBps);`

**In the `init` function of our `FM_BC_Discrete_Redeeming_VirtualSupply_v1`:**
When `_getFunctionFeesAndTreasuryAddresses(buyOrderSelector)` is called:

- It will fetch the `collateralBuyFeeBps` and `issuanceBuyFeeBps` we set above.
- It will fetch the `designatedProtocolTreasury` for both collateral and issuance treasuries.
  These will be stored in our FM's private state variables: `_protocolCollateralFeeBuyBps`, `_protocolIssuanceFeeBuyBps`, `_protocolCollateralTreasury`, and `_protocolIssuanceTreasury`.

Similarly, when `_getFunctionFeesAndTreasuryAddresses(sellOrderSelector)` is called:

- It will fetch the `issuanceSellFeeBps` and `collateralSellFeeBps`.
- It will again fetch the `designatedProtocolTreasury`.
  These will be stored in `_protocolIssuanceFeeSellBps` and `_protocolCollateralFeeSellBps`. The treasury addresses would re-confirm the same `designatedProtocolTreasury`.

**Test Implementation:**
Our test setup for `FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol` will involve:

1.  Ensuring a `FeeManager` instance is deployed and its owner is the test contract (or we can `prank` its owner).
2.  Before calling `fm.init()`, or before the specific test logic that relies on these fees:
    - Call `feeManager.setWorkflowTreasury(...)` once.
    - Call `feeManager.setCollateralWorkflowFee(...)` and `feeManager.setIssuanceWorkflowFee(...)` for the `_buyOrder` selector with desired BPS values.
    - Call `feeManager.setCollateralWorkflowFee(...)` and `feeManager.setIssuanceWorkflowFee(...)` for the `_sellOrder` selector with desired BPS values.
3.  Then, proceed with testing `init` (to check if fees are cached correctly in the FM) and `calculatePurchaseReturn`/`calculateSaleReturn` (to check if they use these cached fees).

This approach allows precise control over the protocol fee environment for our FM contract during testing. This understanding is now integrated into my plan for implementing and testing step 2.10.1.

Are we aligned on this FeeManager configuration strategy for the tests?

### Write functions: Status Quo (`_buyOrder`, `_sellOrder`)

This section outlines how fees are processed during the actual state-changing buy and sell operations, which complements the fee considerations for the read functions (`calculatePurchaseReturn`, `calculateSaleReturn`).

**Core Mechanisms (Leveraging Base Contract Logic):**

The primary fee processing logic resides within the `_buyOrder` (from `BondingCurveBase_v1`) and `_sellOrder` (from `RedeemingBondingCurveBase_v1`) internal functions. These functions orchestrate fee deduction and distribution.

1.  **Fee Inputs:**

    - **Project Fees:** The `buyFee` and `sellFee` state variables (which, in `FM_BC_Discrete_Redeeming_VirtualSupply_v1`, will be initialized from hardcoded constants like `PROJECT_BUY_FEE_BPS` and `PROJECT_SELL_FEE_BPS`).
    - **Protocol Fees:** The cached protocol fee percentages (e.g., `_protocolCollateralFeeBps`, `_protocolIssuanceFeeBps`) and treasury addresses (e.g., `_protocolCollateralTreasury`, `_protocolIssuanceTreasury`) stored as state variables in `FM_BC_Discrete_Redeeming_VirtualSupply_v1` after being fetched from the `FeeManager` during `init`.

2.  **Calculation (`_calculateNetAndSplitFees`):**

    - This crucial helper function (from `BondingCurveBase_v1`) is used to determine the net amount after fees and the individual amounts for protocol and project fees. It's applied sequentially:
      - First to the primary token being deposited/exchanged (e.g., collateral for a buy, issuance for a sell).
      - Then to the token being received before fees (e.g., gross issuance tokens for a buy, gross collateral for a sell).

3.  **Processing Steps (Conceptual for a Buy Operation):**

    - The user's incoming collateral (`_depositAmount`) is processed by `_calculateNetAndSplitFees` using the project `buyFee` and the cached protocol `collateralBuyFeePercentage`. This yields:
      - `netDeposit`: Collateral used for the actual purchase via `_issueTokensFormulaWrapper`.
      - `collateralProtocolFeeAmount`: Protocol fee taken from collateral.
      - `projectFeeAmount`: Project fee taken from collateral.
    - The `_issueTokensFormulaWrapper` calculates the gross `issuanceTokenAmount` based on `netDeposit`.
    - This gross `issuanceTokenAmount` is then processed by `_calculateNetAndSplitFees` using the cached protocol `issuanceBuyFeePercentage` (project fee on issuance is typically 0). This yields:
      - Net `issuanceTokenAmount`: Tokens the user actually receives.
      - `issuanceProtocolFeeAmount`: Protocol fee taken from issuance tokens.
    - A similar two-stage fee deduction applies to sell operations.

4.  **Fee Distribution & Accounting:**
    - **Project Fees (Collateral):** The `projectFeeAmount` (collateral) is accounted for. In `FM_BC_Discrete_Redeeming_VirtualSupply_v1`, this will involve incrementing a dedicated state variable like `projectCollateralFeeCollected`. The base `_projectFeeCollected` hook in `BondingCurveBase_v1` can be leveraged or overridden if necessary.
    - **Protocol Fees:**
      - `collateralProtocolFeeAmount` is transferred to the `_protocolCollateralTreasury` (via `_processProtocolFeeViaTransfer`).
      - `issuanceProtocolFeeAmount` is minted directly to the `_protocolIssuanceTreasury` (via `_processProtocolFeeViaMinting`).
