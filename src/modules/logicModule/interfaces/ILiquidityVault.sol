// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";
import {ILiquidityVaultProviderWhitelist} from
    "@lm/interfaces/ILiquidityVaultProviderWhitelist.sol";
import {SharedStructs} from "@lib/SharedStructs.sol";

interface ILiquidityVault {
    function assessRepaymentPotential(string memory _code)
        external
        view
        returns (
            uint repaymentDeficit,
            SharedStructs.AddressAmount[] memory repayerContributions
        );

    function getCeiling() external view returns (uint);

    function getBuffer() external view returns (uint);

    function getInvestment(string memory _code)
        external
        view
        returns (SharedStructs.Investment memory);

    function getMinimum() external view returns (uint);

    function getReceiver(uint8 _index)
        external
        view
        returns (SharedStructs.InvestmentReceiver memory);

    function getReceivers()
        external
        view
        returns (SharedStructs.InvestmentReceiver[] memory);

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
        SharedStructs.InvestmentReceiver[] calldata _receivers
    ) external;

    function totalInvestedValue() external view returns (uint);

    function totalToBePaidValue() external view returns (uint);

    function totalRepaidValue() external view returns (uint);
}
