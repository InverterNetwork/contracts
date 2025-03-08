// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IERC20PaymentClientBase_v2,
    IPaymentProcessor_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {
    ERC20PaymentClientBase_v2,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

// System under Test (SuT)
import {ILM_PC_FundingPot_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_FundingPot_v1.sol";

contract LM_PC_FundingPot_v1 is
    ILM_PC_FundingPot_v1,
    ERC20PaymentClientBase_v2
{
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
        override(ERC20PaymentClientBase_v2)
        returns (bool)
    {
        return interfaceId_ == type(ILM_PC_FundingPot_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    //--------------------------------------------------------------------------
    // Constants

    //--------------------------------------------------------------------------
    // State

    /// @dev The role for the funding pot admin.
    bytes32 public constant FUNDING_POT_ADMIN_ROLE = "FUNDING_POT_ADMIN";

    /// @notice    Storage gap for future upgrades.
    uint[50] private __gap;

    // =========================================================================
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata_);
    }

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc ILM_PC_FundingPot_v1
    /// @notice Grants the funding pot admin role to the given address.
    /// @dev This function is only callable by the orchestrator admin.
    /// @param admin_ The address to grant the funding pot admin role to.
    function grantFundingPotAdminRole(address admin_)
        external
        onlyOrchestratorAdmin
    {
        if (_checkForFundingPotAdminRole(admin_)) {
            revert Module__LM_PC_FundingPot_FundingPotAdminAlreadySet();
        }
        __Module_orchestrator.authorizer().grantRole(
            getFundingPotAdminRoleId(), admin_
        );
    }

    /// @inheritdoc ILM_PC_FundingPot_v1
    /// @notice Revokes the funding pot admin role from the given address.
    /// @dev This function is only callable by the orchestrator admin.
    /// @param admin_ The address to revoke the funding pot admin role from.
    function revokeFundingPotAdminRole(address admin_)
        external
        onlyOrchestratorAdmin
    {
        if (!_checkForFundingPotAdminRole(admin_)) {
            revert Module__LM_PC_FundingPot_AddressIsNotFundingPotAdmin();
        }
        __Module_orchestrator.authorizer().revokeRole(
            getFundingPotAdminRoleId(), admin_
        );
    }

    // =========================================================================
    // Public - Getters

    /// @notice Generates a role id for the funding pot admin role.
    function getFundingPotAdminRoleId() public view returns (bytes32) {
        return __Module_orchestrator.authorizer().generateRoleId(
            address(this), FUNDING_POT_ADMIN_ROLE
        );
    }
    //--------------------------------------------------------------------------
    // Internal

    /// @dev    Checks if the given address has the funding pot admin role.
    /// @param  admin_ The address to check for the funding pot admin role.
    /// @return bool True if the address has the funding pot admin role, false otherwise.
    function _checkForFundingPotAdminRole(address admin_)
        internal
        view
        returns (bool)
    {
        return __Module_orchestrator.authorizer().checkForRole(
            getFundingPotAdminRoleId(), admin_
        );
    }
}
