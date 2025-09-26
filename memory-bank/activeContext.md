# Active Context: House Protocol

## 1. Current Work Focus

- **Primary Task:** Implementation of fee mechanisms within `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (Step 2.10 in `FM_BC_Discrete_implementation_plan.md`).
  - **Completed Sub-Task (2.10.1):** Fee setup in `init`, fee-aware `calculatePurchaseReturn`/`calculateSaleReturn` (using `ProtocolFeeCache`), and override of `_getFunctionFeesAndTreasuryAddresses` to use cached fees. All associated tests for 2.10.1 are passing.
  - **Next Sub-Task (Remainder of 2.10):** Implementing actual fee collection and distribution in write functions (`_buyOrder`, `_sellOrder`) and updating `projectCollateralFeeCollected`.
  - Future: Integration with a dedicated `DynamicFeeCalculator` contract.

## 2. Recent Changes & Accomplishments

**Fee Implementation (Step 2.10.1 - Fully Completed):**

- Defined `ProtocolFeeCache` struct in `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
- In `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`:
  - Added `PROJECT_BUY_FEE_BPS` and `PROJECT_SELL_FEE_BPS` constants.
  - Used `ProtocolFeeCache private _protocolFeeCache;` for storing protocol fee data.
  - Updated `__FM_BC_Discrete_Redeeming_VirtualSupply_v1_Init` to:
    - Set `buyFee` and `sellFee` state variables.
    - Populate `_protocolFeeCache` from `FeeManager` for buy/sell selectors.
  - Overridden `calculatePurchaseReturn` and `calculateSaleReturn` to use `_protocolFeeCache` and project fees.
  - **Overridden `_getFunctionFeesAndTreasuryAddresses` to return values from `_protocolFeeCache` for relevant selectors, falling back to `super` for others.**
- **Testing for 2.10.1:**
  - Unit tests in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol` now verify: - Correct initialization of `buyFee`, `sellFee`, and population of `_protocolFeeCache` in `init`. - Accuracy of overridden `calculatePurchaseReturn` and `calculateSaleReturn` with fees. - **Correct behavior of overridden `_getFunctionFeesAndTreasuryAddresses` (returning cached values and falling back to super appropriately).**
    All tests for step 2.10.1 are passing.

**Previous Accomplishments (Up to step 2.9):**

- **File Structure & Inheritance:** `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` created with necessary inheritance and overridden functions.
- **Token Initialization:** Issuance and collateral tokens set in `init`.
- **Segment Management:**
  - `_setSegments` internal function implemented and used in `init`.
  - `reconfigureSegments` external function implemented with invariance checks and admin control.
- **Supply Management:**
  - `setVirtualCollateralSupply` and `setVirtualIssuanceSupply` (and their internal counterparts) implemented with admin control.
- **Price Retrieval:** `getStaticPriceForBuying` and `getStaticPriceForSelling` implemented, using `_findPositionForSupply` from `DiscreteCurveMathLib_v1`.
- **Core Formula Wrappers:**
  - `_issueTokensFormulaWrapper` (uses `_calculatePurchaseReturn`).
  - `_redeemTokensFormulaWrapper` (uses `_calculateSaleReturn`).
- **Token Handling Hooks:**
  - `_handleCollateralTokensBeforeBuy` (transfers collateral from provider).
  - `_handleIssuanceTokensAfterBuy` (mints issuance tokens to receiver).
  - `_handleCollateralTokensAfterSell` (transfers collateral to receiver).
- **Orchestrator Token Transfer:** `transferOrchestratorToken` implemented.

## 3. Next Steps

- **Implement Fee Handling in Write Functions (Rest of 2.10):**
  - Modify/Override `_buyOrder` and `_sellOrder` (or ensure base versions work with cached fees) to:
    - Correctly use the `_protocolFeeCache` and project fees.
    - Ensure `_calculateNetAndSplitFees` is applied appropriately.
    - Ensure protocol fees are correctly sent to treasuries (from `_protocolFeeCache.collateralTreasury` / `_protocolFeeCache.issuanceTreasury`).
    - Ensure project fees are correctly accounted for by incrementing the inherited `projectCollateralFeeCollected` state variable.
  - Add tests for actual fee collection and distribution during buy/sell operations.
- **Fee Withdrawal Mechanism:** Implement `withdrawProjectCollateralFee` if not fully covered by base, or test base implementation.

## 4. Active Decisions & Considerations

- **Fee Calculation Point:** Determine the exact point in the mint/redeem flow where fees are calculated and deducted to ensure atomicity and correctness.
- **Rounding for Fees:** How fee amounts are rounded (likely in favor of the protocol).
- **Gas Impact of Fees:** Assess any significant gas increase due to fee calculations.
- **Clarity of Fee Variables:** Naming conventions for fee-related state variables and events.

## 5. Important Patterns & Preferences

- **Virtual Supplies:** Continue to use `virtualIssuanceSupply` and `virtualCollateralSupply` as the primary supply figures for curve math. Actual balances are used for transfers.
- **Invariance:** Maintain strict adherence to collateral backing invariants, especially if fee mechanisms interact with reserve calculations (though typically fees are skimmed from flows).
- **Modularity:** Keep fee logic as contained as possible, anticipating future replacement/enhancement by `DynamicFeeCalculator`.
- **Testing:** Thorough unit tests for all fee-related scenarios, including edge cases.
- **`SafeERC20`:** Use for all token transfers.
- **`FixedPointMathLib`:** Use for precise fee calculations if percentages are involved.

## 6. Learnings & Project Insights

- The separation of math (`DiscreteCurveMathLib_v1`) from stateful logic (`FM_BC_Discrete_Redeeming_VirtualSupply_v1`) has proven effective for clarity and testing.
- The `VirtualIssuanceSupplyBase_v1` and `VirtualCollateralSupplyBase_v1` provide a good foundation for managing these crucial state variables.
- The step-by-step implementation plan is critical for managing complexity.
