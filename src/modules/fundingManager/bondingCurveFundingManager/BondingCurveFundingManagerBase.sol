// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// External Dependencies
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

abstract contract BondingCurveFundingManagerBase is
    IBondingCurveFundingManagerBase,
    IFundingManager,
    ContextUpgradeable,
    ERC20Upgradeable,
    Module
{
    using Strings for uint;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage
    uint8 internal tokenDecimals;
    bool internal buyIsOpen;
    uint internal buyFee;
    address internal collateral;
    // Q: Do we want to set other beneficiary in the contract then the module itself for the fees?

    //--------------------------------------------------------------------------
    // Public Functions

    function token() public view returns (IERC20) {
        return __Module_orchestrator.token();
    }

    function buyOrder(uint _depositAmount) external payable virtual {
        // WiP
        // Deduct fee from incoming value. Fee is paid in collateral token
        _issueTokens(_depositAmount);
    }

    function openBuy() external onlyOrchestratorOwnerOrManager {
        // Function to set the PAMM buy functionality to open
        _openBuy();
    }

    function closeBuy() external onlyOrchestratorOwnerOrManager {
        // Function to set the PAMM buy functionality to close
        _closeBuy();
    }

    function updateBuyFee(uint _fee) external onlyOrchestratorOwnerOrManager {
        // Should update the buy fee of the contract
        _updateBuyFee(_fee);
    }
    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function decimals()
        public
        view
        override(ERC20Upgradeable)
        returns (uint8)
    {
        return tokenDecimals;
    }

    function deposit(uint amount) external {}

    function depositFor(address to, uint amount) external {}

    function withdraw(uint amount) external {}

    function withdrawTo(address to, uint amount) external {}

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    function _openBuy() internal {
        // Validate if not open
        buyIsOpen = true;
    }

    function _closeBuy() internal {
        // Validate if not closed
        buyIsOpen = false;
    }

    function _updateBuyFee(uint _fee) internal {
        buyFee = _fee;
    }

    function _issueTokens(uint _depositAmount)
        internal
        returns (uint mintAmount)
    {
        mintAmount = _issueTokensFormulaWrapper(_depositAmount);
        _mint(msg.sender, mintAmount);
    }

    function _setTokenDecimals(uint8 _decimals) internal {
        // Input check
        tokenDecimals = _decimals;
    }
    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
    {
        __Module_orchestrator.token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
