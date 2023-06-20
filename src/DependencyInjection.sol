// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

contract DependencyInjection {
    string[] moduleList = [
        "ListAuthorizer",
        "SingleVoteGovernor",
        "PaymentClient",
        "RebasingFundingManager",
        "MilestoneManager",
        "RecurringPaymentManager",
        "SimplePaymentProcessor",
        "StreamingPaymentProcessor",
        "MetadataManager"
    ];
}