# Progress: House Protocol

## 1. What Works (Implemented & Tested Functionality)

- **Core Math & Data Structures:**
  - `DiscreteCurveMathLib_v1.sol`: Accurate calculations for purchase/sale returns, reserve for supply, segment validation, supply validation, and finding position for supply.
  - `PackedSegmentLib.sol`: Efficient packing, unpacking, creation, and validation of curve segment data.
- **`FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (Funding Manager):**
  - **Initialization:** Correct setup with issuance token, collateral token, and initial curve segments.
  - **Segment Management:** Setting initial segments (`_setSegments`) and reconfiguring them (`reconfigureSegments`) with admin control and crucial invariance checks (`_calculateReserveForSupply`).
  - **Supply Management:** Setting virtual issuance (`setVirtualIssuanceSupply`) and virtual collateral (`setVirtualCollateralSupply`) supplies with admin control.
  - **Price Information:** `getStaticPriceForBuying()` and `getStaticPriceForSelling()` provide correct current step prices.
  - **Fee-Aware View Functions & Fee Logic Foundation (Step 2.10.1 - Fully Completed):**
    - `ProtocolFeeCache` struct defined in `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
    - `init` function in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` now sets project fees (`buyFee`, `sellFee`) using constants and populates `_protocolFeeCache` with BPS values and treasury addresses from `FeeManager` for buy/sell operations.
    - `calculatePurchaseReturn()` and `calculateSaleReturn()` overridden to use project fees and BPS values from `_protocolFeeCache`.
    - `_getFunctionFeesAndTreasuryAddresses()` overridden to return cached fees from `_protocolFeeCache` for relevant selectors, and fall back to `super` for others.
    - Comprehensive unit tests for all parts of 2.10.1, including `init` fee setup, fee-aware view functions, and the `_getFunctionFeesAndTreasuryAddresses` override, are passing.
  - **Core Mint/Redeem Logic (Wrappers - Pre-Fee Collection):**
    - `_issueTokensFormulaWrapper()` correctly calls `_calculatePurchaseReturn()` (from `DiscreteCurveMathLib_v1`).
    - `_redeemTokensFormulaWrapper()` correctly calls `_calculateSaleReturn()` (from `DiscreteCurveMathLib_v1`).
  - **Token Handling during Mint/Redeem (Pre-Fee Collection):**
    - `_handleCollateralTokensBeforeBuy()`: Correctly transfers collateral from user to FM.
    - `_handleIssuanceTokensAfterBuy()`: Correctly mints issuance tokens to user.
    - `_handleCollateralTokensAfterSell()`: Correctly transfers collateral from FM to user.
  - **Collateral Transfer:** `transferOrchestratorToken()` allows authorized payment clients to withdraw collateral (not affecting virtual supplies).
  - **Inheritance & Interfaces:** Correctly inherits from base contracts and implements required interfaces.

## 2. What's Left to Build

- **`FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`:**
  - **Fee Implementation (Step 2.10 in plan):**
    - **View Functions, Init & Core Fee Logic (2.10.1 - Fully Completed & Tested):**
      - `ProtocolFeeCache` struct defined and used.
      - Project fee constants defined.
      - `init` sets project fees and populates `_protocolFeeCache`.
      - `calculatePurchaseReturn` and `calculateSaleReturn` are overridden to be fee-aware using the struct and project fees.
      - `_getFunctionFeesAndTreasuryAddresses` overridden and tested to return cached fees or fallback to super.
    - **Write Functions (Pending - Remainder of 2.10):** Implement actual fee collection and distribution in `_buyOrder`/`_sellOrder` (or overrides). Ensure `projectCollateralFeeCollected` (inherited from `BondingCurveBase_v1`) is updated. Add tests for these write functions.
    - **Project Fees (Dynamic - Future):** Transition from hardcoded constants to dynamic project fees.
    - **Fee Withdrawal Mechanism (Pending/Verify):** Implement/test `withdrawProjectCollateralFee`.
- **Future Modules (as per `context/Specs.md`):**
  - `DynamicFeeCalculator.sol`: For dynamic calculation of issuance, redemption, and loan origination fees.
  - `LM_PC_Credit_Facility.sol`: Lending facility for users to borrow against $HOUSE.
  - `LM_PC_Shift.sol` / `LM_PC_Elevator.sol`: Specific logic modules for rebalancing/floor-raising if `reconfigureSegments` isn't sufficient or needs a dedicated interface.
  - Full integration with `AUT_Roles.sol` for granular permissions if `onlyOrchestratorAdmin` is too broad for some functions.

## 3. Current Status

- `DiscreteCurveMathLib_v1.sol` and `PackedSegmentLib.sol` are complete and considered stable.
- `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` has its core non-fee-related functionality implemented (up to step 2.9).
- **Step 2.10.1 (Fee Setup, Fee-Aware View Functions, `_getFunctionFeesAndTreasuryAddresses` Override & Tests) is fully implemented and tested.**
- **Current focus:** Implementing fee handling in write functions (`_buyOrder`, `_sellOrder`) (Remainder of step 2.10).

## 4. Known Issues

- No major known bugs in the implemented and tested functionality.
- The `projectCollateralFeeCollected` variable mentioned in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (in `transferOrchestratorToken`) is not yet being incremented as fee collection isn't implemented. This will be addressed during fee implementation.

## 5. Evolution of Project Decisions

- **Initial Math Focus:** Prioritizing the `DiscreteCurveMathLib_v1` ensured a solid mathematical foundation before building the stateful FM.
- **Virtual Supplies:** Adopting `virtualIssuanceSupply` and `virtualCollateralSupply` simplified the core FM logic by separating curve math from direct balance dependencies for calculations.
- **Staged Fee Implementation:** Decision to implement basic hardcoded project fees first, then protocol fees, and finally integrate a full `DynamicFeeCalculator` allows for incremental development and testing.
- **Packed Segments:** Early adoption of bit-packed segments for gas efficiency has been a consistent design choice.
