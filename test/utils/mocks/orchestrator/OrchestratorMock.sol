// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {IModuleManager} from "src/orchestrator/base/IModuleManager.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

contract OrchestratorMock is IOrchestrator {
    IERC20 public token;
    IPaymentProcessor public paymentProcessor;

    bool public executeTxBoolReturn;
    bytes public executeTxData;

    function executeTxFromModule(address, bytes memory data)
        external
        returns (bool, bytes memory)
    {
        executeTxData = data;
        return (executeTxBoolReturn, bytes(""));
    }

    function addModule(address module) external {}

    function removeModule(address module) external {}

    function isModule(address module) external returns (bool) {}

    function listModules() external view returns (address[] memory) {}

    function modulesSize() external view returns (uint8) {}

    function grantRole(bytes32 role, address account) external {}

    function revokeRole(bytes32 role, address account) external {}

    function renounceRole(address module, bytes32 role) external {}

    function hasRole(address module, bytes32 role, address account)
        external
        returns (bool)
    {}

    function init(
        uint,
        address,
        IERC20,
        address[] calldata,
        IFundingManager,
        IAuthorizer,
        IPaymentProcessor
    ) external {}

    function setAuthorizer(IAuthorizer authorizer_) external {}

    function setFundingManager(IFundingManager fundingManager_) external {}

    function setPaymentProcessor(IPaymentProcessor paymentProcessor_)
        external
    {
        paymentProcessor = paymentProcessor_;
    }

    function executeTx(address target, bytes memory data)
        external
        returns (bytes memory)
    {}

    function orchestratorId() external view returns (uint) {}

    function fundingManager() external view returns (IFundingManager) {}

    function authorizer() external view returns (IAuthorizer) {}

    function version() external pure returns (string memory) {}

    function owner() external view returns (address) {}

    function manager() external view returns (address) {}

    function findModuleAddressInOrchestrator(string calldata moduleName)
        external
        view
        returns (address)
    {}

    function verifyAddressIsPaymentProcessor(address paymentProcessorAddress)
        external
        view
        returns (bool)
    {}

    function verifyAddressIsRecurringPaymentManager(
        address recurringPaymentManager
    ) external view returns (bool) {}

    function verifyAddressIsMilestoneManager(address milestoneManagerAddress)
        external
        view
        returns (bool)
    {}

    function verifyAddressIsFundingManager(address fundingManagerAddress)
        external
        view
        returns (bool)
    {}

    function verifyAddressIsAuthorizerModule(address authModule)
        external
        view
        returns (bool)
    {}

    //-------------------------------------------------------------------
    //Mock Helper Functions
    function setToken(IERC20 token_) external {
        token = token_;
    }

    function setExecuteTxBoolReturn(
        bool boo //<--- this is a scary function
    ) external {
        executeTxBoolReturn = boo;
    }
}
