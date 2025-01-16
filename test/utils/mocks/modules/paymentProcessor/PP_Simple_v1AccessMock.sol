// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
// Internal Dependencies
import {PP_Simple_v1} from "@pp/PP_Simple_v1.sol";

contract PP_Simple_v1AccessMock is PP_Simple_v1 {
    function exposed_validPaymentReceiver(address addr)
        external
        view
        returns (bool)
    {
        return _validPaymentReceiver(addr);
    }

    function exposed__validTotal(uint _total) external pure returns (bool) {
        return _validTotal(_total);
    }

    function exposed_validPaymentToken(address _token)
        external
        returns (bool)
    {
        return _validPaymentToken(_token);
    }
}
