// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {ILiquidityVaultController} from
    "@liquidityVault/ILiquidityVaultController.sol";
import {ILiquidityVaultProviderWhitelist} from
    "@liquidityVault/ILiquidityVaultProviderWhitelist.sol";
import {LibLiquidityVaultStructs} from
    "src/modules/lib/LibLiquidityVaultStructs.sol";

interface ILiquidityVault {
    function assessRepaymentPotential(string memory _code)
        external
        view
        returns (
            uint repaymentDeficit,
            LibLiquidityVaultStructs.AddressAmount[] memory repayerContributions
        );

    function getCeiling() external view returns (uint);

    function getBuffer() external view returns (uint);

    function getInvestment(string memory _code)
        external
        view
        returns (LibLiquidityVaultStructs.Investment memory);

    function getMinimum() external view returns (uint);

    function getReceiver(uint8 _index)
        external
        view
        returns (LibLiquidityVaultStructs.InvestmentReceiver memory);

    function getReceivers()
        external
        view
        returns (LibLiquidityVaultStructs.InvestmentReceiver[] memory);

    function invest(uint _amount) external;

    function repay(string memory _code) external;

    function resetCeiling() external;

    function setBuffer(uint _newValue) external;

    function setCeiling(uint _newValue) external;

    function setLiquidityProviderWhitelistContract(
        ILiquidityVaultProviderWhitelist _lpw
    ) external;

    function setLiquidityPoolContract(ILiquidityVaultController _lp) external; // TODO: change function name to reflect contract name change

    function setMinimum(uint _newValue) external;

    function setReceivers(
        LibLiquidityVaultStructs.InvestmentReceiver[] calldata _receivers
    ) external;

    function totalInvestedValue() external view returns (uint);

    function totalToBePaidValue() external view returns (uint);

    function totalRepaidValue() external view returns (uint);
}
