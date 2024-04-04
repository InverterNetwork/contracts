// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/// @title  Aragon Interface for the Bancor Formula
/// @author https://github.com/AragonBlack/fundraising/blob/master/apps/bancor-formula/contracts/interfaces/IBancorFormula.sol
/// @notice The only revision that has been enacted within this distinct contract pertains to the
///         adjustment of the Solidity version, accompanied by version-specific changes. These
///         revisions encompass the changing of the 'contract' keyword into an 'interface' and the
///         modification of function visibility, transitioning from 'public' to 'external'

/*
    Bancor Formula interface
*/
interface IBancorFormula {
    function calculatePurchaseReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _depositAmount
    ) external view returns (uint);
    function calculateSaleReturn(
        uint _supply,
        uint _connectorBalance,
        uint32 _connectorWeight,
        uint _sellAmount
    ) external view returns (uint);
    function calculateCrossConnectorReturn(
        uint _fromConnectorBalance,
        uint32 _fromConnectorWeight,
        uint _toConnectorBalance,
        uint32 _toConnectorWeight,
        uint _amount
    ) external view returns (uint);
}
