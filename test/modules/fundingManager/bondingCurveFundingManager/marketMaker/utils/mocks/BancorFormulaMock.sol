pragma solidity 0.8.20;

import {IBancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/IBancorFormula.sol";

contract BancorFormulaMock is IBancorFormula {
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
