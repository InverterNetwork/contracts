// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IPayer} from "src/interfaces/IPayer.sol";
import {IModule} from "src/interfaces/IModule.sol";

interface IPaymentManager is IPayer, IModule {
    struct Payment {
        uint id;
        address recipient;
        uint amount;
        bool isClaimed;
        bool isPaused;
        bool isRemoved;
    }

    function addPayment(address recipient, uint amount)
        external
        returns (uint);

    function listPayments() external view returns (Payment[] memory);
    function listPayments(uint start, uint end) external view returns (Payment[] memory);

    function pausePayment(uint id) external;

    function removePayment(uint id) external;

    function claim(uint id) external;

    /*
    addPayment(terms) - Adds a new payment containing the details of the monetary flow depending on the module
    listPayments() - Returns the existing payments of the contributors
    pausePayment(id) - Pauses a payment of a contributor
    removePayment(id) - Removes/stops a payment of a contributor
    claim() - Claims a
    */
}
