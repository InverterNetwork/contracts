# Product Context: House Protocol

## 1. Problem Solved

The House Protocol aims to address several challenges in the realm of cultural asset financing and tokenization:

- **Liquidity for Cultural Assets:** Traditional cultural assets (like art, sports teams, etc.) often suffer from illiquidity. The protocol seeks to provide a mechanism to tokenize these assets (as "endowment tokens") and create liquid markets for them.
- **Price Discovery:** Establishing fair market value for unique cultural assets can be difficult. The Discrete Bonding Curve (DBC) mechanism for the $HOUSE token, and subsequently for endowment tokens, offers a transparent and automated price discovery process.
- **Sustainable Funding:** The protocol aims to create a self-sustaining ecosystem where fees generated from token minting/redeeming and lending activities can be reinvested to support the protocol's growth and increase the value proposition for token holders (e.g., by raising the $HOUSE floor price).
- **Access to Capital:** $HOUSE token holders can gain liquidity without selling their assets by using the protocol's credit facility, borrowing against their tokens.

## 2. Target Users

The House Protocol targets several user segments:

- **Institutional Investors:** Initial participants in the permissioned pre-sale of $HOUSE tokens.
- **General Crypto Users/Investors:** Participants in the Primary Issuance Market (PIM) for minting and redeeming $HOUSE tokens, and potentially speculating on its value.
- **Cultural Asset Owners/Communities:** Entities or groups wishing to tokenize real-world cultural assets by launching endowment tokens.
- **Borrowers:** $HOUSE token holders seeking to access liquidity by taking out loans against their holdings.
- **Protocol Stewards/DAO (Implied):** Entities responsible for managing and configuring aspects of the protocol, such as fee parameters and curve reconfigurations.

## 3. How It Works (High-Level Product Flow)

1.  **Initialization & Pre-Sale:**

    - The protocol is launched, and $HOUSE tokens are offered to whitelisted institutional investors at a fixed price.
    - Funds from the pre-sale are collected to provide the initial collateral for the Discrete Bonding Curve.

2.  **Primary Issuance Market (PIM) for $HOUSE:**

    - The PIM opens, allowing anyone to mint $HOUSE tokens by depositing a specified collateral token (e.g., a stablecoin) into the DBC. The price is determined by the curve's current step.
    - Users can also redeem (sell) their $HOUSE tokens back to the DBC to receive collateral tokens.
    - Minting and redeeming operations incur dynamic fees.

3.  **Floor Price Appreciation:**

    - A portion of the collected fees is used by the protocol to inject additional collateral into the lower steps of the DBC or reconfigure the curve.
    - This action aims to systematically raise the floor price of the $HOUSE token over time.

4.  **Credit Facility:**

    - $HOUSE token holders can lock their tokens as collateral within the protocol's lending facility.
    - They can then borrow collateral tokens from the DBC's reserve, up to a certain percentage of their locked $HOUSE value (valued at the floor price).
    - Borrowing incurs an origination fee. Repayment of the loan (principal) unlocks the $HOUSE tokens.

5.  **Endowment Tokens:**
    - Community members or asset owners can permissionlessly launch new ERC20 "endowment tokens" representing shares in specific cultural assets.
    - These endowment tokens would also use a PIM mechanism, likely with $HOUSE as their collateral token, but without the advanced features like floor price raising or a credit facility specific to them.

## 4. User Experience Goals

- **Transparency:** Users should have a clear understanding of how the bonding curve determines prices and how fees are calculated and utilized.
- **Predictability:** While prices are dynamic, the mechanism of the DBC should provide a predictable framework for how supply changes affect price.
- **Security:** Users must trust that their funds and tokens are secure within the protocol's smart contracts.
- **Accessibility:** The process of minting, redeeming, and borrowing should be as straightforward as possible for users familiar with DeFi protocols.
- **Fairness:** Fee structures and protocol mechanisms should be designed to be equitable and to benefit the long-term health and growth of the ecosystem.

## 5. Key Workflows (User Journeys)

- **Investor (Pre-Sale):**
  1.  Get whitelisted.
  2.  Contribute collateral tokens during the pre-sale period.
  3.  Receive $HOUSE tokens after the pre-sale concludes and the PIM is initialized.
- **Trader/User (PIM - Minting $HOUSE):**
  1.  Approve collateral token spending for the FM contract.
  2.  Call the mint function on the FM, specifying the amount of collateral to spend or tokens to receive.
  3.  Receive $HOUSE tokens, with fees automatically deducted/accounted for.
- **Trader/User (PIM - Redeeming $HOUSE):**
  1.  Approve $HOUSE token spending for the FM contract.
  2.  Call the redeem function on the FM, specifying the amount of $HOUSE to redeem.
  3.  Receive collateral tokens, with fees automatically deducted/accounted for.
- **Borrower ($HOUSE Holder):**
  1.  Approve $HOUSE token spending for the Lending Facility contract.
  2.  Deposit $HOUSE tokens into the Lending Facility.
  3.  Request a loan of collateral tokens, up to their borrowing limit.
  4.  Receive collateral tokens, with an origination fee deducted.
  5.  Repay the loan principal to the Lending Facility.
  6.  Withdraw their locked $HOUSE tokens.
- **Protocol Administrator/DAO:**
  1.  Configure initial curve segments.
  2.  Reconfigure curve segments to manage liquidity or raise the floor price (e.g., Liquidity Shift, Revenue Injection).
  3.  Set and adjust parameters for the Dynamic Fee Calculator.
  4.  Manage parameters for the Lending Facility (e.g., Borrowable Quota).
