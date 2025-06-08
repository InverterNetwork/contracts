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

### 2. Implementation

### 2.1. \_setSegments [DONE]

- Create a function that takes in an array of `PackedSegment` structs and sets the segments of the bonding curve
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol
  - function name: `_setSegments`
  - function signature: `function _setSegments(PackedSegment[] memory newSegments_)`
  - emits an event
- Should be tested via exposed function
- Should be called in the `init` function (and tested)

### 2.2. transferOrchestratorToken [DONE]

- Function implementation should be identical to the one in `src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol`
- Should be tested
  - success case requires some setup; use `testTransferOrchestratorToken_WorksGivenFunctionGetsCalled` in `test/unit/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol` as reference

### 2.3. setVirtualCollateralSupply [DONE]

- first implement `setVirtualCollateralSupply` same as in `src/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.sol`
  - add tests (you can use `FM_BC_Bancor_Redeeming_VirtualSupplyV1Test` l.1264 as reference):
