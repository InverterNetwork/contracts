pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";


contract ImplementationV2Mock is ModuleMock {

    uint public data;

    constructor() {}

    function initialize(uint _data) external initializer {
        data = _data;
    }

    function getVersion() external pure returns (uint) {
        return 2;
    }
}
