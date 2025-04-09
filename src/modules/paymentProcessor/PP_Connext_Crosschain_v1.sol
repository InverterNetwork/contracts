pragma solidity ^0.8.20;

import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrosschainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {PP_Crosschain_v1} from
    "src/modules/paymentProcessor/abstracts/PP_Crosschain_v1.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

contract PP_Connext_Crosschain_v1 is PP_Crosschain_v1 {
    IEverclearSpoke public everClearSpoke;
    IWETH public weth;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override initializer {
        __Module_init(orchestrator_, metadata);
        (
            uint chainId_,
            address connextBridgeLogic_,
            address everClearSpoke_,
            address weth_
        ) = abi.decode(configData, (uint, address, address, address));

        everClearSpoke = IEverclearSpoke(everClearSpoke_);
        weth = IWETH(weth_);
    }

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        bytes memory executionData
    ) internal override returns (bytes memory) {
        //@notice call the connextBridgeLogic to execute the bridge transfer
        bytes32 intentId = xcall(order, executionData);
        return abi.encode(intentId);
    }

    function processPayments(IERC20PaymentClientBase_v2 client)
        external
        override
    {
        // Collect orders from the client
        IERC20PaymentClientBase_v2.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();

        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData =
                _executeBridgeTransfer(orders[i], executionData);

            emit PaymentOrderProcessed(
                address(client),
                orders[i].recipient,
                address(orders[i].paymentToken),
                orders[i].amount,
                orders[i].start,
                orders[i].cliff,
                orders[i].end
            );
            _paymentId++;

            // Inform the client about the processed amount
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    function xcall(
        IERC20PaymentClientBase_v2.PaymentOrder memory order,
        bytes memory executionData
    ) internal returns (bytes32 intentId) {
        // Decode any additional parameters from executionData
        (uint maxFee, uint ttl) = abi.decode(executionData, (uint, uint));

        // Wrap ETH into WETH to send with the xcall
        IERC20(order.paymentToken).transferFrom(
            msg.sender, address(this), order.amount
        );

        // This contract approves transfer to EverClearSpoke
        IERC20(order.paymentToken).approve(
            address(everClearSpoke), order.amount
        );

        // Create destinations array with the target chain
        uint32[] memory destinations = new uint32[](1);
        destinations[0] = 8453; // @note -> hardcode for now -> order.destinationChainId;

        // Call newIntent on the EverClearSpoke contract
        (intentId,) = everClearSpoke.newIntent(
            destinations,
            order.recipient, // to
            order.paymentToken, // inputAsset
            address(weth), // outputAsset (assuming same asset on destination)
            order.amount, // amount
            uint24(maxFee), // maxFee (cast to uint24)
            uint48(ttl), // ttl (cast to uint48)
            "" // empty data field, modify if needed
        );

        return intentId;
    }

    ///cancelling payments on connext??????
}
