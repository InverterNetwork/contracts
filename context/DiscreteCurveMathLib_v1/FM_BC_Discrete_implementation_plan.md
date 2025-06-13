# Implementation Plan

## Steps

### 1.Basics

#### 1.1. Create files [DONE]

- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` file, declare contract
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol
- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol` file, declare contract, add dummy test so that it can be compiled
  - location: test/unit/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol
- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.md` file, declare contract
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.md
- Create `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` file, declare empty interface
  - location: src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol

### 1.2. Inheritance [DONE]

- FM_BC_Discrete_Redeeming_VirtualSupply_v1 should inherit from a bunch of other contracts specified in context/DiscreteCurveMathLib_v1/FM_BC_Discrete_implementation_context.md
- override all _required_ functions from the inheritance contracts with empty implementations, so that in the end we have a contract that holds all the required functions, but these functions dont do anything

### 1.3. Default Curve Conguration in test [DONE]

- use the same curve as `flatSlopedTestCurve` defined in `test/unit/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.t.sol` as a default curve configuration to be defined in the top of the testfile `test/unit/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol`
- then make sure that all tests that make use of a curve configuration are using the default curve configuration (where possible); the following tests should be updated to use the default curve configuration
  - `testReconfigureSegments_FailsGivenInvarianceCheckFailure` and
  - `testReconfigureSegments_WorksAndEmitsEvent` will be updated to utilize this `defaultCurve` for their initial segment setup.

### 2. Implementation

### 2.0 `_init`

#### 2.0.1 setting tokens [DONE]

- set issuance token in the bonding curve (`issuanceToken`)
  - internal function `_setIssuanceToken`
  - is called within the `init` function
  - requires test to check that the issuance token is set correctly + event emission
- set collateral token in the bonding curve (`_token`)
  - requires test to check that the token is set correctly + event emission

### 2.1. `_setSegments` [DONE]

- Create a function that takes in an array of `PackedSegment` structs and sets the segments of the bonding curve
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol
  - function name: `_setSegments`
  - function signature: `function _setSegments(PackedSegment[] memory newSegments_)`
  - emits an event
- Should be tested via exposed function
- Should be called in the `init` function (and tested)

### 2.2. `transferOrchestratorToken` [DONE]

- Function implementation should be identical to the one in `src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol`
- Should be tested
  - success case requires some setup; use `testTransferOrchestratorToken_WorksGivenFunctionGetsCalled` in `test/unit/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol` as reference

### 2.3. `setVirtualCollateralSupply` [DONE]

- first implement `setVirtualCollateralSupply` same as in `src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol`
  - add tests (you can use `FM_BC_Bancor_Redeeming_VirtualSupplyV1Test` l.1264 as reference):

### 2.4. `reconfigureSegments` [DONE]

- should take in an array of `PackedSegment`
- invariance check: should revert if the new curve shape breaks the 100% backing constraint
- should emit an event: segments, virtualIssuanceSupply
- only callable by orchestrator admin
- tests:
  - access control
  - invariant check => if invariant breaks should revert
  - happy path: deletes previous segments and sets new segments
  - event emission: segments, virtualIssuanceSupply

### 2.5. `setVirtualIssuanceSupply` [DONE]

- Implement `_setVirtualIssuanceSupply` in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` (similar to `_setVirtualCollateralSupply`).
- Implement `setVirtualIssuanceSupply` (external, `onlyOrchestratorAdmin`) in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
- Update `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` to include `setVirtualIssuanceSupply`.
- Update `FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol` to expose `_setVirtualIssuanceSupply` (as `exposed_setVirtualIssuanceSupply`).
- Add tests for `_setVirtualIssuanceSupply` (success with event).
- Add tests for `setVirtualIssuanceSupply` (success, reverts if not authorized).

### 2.6. `getStaticPriceForBuying` and `getStaticPriceForSelling` [DONE]

- `getStaticPriceForSelling` is the return value of `_findPositionForSupply` in `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol`
  - it needs to be passed the current curve configuration and
  - the virtualIssuanceSupply
