// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IModule} from "src/modules/base/IModule.sol";
import {IModuleFactory} from "src/factories/IModuleFactory.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";
import {IModuleManager} from "src/orchestrator/base/IModuleManager.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IMetadataManager} from "src/modules/utils/IMetadataManager.sol";
import {ISingleVoteGovernor} from "src/modules/utils/ISingleVoteGovernor.sol";
import {IPaymentProcessor} from "src/modules/paymentProcessor/IPaymentProcessor.sol";
import {IStreamingPaymentProcessor} from "src/modules/paymentProcessor/IStreamingPaymentProcessor.sol";
import {IBountyManager} from "src/modules/logicModule/IBountyManager.sol";
import {IRecurringPaymentManager} from "src/modules/logicModule/IRecurringPaymentManager.sol";
import {IERC20PaymentClient} from "src/modules/logicModule/paymentClient/IERC20PaymentClient.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IRebasingERC20} from "src/modules/fundingManager/token/IRebasingERC20.sol";
import {IBancorVirtualSupplyBondingCurveFundingManager} from "src/modules/fundingManager/bondingCurveFundingManager/IBancorVirtualSupplyBondingCurveFundingManager.sol";
import {IBondingCurveFundingManagerBase} from "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
import {IVirtualCollateralSupply} from "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualCollateralSupply.sol";
import {IVirtualTokenSupply} from "src/modules/fundingManager/bondingCurveFundingManager/marketMaker/IVirtualTokenSupply.sol";
import {IBancorFormula} from "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {ITokenGatedRoleAuthorizer} from "src/modules/authorizer/ITokenGatedRoleAuthorizer.sol";

import {IBeacon} from "@oz/proxy/beacon/IBeacon.sol";
import {IERC20} from "src/modules/fundingManager/token/IERC20.sol";
import {IERC20Metadata} from "src/modules/fundingManager/token/IERC20Metadata.sol";

library LibInterfaceId {

    function getInterfaceId_ISingleVoteGovernor() external pure returns(bytes4) {
        return type(ISingleVoteGovernor).interfaceId;
    }

    function getInterfaceId_IPaymentProcessor() external pure returns(bytes4) {
        return type(IPaymentProcessor).interfaceId;
    }

    function getInterfaceId_IStreamingPaymentProcessor() external pure returns(bytes4) {
        return type(IStreamingPaymentProcessor).interfaceId;
    }

    function getInterfaceId_IBountyManager() external pure returns(bytes4) {
        return type(IBountyManager).interfaceId;
    }

    function getInterfaceId_IRecurringPaymentManager() external pure returns(bytes4) {
        return type(IRecurringPaymentManager).interfaceId;
    }

    function getInterfaceId_IERC20PaymentClient() external pure returns(bytes4) {
        return type(IERC20PaymentClient).interfaceId;
    }

    function getInterfaceId_IFundingManager() external pure returns(bytes4) {
        return type(IFundingManager).interfaceId;
    }

    function getInterfaceId_IRebasingERC20() external pure returns(bytes4) {
        return type(IRebasingERC20).interfaceId;
    }

    function getInterfaceId_IBancorVirtualSupplyBondingCurveFundingManager() external pure returns(bytes4) {
        return type(IBancorVirtualSupplyBondingCurveFundingManager).interfaceId;
    }

    function getInterfaceId_IBondingCurveFundingManagerBase() external pure returns(bytes4) {
        return type(IBondingCurveFundingManagerBase).interfaceId;
    }

    function getInterfaceId_IRedeemingBondingCurveFundingManagerBase() external pure returns(bytes4) {
        return type(IRedeemingBondingCurveFundingManagerBase).interfaceId;
    }

    function getInterfaceId_IVirtualCollateralSupply() external pure returns(bytes4) {
        return type(IVirtualCollateralSupply).interfaceId;
    }
    function getInterfaceId_IVirtualTokenSupply() external pure returns(bytes4) {
        return type(IVirtualTokenSupply).interfaceId;
    }
    function getInterfaceId_IBancorFormula() external pure returns(bytes4) {
        return type(IBancorFormula).interfaceId;
    }

    function getInterfaceId_IAuthorizer() external pure returns(bytes4) {
        return type(IAuthorizer).interfaceId;
    }

    function getInterfaceId_ITokenGatedRoleAuthorizer() external pure returns(bytes4) {
        return type(ITokenGatedRoleAuthorizer).interfaceId;
    }

    function getInterfaceId_IMetadaManager() external pure returns(bytes4) {
        return type(IMetadataManager).interfaceId;        
    }

    function getInterfaceId_IModuleFactory() external pure returns(bytes4) {
        return type(IModuleFactory).interfaceId;
    }

    function getInterfaceId_IModule() external pure returns(bytes4) {
        return type(IModule).interfaceId;
    }

    function getInterfaceId_IOrchestrator() external pure returns(bytes4) {
        return type(IOrchestrator).interfaceId;
    }

    function getInterfaceId_IModuleManager() external pure returns(bytes4) {
        return type(IModuleManager).interfaceId;
    }

    function getInterfaceId_IOrchestratorFactory() external pure returns(bytes4) {
        return type(IOrchestratorFactory).interfaceId;
    }

    function getInterfaceId_IBeacon() external pure returns(bytes4) {
        return type(IBeacon).interfaceId;
    }

    function getInterfaceId_IERC20Metadata() external pure returns(bytes4) {
        return type(IERC20Metadata).interfaceId;
    }

    function getInterfaceId_IERC20() external pure returns(bytes4) {
        return type(IERC20).interfaceId;
    }
    
}
