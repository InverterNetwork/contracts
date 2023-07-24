// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Dependencies
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Dependencies
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";
import {TokenGatedRoleAuthorizer} from
    "src/modules/authorizer/TokenGatedRoleAuthorizer.sol";
import {SingleVoteGovernor} from "src/modules/authorizer/SingleVoteGovernor.sol";
import {PaymentClient} from "src/modules/base/mixins/PaymentClient.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";
import {MilestoneManager} from "src/modules/logicModule/MilestoneManager.sol";
import {RecurringPaymentManager} from
    "src/modules/logicModule/RecurringPaymentManager.sol";
import {SimplePaymentProcessor} from
    "src/modules/paymentProcessor/SimplePaymentProcessor.sol";
import {StreamingPaymentProcessor} from
    "src/modules/paymentProcessor/StreamingPaymentProcessor.sol";

import {ModuleManager} from "src/proposal/base/ModuleManager.sol";
import {IMilestoneManager} from "src/modules/logicModule/IMilestoneManager.sol";

// Internal Interfaces
import {
    IProposal,
    IFundingManager,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";
import {IModule} from "src/modules/base/IModule.sol";

/**
 * @title Proposal
 *
 * @dev A new funding primitive to enable multiple actors within a decentralized
 *      network to collaborate on proposals.
 *
 *      A proposal is composed of a [funding mechanism](./base/FundingVault) *      and a set of [modules](./base/ModuleManager).
 *
 *      The token being accepted for funding is non-changeable and set during
 *      initialization. Authorization is performed via calling a non-changeable
 *      {IAuthorizer} instance. Payments, initiated by modules, are processed
 *      via a non-changeable {IPaymentProcessor} instance.
 *
 *      Each proposal has a unique id set during initialization.
 *
 * @author Inverter Network
 */
contract Proposal is IProposal, OwnableUpgradeable, ModuleManager {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyAuthorized() {
        if (!authorizer.isAuthorized(_msgSender())) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    // Once we merge the RoleAuthoirzer We can completely remove Ownable
    // as import and rely on IAuthorizer to validate owners.

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address or manager.
    modifier onlyAuthorizedOrManager() {
        if (!authorizer.isAuthorized(_msgSender()) && _msgSender() != manager())
        {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    IERC20 private _token;

    /// @inheritdoc IProposal
    uint public override(IProposal) proposalId;

    /// @inheritdoc IProposal
    IFundingManager public override(IProposal) fundingManager;

    /// @inheritdoc IProposal
    IAuthorizer public override(IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override(IProposal) paymentProcessor;

    //--------------------------------------------------------------------------
    // Initializer

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IProposal
    function init(
        uint proposalId_,
        address owner_,
        IERC20 token_,
        address[] calldata modules,
        IFundingManager fundingManager_,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override(IProposal) initializer {
        // Initialize upstream contracts.
        __Ownable_init();
        __ModuleManager_init(modules);

        // Set storage variables.
        proposalId = proposalId_;

        _token = token_;

        fundingManager = fundingManager_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Transfer ownerhsip of proposal to owner argument.
        _transferOwnership(owner_);

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
        __ModuleManager_addModule(address(fundingManager_));
        __ModuleManager_addModule(address(authorizer_));
        __ModuleManager_addModule(address(paymentProcessor_));
    }

    //--------------------------------------------------------------------------
    // Module search functions

    /// @notice verifies whether a proposal with the title `moduleName` has been used in this proposal
    /// @dev The query string and the module title should be **exactly** same, as in same whitespaces, same capitalizations, etc.
    /// @param moduleName Query string which is the title of the module to be searched in the proposal
    /// @return uint256 index of the module in the list of modules used in the proposal
    /// @return address address of the module with title `moduleName`
    function _isModuleUsedInProposal(string calldata moduleName)
        private
        view
        returns (uint, address)
    {
        address[] memory moduleAddresses = listModules();
        uint moduleAddressesLength = moduleAddresses.length;
        string memory currentModuleName;
        uint index;

        for (; index < moduleAddressesLength;) {
            currentModuleName = IModule(moduleAddresses[index]).title();

            if (bytes(currentModuleName).length == bytes(moduleName).length) {
                if (
                    keccak256(abi.encodePacked(currentModuleName))
                        == keccak256(abi.encodePacked(moduleName))
                ) {
                    return (index, moduleAddresses[index]);
                }
            }

            unchecked {
                ++index;
            }
        }

        return (type(uint).max, address(0));
    }

    /// @inheritdoc IProposal
    function findModuleAddressInProposal(string calldata moduleName)
        external
        view
        returns (address)
    {
        (uint moduleIndex, address moduleAddress) =
            _isModuleUsedInProposal(moduleName);
        if (moduleIndex == type(uint).max) {
            revert DependencyInjection__ModuleNotUsedInProposal();
        }

        return moduleAddress;
    }

    //--------------------------------------------------------------------------
    // Module address verification functions
    // Note These set of functions are not mandatory for the functioning of the protocol, however they
    //      are provided for the convenience of the users since matching the names of the modules does not
    //      fully guarantee that the returned address is the address of the exact module the user was looking for

    /// @inheritdoc IProposal
    function verifyAddressIsAuthorizerModule(address authModule)
        external
        view
        returns (bool)
    {
        IAuthorizer authorizerModule = IAuthorizer(authModule);

        try authorizerModule.isAuthorized(address(uint160(1234))) returns (bool)
        {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IProposal
    function verifyAddressIsRebasingFundingManager(
        address rebasingFundingManagerAddress
    ) external view returns (bool) {
        RebasingFundingManager rebasingFundingManager =
            RebasingFundingManager(rebasingFundingManagerAddress);

        try rebasingFundingManager.token() returns (IERC20) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IProposal
    function verifyAddressIsMilestoneManager(address milestoneManagerAddress)
        external
        view
        returns (bool)
    {
        MilestoneManager milestoneManager =
            MilestoneManager(milestoneManagerAddress);

        try milestoneManager.hasActiveMilestone() returns (bool) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IProposal
    function verifyAddressIsRecurringPaymentManager(
        address recurringPaymentManager
    ) external view returns (bool) {
        RecurringPaymentManager paymentManager =
            RecurringPaymentManager(recurringPaymentManager);

        try paymentManager.getEpochLength() returns (uint) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IProposal
    function verifyAddressIsSimplePaymentProcessor(
        address simplePaymentProcessorAddress
    ) external view returns (bool) {
        SimplePaymentProcessor simplePaymentProcessor =
            SimplePaymentProcessor(simplePaymentProcessorAddress);

        try simplePaymentProcessor.token() returns (IERC20) {
            return true;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IProposal
    function verifyAddressIsStreamingPaymentProcessor(
        address streamingPaymentProcessorAddress
    ) external view returns (bool) {
        StreamingPaymentProcessor streamingPaymentProcessor =
            StreamingPaymentProcessor(streamingPaymentProcessorAddress);

        try streamingPaymentProcessor.unclaimable(
            address(uint160(345)), address(uint160(65))
        ) returns (uint) {
            return true;
        } catch {
            return false;
        }
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Only addresses authorized via the {IAuthorizer} instance can manage
    ///      modules.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override(ModuleManager)
        returns (bool)
    {
        return authorizer.isAuthorized(who);
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions

    /// @inheritdoc IProposal
    function executeTx(address target, bytes memory data)
        external
        onlyAuthorized
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (ok) {
            return returnData;
        } else {
            revert Proposal__ExecuteTxFailed();
        }
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IProposal
    function token() public view override(IProposal) returns (IERC20) {
        return _token;
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }

    function owner()
        public
        view
        override(OwnableUpgradeable, IProposal)
        returns (address)
    {
        return super.owner();
    }

    function manager() public view returns (address) {
        return owner();
    }
}
