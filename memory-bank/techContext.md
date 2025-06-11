# Tech Context: House Protocol

## 1. Core Technologies

- **Primary Language:** Solidity (`^0.8.19` / `^0.8.23` as per existing contracts).
- **Development Framework:** Foundry (inferred from `.t.sol` test files, `foundry.toml`).
- **Smart Contracts (Key Implemented/In-Progress):**
  - `src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol`
  - `src/modules/fundingManager/bondingCurve/libraries/PackedSegmentLib.sol`
  - `src/modules/fundingManager/bondingCurve/FM_BC_Discrete_Redeeming_VirtualSupply_v1.sol`

## 2. Key Dependencies

- **OpenZeppelin Contracts:**
  - `@oz/token/ERC20/IERC20.sol`
  - `@oz/token/ERC20/extensions/IERC20Metadata.sol`
  - `@oz/token/ERC20/utils/SafeERC20.sol`
  - `@oz/utils/math/Math.sol`
  - `@oz-up/utils/introspection/ERC165Upgradeable.sol` (OpenZeppelin Upgradeable Contracts)
- **Modular Libraries (In-Repo):**
  - `@modLib/FixedPointMathLib.sol`
- **Foundry Standard Library:**
  - `forge-std/console2.sol` (for testing/debugging).
- **Project-Specific Interfaces & Abstract Contracts:**
  - `@fm/IFundingManager_v1.sol`
  - `@fm/bondingCurve/abstracts/*`
  - `@fm/bondingCurve/interfaces/*`
  - `src/modules/base/Module_v1.sol`
  - `src/orchestrator/interfaces/IOrchestrator_v1.sol`
  - `@ex/token/ERC20Issuance_v1.sol`

## 3. Technical Constraints & Considerations

- **Gas Optimization:** Critical for on-chain math and storage. Addressed via `PackedSegmentLib` and careful algorithm design in `DiscreteCurveMathLib_v1`.
- **Solidity Versioning:** Consistency across contracts.
- **ERC20 Compliance:** For issuance and collateral tokens.
- **Security:** Standard smart contract security practices (reentrancy guards if applicable, input validation, overflow/underflow checks, access control).
- **Bit-Packing Limits:** `PackedSegmentLib` defines strict bit limits for segment parameters (e.g., `INITIAL_PRICE_BITS = 72`).
- **`MAX_SEGMENTS`:** `DiscreteCurveMathLib_v1` defines a `MAX_SEGMENTS` constant (currently 10).
- **Upgradeability:** Contracts use `initializer` pattern, suggesting a proxy-based upgradeability strategy.

## 4. Tool Usage Patterns

- **`PackedSegmentLib`:** Used for creating, validating, and unpacking `PackedSegment` data. Ensures data integrity within bit limits.
- **`DiscreteCurveMathLib_v1`:** Central library for all bonding curve calculations. Called by `FM_BC_Discrete_Redeeming_VirtualSupply_v1` for its core logic.
- **Foundry for Testing:** Unit tests (`.t.sol` files) for individual functions and contract interactions. Use of `console2` for debugging within tests.
- **`SafeERC20`:** Used for safe ERC20 token interactions.
- **`FixedPointMathLib`:** For precise fixed-point arithmetic, especially `_mulDivUp` for rounding in favor of the protocol.

## 5. Development Setup (Inferred)

- Project managed with Foundry (`foundry.toml`).
- Dependencies likely managed via Git submodules (`.gitmodules`) or Forge's dependency management.
- Standard Solidity project structure (`src/`, `lib/`, `test/`, `script/`).
- Remappings (`remappings.txt`) used to simplify import paths.
