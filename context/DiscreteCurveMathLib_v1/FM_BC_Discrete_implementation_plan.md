# Implementation Plan

## Steps

### Basics

#### 1. Create files [DONE]

- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` file, declare contract
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol
- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol` file, declare contract, add dummy test so that it can be compiled
  - location: test/unit/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.t.sol
- Create `FM_BC_Discrete_Redeeming_VirtualSupply_v1.md` file, declare contract
  - location: src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.md
- Create `IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol` file, declare empty interface
  - location: src/modules/fundingManager/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol

### 2. Inheritance [DONE]

- FM_BC_Discrete_Redeeming_VirtualSupply_v1 should inherit from a bunch of other contracts specified in context/DiscreteCurveMathLib_v1/FM_BC_Discrete_implementation_context.md
- override all _required_ functions from the inheritance contracts with empty implementations, so that in the end we have a contract that holds all the required functions, but these functions dont do anything
