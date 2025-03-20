pragma solidity ^0.8.0;

import "@oz/proxy/utils/Initializable.sol";

import {ModuleV1Mock} from "@mock/modules/base/ModuleV1Mock.sol";
import {IModuleImplementationMock} from
    "@mock/proxies/IModuleImplementationMock.sol";

contract ModuleImplementationV2Mock is
    ModuleV1Mock,
    IModuleImplementationMock
{
    uint public data;

    function initialize(uint data_) external initializer {
        data = data_;
    }

    function getMockVersion() external pure returns (uint) {
        return 2;
    }
}
