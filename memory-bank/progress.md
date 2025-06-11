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
  - **Core Mint/Redeem Logic (Wrappers):**
    - `_issueTokensFormulaWrapper()` correctly calls `_calculatePurchaseReturn()`.
    - `_redeemTokensFormulaWrapper()` correctly calls `_calculateSaleReturn()`.
  - **Token Handling during Mint/Redeem:**
    - `_handleCollateralTokensBeforeBuy()`: Correctly transfers collateral from user to FM.
    - `_handleIssuanceTokensAfterBuy()`: Correctly mints issuance tokens to user.
    - `_handleCollateralTokensAfterSell()`: Correctly transfers collateral from FM to user.
  - **Collateral Transfer:** `transferOrchestratorToken()` allows authorized payment clients to withdraw collateral (not affecting virtual supplies).
  - **Inheritance & Interfaces:** Correctly inherits from base contracts and implements required interfaces.

## 2. What's Left to Build

- **`FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`:**
  - **Fee Implementation (Step 2.10 in plan):**
    - Project fees (initially hardcoded constant, then dynamic).
    - Protocol fees (caching and update logic).
    - Fee collection during mint/redeem.
    - Fee withdrawal mechanism.
- **Future Modules (as per `context/Specs.md`):**
  - `DynamicFeeCalculator.sol`: For dynamic calculation of issuance, redemption, and loan origination fees.
  - `LM_PC_Credit_Facility.sol`: Lending facility for users to borrow against $HOUSE.
  - `LM_PC_Shift.sol` / `LM_PC_Elevator.sol`: Specific logic modules for rebalancing/floor-raising if `reconfigureSegments` isn't sufficient or needs a dedicated interface.
  - Full integration with `AUT_Roles.sol` for granular permissions if `onlyOrchestratorAdmin` is too broad for some functions.

## 3. Current Status

- `DiscreteCurveMathLib_v1.sol` and `PackedSegmentLib.sol` are complete and considered stable.
- `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` has its core non-fee-related functionality implemented and tested as per the implementation plan up to step 2.9.
- **Current focus:** Implementing fee collection and management within `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (step 2.10).

## 4. Known Issues

- No major known bugs in the implemented and tested functionality.
- The `projectCollateralFeeCollected` variable mentioned in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (in `transferOrchestratorToken`) is not yet being incremented as fee collection isn't implemented. This will be addressed during fee implementation.

## 5. Evolution of Project Decisions

- **Initial Math Focus:** Prioritizing the `DiscreteCurveMathLib_v1` ensured a solid mathematical foundation before building the stateful FM.
- **Virtual Supplies:** Adopting `virtualIssuanceSupply` and `virtualCollateralSupply` simplified the core FM logic by separating curve math from direct balance dependencies for calculations.
- **Staged Fee Implementation:** Decision to implement basic hardcoded project fees first, then protocol fees, and finally integrate a full `DynamicFeeCalculator` allows for incremental development and testing.
- **Packed Segments:** Early adoption of bit-packed segments for gas efficiency has been a consistent design choice.
