# Active Context: House Protocol

## 1. Current Work Focus

- **Primary Task:** Implementation of fee mechanisms within `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
  - According to `context/DiscreteCurveMathLib_v1/FM_BC_Discrete_implementation_plan.md`, this is step "2.10. Fees".
  - Initial phase: Implement project fees using a hardcoded constant.
  - Subsequent phase: Implement protocol fee caching and update logic.
  - Future: Integration with a dedicated `DynamicFeeCalculator` contract.

## 2. Recent Changes & Accomplishments

Based on `context/DiscreteCurveMathLib_v1/FM_BC_Discrete_implementation_plan.md` (up to step 2.9):

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

- **Implement Project Fees (Hardcoded):**
  - Define a constant for project fee percentage/amount in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
  - Modify `_issueTokensFormulaWrapper` and/or `_handleCollateralTokensBeforeBuy` to collect this fee from the collateral paid by the user.
  - Modify `_redeemTokensFormulaWrapper` and/or `_handleCollateralTokensAfterSell` to collect this fee from the collateral returned to the user.
  - Store collected project fees in a dedicated state variable (e.g., `projectCollateralFeeCollected`).
  - Add tests for fee collection during mint and redeem operations.
- **Implement Protocol Fees (Cached):**
  - Logic for caching and updating protocol fees (details to be clarified based on spec for how these are derived/set).
- **Fee Withdrawal Mechanism:** Function for an authorized address to withdraw collected project fees.

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
