// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRepayer_v1} from "@lm/interfaces/IRepayer_v1.sol";

library SharedStructs {
    /// @notice enum of possible states of an Investment
    enum InvestmentStatus {
        AVAILABLE,
        OK,
        REPAID
    }

    /// @notice general struct of an Investment
    struct Investment {
        uint tenure;
        uint principal;
        uint interestDue;
        uint start;
        uint end;
        uint totalRepaid;
        uint128 timeBetweenInstalments;
        uint32 fixedInterestAtEnd;
        uint16 numberOfInstalment;
        uint16 lastRepaidInstalment;
        uint32 fixedInterestPerInstalment;
        uint32 interestVariabilityCoefficient;
        address investor;
        InvestmentStatus status;
        string code;
    }

    /// @notice struct for investment receiver that holds the percentage for the split investment and must implement the Repayer interface
    struct InvestmentReceiver {
        uint percentage;
        IRepayer_v1 repayer;
    }

    /// @notice tuple with address and amount, a general struct for several use cases e.g. the return of forecastRepayment
    struct AddressAmount {
        address addr;
        uint amount;
    }
}
