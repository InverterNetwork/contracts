// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";
import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {BondingCurveFundingManagerMock} from
    "test/modules/fundingManager/bondingCurveFundingManager/marketMaker/utils/mocks/BondingCurveFundingManagerMock.sol";

contract BondingCurveFundingManagerBaseTest is ModuleTest {
    string private constant NAME = "Bonding Curve Token";
    string private constant SYMBOL = "BCT";
    uint8 private constant DECIMALS = 18;
    uint private constant BUY_FEE = 0;
    bool private constant BUY_IS_OPEN = true;

    BondingCurveFundingManagerMock bondingCurveFundingManger;
    address formula;

    function setUp() public {
        // Deploy contracts
        address impl = address(new BondingCurveFundingManagerMock());

        bondingCurveFundingManger =
            BondingCurveFundingManagerMock(Clones.clone(impl));

        formula = address(new BancorFormula());

        _setUpOrchestrator(bondingCurveFundingManger);

        // Init Module
        bondingCurveFundingManger.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                bytes32(abi.encodePacked(NAME)),
                bytes32(abi.encodePacked(SYMBOL)),
                DECIMALS,
                formula,
                BUY_FEE,
                BUY_IS_OPEN
            )
        );
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit() public override {
        assertEq(
            bondingCurveFundingManger.name(),
            string(abi.encodePacked(bytes32(abi.encodePacked(NAME)))),
            "Name has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.symbol(),
            string(abi.encodePacked(bytes32(abi.encodePacked(SYMBOL)))),
            "Symbol has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.decimals(),
            DECIMALS,
            "Decimals has not been set correctly"
        );
        assertEq(
            address(bondingCurveFundingManger.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.buyFee(),
            BUY_FEE,
            "Buy fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManger.buyIsOpen(),
            BUY_IS_OPEN,
            "Buy-is-open has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        bondingCurveFundingManger.init(_orchestrator, _METADATA, abi.encode());
    }

    /* Test buyingIsEnabled modifier
        ├── when buy is not open
        │       └── it should revert
        └── when buy is open
                └── it should not revert

    */
    function testBuyingIsEnabled_FailsIfBuyNotOpen() public{}

    /* Test validReceiver modifier
        ├── when receiver is address 0
        │       └── it should revert
        ├── when receiver is address itself
        │       └── it should revert
        └── when address is not in the cases above
                └── it should not revert
    */
    function testValidReceiver_FailsForInvalidAddresses() public{}

    //  Test modifiers on buyOrderFor function 

    function testPassingModifiersOnBuyOrderFor() public{}

    /* Test buyOrder and _buyOrder function
        ├── when the deposit amount is 0
        │       └── it should revert 
        └── when the deposit amount is not 0
                ├── when the fee is higher than 0
                │       └── it should substract the fee from the deposit amount
                │               └── it use determine the mint amount of tokens to mint 
                │               └── it should mint the tokens to the receiver    
                └── when the fee is 0
                        └── it use determine the mint amount of tokens to mint 
                        └── it should mint the tokens to the receiver     
        
    */
    function testBuyOrder_FailsIfDepositAmountIsZero() public{}
    function testBuyOrderWithZeroFee() public{}
    function testBuyOrderWithFee() public{}



    // modifier callerIsOrchestrationOwner() @todo changePrank({})
    modifier callerIsOrchestrationOwner() {
        address test_caller = address(0xA1BA);
        _authorizer.grantRole(_authorizer.getOwnerRole(), test_caller);
        changePrank(test_caller);
        _;
    }

    /* Test openBuy and _openBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module modifier tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already open
                │      └── it should revert  -> sure? idempotence @note
                └── when buy functionality is not open
                        └── it should open the buy functionality
                        └── it should emit an event? @todo
    */
    function testOpenBuy_FailsIfAlreadyOpen() callerIsOrchestrationOwner public{}
    function testOpenBuy() public{}

    /* Test closeBuy and _closeBuy function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when buy functionality is already closed
                │      └── it should revert ->  sure? idempotence @note
                └── when buy functionality is not closed
                        └── it should close the buy functionality
                        └── it should emit an event? @todo
    */
    function testCloseBuy_FailsIfAlreadyClosed() callerIsOrchestrationOwner public{}
    function testCloseBuy() public{}

    /* Test setBuyFee and _setBuyFee function
        ├── when caller is not the Orchestrator owner
        │      └── it should revert (tested in base Module tests)
        └── when caller is the Orchestrator owner
               └── when fee is above 100%
                │      └── it should revert
                └── when fee is below 100%
                        └── it should set the new fee
                        └── it should emit an event? @todo
    */
    function testSetBuyFee_FailsIfFeeAbove100() callerIsOrchestrationOwner public{}
    function testSetBuyFee() public{}


    /* Test _calculateFeeDeductedDepositAmount function
        ├── when feePct is higher than the BPS
        │      └── it should revert ( sanity check, we don't need to add a special revert since it's internal and buyFee < BPS is already tested in setBuyFee))) 
        └── when feePct is lower than the BPS
                └── it should return the deposit amount with the fee deducted
    */
    function testCalculateFeeDeductedDepositAmount_FailsIfFeeAbove100() public{}
    function testCalculateFeeDeductedDepositAmount() public{}

    // Test _issueTokens function
    // this is tested in the buyOrder tests




}
