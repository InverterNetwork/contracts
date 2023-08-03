pragma solidity 0.8.19;

/// TODO: Add license

/*
    Bancor Formula interface
*/
interface IBancorFormula {
    function calculatePurchaseReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _depositAmount
    ) external returns (uint);
    function calculateSaleReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _sellAmount
    ) external returns (uint);
    function calculateCrossConnectorReturn(
        uint _fromConnectorBalance,
        uint32 _fromConnectorWeight,
        uint _toConnectorBalance,
        uint32 _toConnectorWeight,
        uint _amount
    ) external returns (uint);
}
