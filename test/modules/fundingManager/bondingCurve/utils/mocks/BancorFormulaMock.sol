pragma solidity ^0.8.0;

import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

contract BancorFormulaMock is IBancorFormula, ERC165 {
    function calculatePurchaseReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _depositAmount
    ) public view returns (uint) {}
    function calculateSaleReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _sellAmount
    ) public view returns (uint) {}
    function calculateCrossConnectorReturn(
        uint _fromConnectorBalance,
        uint32 _fromConnectorWeight,
        uint _toConnectorBalance,
        uint32 _toConnectorWeight,
        uint _amount
    ) public view returns (uint) {}
}