- `getStaticPriceForBuying` is the return value of `_findPositionForSupply` in `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol`
  - it needs to be passed the current curve configuration and
  - the virtualCollateralSupply + 1
- tests for both functions:
  - test that they return the correct values
    - at segment transition
    - at segment transition

### 2.7. `_issueTokensFormulaWrapper` [DONE]

- return value of `_calculatePurchaseReturn` in `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol`
  - passed current curve configuration and
  - the virtualIssuanceSupply and
  - amountIn of collateral tokens
- tests (via exposed function)
  - returns expected value for given input (multiple curve scenarios)

### 2.8. `_redeemTokensFormulaWrapper` [DONE]

- return value of `_calculateSaleReturn` in `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol`
  - passed current curve configuration and
  - the virtualIssuanceSupply and
  - amountIn of issuance tokens
- tests (via exposed function)
  - returns expected value for given input (multiple curve scenarios)

### 2.9. handle functions: token transfers & mints [BLOCKED]

Note: exposed contract can be found here: `test/mocks/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed.sol`

#### 2.9.1. `_handleCollateralTokensBeforeBuy` [DONE]

- [x] transfers issuance tokens from provider to this module
  - tests (via exposed function)
    - [x] transfers tokens from provider to this module

#### 2.9.2. `_handleIssuanceTokensAfterBuy` [DONE]

- mints issuance tokens to receiver
  - tests (via exposed function)
    - mints tokens to receiver

#### 2.9.3. `_handleCollateralTokensAfterSell` [DONE]

- transfers collateral tokens to receiver
  - tests (via exposed function)
    - transfers tokens to receiver

### 2.10. `_getFunctionFeesAndTreasuryAddresses` (Cached Protocol Fees) [DONE]

- [x] 1. Define `ProtocolFeeCache` struct in `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`.
- [x] 2. Set constant project fees (`PROJECT_BUY_FEE_BPS`, `PROJECT_SELL_FEE_BPS`) in `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` and ensure `buyFee`/`sellFee` state vars are set in `init`.
- [x] 3. `init` calls `super._getFunctionFeesAndTreasuryAddresses` to get protocol fees (BPS for collateral/issuance, for buy/sell selectors) and treasury addresses from `FeeManager` and stores them in a new `_protocolFeeCache` (struct instance).
- [x] 4. Add unit tests for `init` fee setup (populating `_protocolFeeCache`) and
- [x] 5. Override `_getFunctionFeesAndTreasuryAddresses` to retrieve and returned cached protocol fees (from `_protocolFeeCache` struct) depending on the function selector
- [x] 6. Unit test for `_getFunctionFeesAndTreasuryAddresses`: retrieves correct protocol fees and treasury addresses from `_protocolFeeCache` struct.

### 2.11. Project Fees Preparation

- [x] 1. Add `_getBuyFee() virtual` functions to `BondingCurveBase_v1`; update `calculatePurchaseReturn` and ; run tests to ensure nothing breaks; add tests for new getters (to be tested via `test/mocks/modules/fundingManager/bondingCurve/abstracts/BondingCurveBaseV1Mock.sol`) to `test/unit/modules/fundingManager/bondingCurve/abstracts/BondingCurveBase_v1.t.sol`
- [ ] 2. Add `_getSellFee() virtual` functions to `RedeemingBondingCurveBase_v1p`; udate `calculateSaleReturn` to use new getter; run tests to ensure nothing breaks; add tests for new getters (to be tested via `test/mocks/modules/fundingManager/bondingCurve/abstracts/RedeemingBondingCurveBaseV1Mock.sol`) to `test/unit/modules/fundingManager/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.t.sol`
- [ ] 3. Add overwritten `_getBuyFee()` and `_getSellFee()` functions to `FM_BC_Discrete_Redeeming_VirtualSupply_v1` and `FM_BC_Discrete_Redeeming_VirtualSupply_v1_Exposed`; for now they just return the constant values defined in the contract
