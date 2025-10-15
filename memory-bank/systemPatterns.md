# System Patterns: House Protocol

## 1. System Architecture Overview

The House Protocol employs a modular architecture. Key components include:

- **`FM_BC_Discrete_Redeeming_VirtualSupply_v1` (Funding Manager):** Manages the $HOUSE token's Discrete Bonding Curve (DBC), including minting/redeeming, segment configuration, and collateral management.
- **`DiscreteCurveMathLib_v1` (Math Library):** Provides pure functions for all DBC calculations (purchase/sale returns, reserves).
- **`PackedSegmentLib` (Helper Library):** Handles bit-packing and unpacking for efficient on-chain storage of curve segment data.
- **`AUT_Roles` (Authorizer):** Enforces role-based access control for administrative functions.
- **`LM_PC_Credit_Facility` (Logic Module - Future):** Will manage user loans against staked $HOUSE tokens.
- **`DynamicFeeCalculator` (DFC - Future):** Will calculate dynamic fees for mint, redeem, and loan origination.

_(Refer to `context/Specs.md` "4. Workflow Overview" for a Mermaid diagram of module interactions.)_

## 2. Key Technical Decisions

- **Discrete Bonding Curve (DBC):** Chosen for its defined price steps and segment-based structure.
- **Packed Segments:** `PackedSegment` struct and `PackedSegmentLib` for gas-efficient storage and retrieval of curve parameters.
- **Virtual Supplies:** `virtualIssuanceSupply` and `virtualCollateralSupply` used as references for curve calculations, decoupling them from immediate token balances for math operations.
- **Separated Math Logic:** Complex calculations are isolated in `DiscreteCurveMathLib_v1` for clarity, testability, and reusability.
- **Role-Based Access Control:** Administrative functions protected (e.g., `onlyOrchestratorAdmin`).

## 3. Design Patterns

- **Modular Design:** Functionality is split into distinct, specialized contracts (FMs, Libraries, Logic Modules).
- **Upgradeable Contracts:** Implied by use of `initializer` patterns and `ERC165Upgradeable`.
- **Interfaces:** Used for defining interactions between contracts (e.g., `IFundingManager_v1`, `IDiscreteCurveMathLib_v1`).
- **Event-Driven:** Key state changes and actions emit events for off-chain tracking and verification.
- **Library Usage:** Stateless logic (math, data packing) encapsulated in libraries (`DiscreteCurveMathLib_v1`, `PackedSegmentLib`).

## 4. Component Relationships

- `FM_BC_Discrete` uses `DiscreteCurveMathLib_v1` for all curve math.
- `FM_BC_Discrete` uses `PackedSegmentLib` (via `DiscreteCurveMathLib_v1`) for segment data.
- `FM_BC_Discrete` will interact with `DynamicFeeCalculator` for fee determination.
- `LM_PC_Credit_Facility` (future) will interact with `FM_BC_Discrete` (for collateral), `DiscreteCurveMathLib_v1` (for calculations), and `DynamicFeeCalculator` (for origination fees).

## 5. Critical Implementation Paths

- **Accurate DBC Math:** Precise implementation of `calculatePurchaseReturn`, `calculateSaleReturn`, and `calculateReserveForSupply` in `DiscreteCurveMathLib_v1`.
- **Segment & Step Logic:** Correct handling of calculations across segment boundaries and within individual steps, including partial steps.
- **Invariance Checks:** Robust `calculateReserveForSupply` check during `reconfigureSegments` to maintain collateral integrity.
- **Secure Token Handling:** Safe and correct transfer of collateral and issuance tokens (`SafeERC20`).
- **Gas Efficiency:** Continued attention to gas optimization, especially in mathematical computations and storage access.
