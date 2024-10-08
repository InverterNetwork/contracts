// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
// External Dependencies
import {IERC20} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

contract FM_DepositVault_v1_Exposed is FM_DepositVault_v1 {
    function exposed_processProtocolFeeViaTransfer(
        address _treasury,
        IERC20 _token,
        uint _feeAmount
    ) external {
        _processProtocolFeeViaTransfer(_treasury, _token, _feeAmount);
    }

    function exposed_validateRecipient(address receiver) external view {
        return _validateRecipient(receiver);
    }
}
