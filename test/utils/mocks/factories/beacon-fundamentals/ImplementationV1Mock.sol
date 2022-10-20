pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ModuleMock} from "test/utils/mocks/modules/base/ModuleMock.sol";

contract ImplementationV1Mock is ModuleMock {
    uint256 public data;

    constructor() {}

    function initialize(uint256 _data) external initializer {
        data = _data;
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}
