// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {IFM_Template_v1} from "./IFM_Template_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Template Funding Manager
 *
 * @notice  Basic template funding manager used as base for developing new
 *          funding managers.
 *
 * @dev     This contract is used to showcase a basic setup for a funding
 *          manager. The contract showcases the following:
 *          - Inherit from the Module_v1 contract to enable interaction with
 *            the Inverter workflow.
 *          - Use of the IFundingManager_v1 interface to facilitate
 *            interaction as a Funding Manager.
 *          - Implement custom interface which has all the public facing
 *            functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state
 *            variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface
 *            support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
contract FM_Template_v1 is IFM_Template_v1, Module_v1 {
    // =========================================================================
    // Libraries

    using SafeERC20 for IERC20;

    // =========================================================================
    // ERC165

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(IFM_Template_v1).interfaceId
            || interfaceId_ == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    // =========================================================================
    // Constants

    // Add constants here

    // =========================================================================
    // State

    /// @notice    Mapping of user addresses to their deposited token amounts.
    mapping(address user => uint amount) internal _depositedAmounts;

    /// @notice    The orchestrator token.
    IERC20 internal _orchestratorToken;

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // =========================================================================
    // Modifiers

    // Add modifiers here

    // =========================================================================
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);

        // Decode module specific init data through use of configData bytes.
        // This value is an example value used to showcase the setters/getters
        // and internal functions/state formatting style.
        (address orchestratorTokenAddress) = abi.decode(configData_, (address));

        // Set init state.
        _orchestratorToken = IERC20(orchestratorTokenAddress);
    }

    // =========================================================================
    // Public - Getters

    /// @inheritdoc IFM_Template_v1
    function getDepositedAmount(address user_)
        external
        view
        virtual
        returns (uint amount_)
    {
        amount_ = _depositedAmounts[user_];
    }

    /// @inheritdoc IFundingManager_v1
    function token()
        external
        view
        override
        returns (IERC20 orchestratorToken_)
    {
        orchestratorToken_ = _orchestratorToken;
    }

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc IFM_Template_v1
    function deposit(uint amount_) external virtual {
        // Validate parameters.
        if (amount_ == 0) {
            revert Module__FM_Template_InvalidAmount();
        }

        // Update state.
        _depositedAmounts[_msgSender()] += amount_;

        // Transfer tokens.
        _orchestratorToken.safeTransferFrom(
            _msgSender(), address(this), amount_
        );

        // Emit event.
        emit Deposited(_msgSender(), amount_);
    }

    /// @inheritdoc IFundingManager_v1
    /// @dev Only the payment client can call this function.
    function transferOrchestratorToken(address to, uint amount)
        external
        virtual
        override
        onlyPaymentClient
    {
        // Validate parameters.
        _validateOrchestratorTokenTransfer(to, amount);

        // Transfer tokens.
        _orchestratorToken.safeTransfer(to, amount);

        // Emit event.
        emit TransferOrchestratorToken(to, amount);
    }

    // =========================================================================
    // Internal

    /// @notice Validates the transfer of orchestrator token.
    /// @param  to_     Address to transfer to.
    /// @param  amount_ Amount to transfer.
    function _validateOrchestratorTokenTransfer(address to_, uint amount_)
        internal
        view
        virtual
    {
        if (to_ == address(0)) {
            revert Module__FM_Template__ReceiverNotValid();
        }

        if (amount_ == 0) {
            revert Module__FM_Template_InvalidAmount();
        }

        if (_depositedAmounts[_msgSender()] < amount_) {
            revert Module__FM_Template_InvalidAmount();
        }
    }

    // =========================================================================
    // Overridden Internal Functions
}
