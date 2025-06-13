# Project Brief: House Protocol

## 1. Project Name

House Protocol

## 2. Core Objective

The House Protocol aims to utilize crypto-economic mechanisms to support the proliferation and sustainable financing of cultural assets. At its heart is the native `$HOUSE` token.

## 3. Project Vision & Goals

- **Establish a Robust Token Economy:** Create a liquid and stable market for the `$HOUSE` token through a pre-sale and a subsequent Primary Issuance Market (PIM) based on a Discrete Bonding Curve (DBC).
- **Support Cultural Asset Tokenization:** Enable the permissionless launch of "endowment tokens" representing shares in real-world cultural assets, using `$HOUSE` as a core collateral token.
- **Provide Sustainable Value Accrual:** Implement mechanisms (e.g., fee collection, revenue injection) to systematically raise the floor price of the `$HOUSE` token over time.
- **Offer Capital Efficiency:** Provide a credit facility allowing `$HOUSE` token holders to borrow against their assets, freeing up liquidity.
- **Foster a Community-Driven Ecosystem:** Create a platform that empowers communities to fund and support cultural endeavors.

## 4. Key Features & Modules (High-Level Overview)

The protocol will be built on the Inverter stack and will consist of several key modules and functionalities:

1.  **`$HOUSE` Token:** The central ERC20 token of the protocol.
2.  **Pre-Sale Mechanism:** An initial, permissioned sale of `$HOUSE` tokens at a fixed price to institutional investors to bootstrap initial collateral.
3.  **Primary Issuance Market (PIM) / Discrete Bonding Curve (DBC):**
    - `FM_BC_Discrete_Redeeming_VirtualSupply_v1`: The core funding manager contract that allows anyone to mint (buy) and redeem (sell) `$HOUSE` tokens against a collateral token (e.g., stablecoin) based on a configurable, step-based price curve.
    - `DiscreteCurveMathLib_v1`: A library containing the pure mathematical logic for DBC calculations.
4.  **Floor Price Appreciation Mechanisms:**
    - **Revenue Injection:** Protocol revenue (from fees) will be used to inject more collateral into the DBC, raising the floor price.
    - **Liquidity Shift:** Authorized entities can reconfigure the DBC segments to reallocate existing reserves and raise the floor price.
5.  **Credit Facility (`LM_PC_Credit_Facility` - Future):** A system allowing `$HOUSE` token holders to lock their tokens and take out loans from the DBC's collateral reserves.
6.  **Dynamic Fee Mechanism (`DynamicFeeCalculator` - Future):** A module to calculate and apply dynamic fees for minting, redeeming, and loan origination, responsive to system state and KPIs.
7.  **Endowment Tokens:** A framework for the permissionless launch of ERC20 tokens representing shares in cultural assets, likely using `$HOUSE` as collateral and a similar PIM mechanism (without floor price raising or credit facility).
8.  **Access Control (`AUT_Roles`):** Role-based permissions for administrative functions across the protocol.

## 5. Target Audience

- **Institutional Investors:** Participants in the initial `$HOUSE` token pre-sale.
- **General Crypto Users/Investors:** Individuals minting, redeeming, or trading `$HOUSE` tokens and endowment tokens.
- **Cultural Asset Owners & Communities:** Entities seeking to tokenize and fund cultural assets.
- **Borrowers:** `$HOUSE` token holders looking to access liquidity via the credit facility.
- **Protocol Administrators/DAO:** Entities responsible for governance, configuration, and maintenance of the protocol.

## 6. Scope Boundaries

**In Scope (Current & Near-Term Focus):**

- Full implementation of the `FM_BC_Discrete_Redeeming_VirtualSupply_v1` module, including:
  - Core minting/redeeming logic.
  - Segment configuration and reconfiguration.
  - Virtual supply management.
  - Initial (potentially fixed) fee mechanisms.
- Development of the `DiscreteCurveMathLib_v1` and `PackedSegmentLib`.
- Basic access control mechanisms.

**Future Scope (Modules to be developed post-core FM):**

- `LM_PC_Credit_Facility` (Lending Facility).
- `DynamicFeeCalculator` (for fully dynamic fees).
- Dedicated modules for Liquidity Shift/Revenue Injection if `reconfigureSegments` proves insufficient (`LM_PC_Shift`, `LM_PC_Elevator`).
- Full framework and support for Endowment Token launches.
- Advanced governance mechanisms.

**Out of Scope (Explicitly):**

- Mechanisms for raising the price floor or a credit facility for individual Endowment Tokens (these features are specific to `$HOUSE`).

## 7. Source of Truth

This `projectBrief.md` serves as the foundational document. For detailed specifications, refer to:

- `context/Specs.md`: Detailed functional and behavioral specifications.
- Other Memory Bank files (`productContext.md`, `systemPatterns.md`, `techContext.md`, `activeContext.md`, `progress.md`) for evolving context.
