__PR 737: CrossChain PP Base & Everclear CrossChain PP__

This PR introduces a base contract and a specific implementation for cross-chain payment processing within the Inverter network. It leverages the Everclear protocol for bridging tokens between chains.

__Key Components:__

1. __`PP_CrossChainBase_v1` (Abstract Contract):__

   - This abstract contract provides the foundation for cross-chain payment processors.

   - It inherits from `IPP_CrossChainBase_v1` and `Module_v1`.

   - __Key Features:__

     - __Bridge Data Management:__ Stores and retrieves bridge-specific data.
     - __Payment ID Tracking:__ Tracks payment IDs for cross-chain payments.
     - __Unclaimable Amounts:__ Manages and allows claiming of tokens that failed to transfer.
     - __Base Validation:__ Implements basic validation checks for cross-chain payments.

   - It defines the `_executeBridgeTransfer` function, which __must be implemented__ in derived contracts to handle bridge-specific logic.

2. __`IPP_CrossChainBase_v1` (Interface):__

   - Defines the interface for the `PP_CrossChainBase_v1` contract.
   - Includes functions for getting bridge data and the current payment ID.
   - Defines events for bridge transfer success and failure.

3. __`PP_Everclear_CrossChain_v1` (Contract):__

   - This contract implements the `PP_CrossChainBase_v1` to enable cross-chain payments using the Everclear protocol.

   - It inherits from `IPP_Everclear_CrossChain_v1` and `PP_CrossChainBase_v1`.

   - __Key Features:__

     - __Everclear Integration:__ Creates new intents via the Everclear Spoke contract for each payment order.
     - __Failed Transfer Handling:__ Retries failed transfers using unclaimable amounts.

   - It uses the `_everClearSpoke` state variable to interact with the Everclear Spoke contract.

   - It implements the `_executeBridgeTransfer` function to create a new intent on Everclear.

4. __`IPP_Everclear_CrossChain_v1` (Interface):__

   - Defines the interface for the `PP_Everclear_CrossChain_v1` contract.
   - Includes functions for getting the Everclear Spoke contract address and retrieving intent data.

__Workflow:__

1. A payment client initiates a cross-chain payment by creating a payment order.
2. The `processPayments` function in `PP_Everclear_CrossChain_v1` is called.
3. The function validates the payment order and transfers the tokens from the payment client to the payment processor.
4. The `_executeBridgeTransfer` function is called, which creates a new intent on the Everclear Spoke contract.
5. If the bridge transfer is successful, the `_processSuccessfulBridgeTransfer` function is called, which emits events and stores bridge data.
6. If the bridge transfer fails, the `_processFailedBridgeTransfer` function is called, which stores the unclaimable amount and emits an event.


__TO DO__

Task: E2E test for PP_EverclearCrossChain

Context

The E2E tests still have to be created for the Everclear CrossChain PP.

We don't have a payment client which is able to create payment orders, defining the destination chain ID and TTL, Fee variables.

A mock should be created by extending the LM_PC_PaymentRouter_v2, adding a function to add a payment order with the needed parameters

References

Success Criteria

- [ ] payment client mock based on LM_PC_PaymentRouter_v2, which enables adding payment orders with the needed crosschain parameters

- [ ]  E2E test testing the PP_Everclear_CrossChain_v1