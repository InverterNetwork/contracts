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
    function calculatePurchaseReturn(uint256 _supply, uint256 _connectorBalance, uint32 _connectorWeight, uint256 _depositAmount) external view returns (uint256);
    function calculateSaleReturn(uint256 _supply, uint256 _connectorBalance, uint32 _connectorWeight, uint256 _sellAmount) external view returns (uint256);
    function calculateCrossConnectorReturn(uint256 _fromConnectorBalance, uint32 _fromConnectorWeight, uint256 _toConnectorBalance, uint32 _toConnectorWeight, uint256 _amount) external view returns (uint256);
}