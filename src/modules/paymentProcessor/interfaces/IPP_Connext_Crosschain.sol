// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IPaymentProcessor_v2} from
    "src/modules/paymentProcessor/IPaymentProcessor_v2.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IPP_Connext_Crosschain is IPaymentProcessor_v2 {}
