# System Patterns

**Architecture:**

The Inverter Network smart contracts follow a modular architecture. Key components include:

*   **Modules:** Logic modules (e.g., payment routers, staking modules, funding pots) encapsulate specific functionalities.
*   **Factories:** Factories are used to deploy and manage modules.
*   **Proxies:** Proxies enable upgradability of the modules.
*   **Payment Processors:** Payment processors handle the logic for processing payments, including cross-chain payments.

**Key Technical Decisions:**

*   Using the Everclear protocol for cross-chain bridging.
*   Implementing a modular architecture for upgradability and maintainability.
*   Adhering to the ERC20 standard for token compatibility.

**Design Patterns:**

*   **Factory Pattern:** Used for deploying and managing modules.
*   **Proxy Pattern:** Used for enabling upgradability of modules.
*   **Module Pattern:** Encapsulating specific functionalities within modules.
