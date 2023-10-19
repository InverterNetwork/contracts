// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {OptimisticOracleIntegratorMock} from 
 "test/modules/logicModule/oracle/utils/OptimisiticOracleIntegratorMock.sol";

 import {OptimisticOracleV3Mock} from 
 "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";




// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    OptimisticOracleIntegrator,
    IOptimisticOracleIntegrator
} from "src/modules/logicModule/oracle/OptimisticOracleIntegrator.sol";

contract OptimisticOracleIntegratorTest is ModuleTest {
    OptimisticOracleIntegratorMock ooIntegrator;
    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 5000;

    // Mock data for assertions
        bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
        bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
        address constant MOCK_ASSERTER_ADDRESS = address(0x0);

    // Setup + Init

    function setUp() public {
        // TODO
        ooV3 = new OptimisticOracleV3Mock(_token, DEFAULT_LIVENESS);

        //Add Module to Mock Orchestrator
        address impl = address(new OptimisticOracleIntegratorMock());
        ooIntegrator = OptimisticOracleIntegratorMock(Clones.clone(impl));

        _setUpOrchestrator(ooIntegrator);

        _authorizer.setAllAuthorized(true);

        assertEq(address(_authorizer), address(_orchestrator.authorizer()));

        //console.log("Token address: ", address(_token));
        //console.log("Optimistic Oracle address: ",address(ooV3));
        bytes memory _configData = abi.encode(address(_token), address(ooV3));
        //console.log("Optimistic Oracle config data (next line): ");
        //console.logBytes(_configData);

        ooIntegrator.init(_orchestrator, _METADATA, _configData);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {

        bytes memory _configData = abi.encode(address(_token), address(ooV3));

        //TODO:
        // Assert that all the variables are correctly set or test if wrong inits fail?
/*         vm.expectRevert(
            IModule
                .Module__InvalidOrchestratorAddress
                .selector
        );

        //Init Module wrongly
        ooIntegrator.init(
            _orchestrator, _METADATA, abi.encode(1 weeks - 1)
        );

        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__RecurringPaymentManager__InvalidEpochLength
                .selector
        );

        //Init Module wrongly
        ooIntegrator.init(
            _orchestrator, _METADATA, abi.encode(52 weeks + 1)
        );

        //Init Module correct
        ooIntegrator.init(
            _orchestrator, _METADATA, abi.encode(1 weeks)
        );

        assertEq(ooIntegrator.getEpochLength(), 1 weeks); */
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        ooIntegrator.init(_orchestrator, _METADATA, bytes(""));
    }

    // Tests

    /*
        Gets the stored data
            When the assertion is not resolved
                 returns false and 0
            When the assertion is resolved
                 returns true + the correct data


    */
    function testGetData_ReturnsZeroWhenAssertionNotResolved() public {
        bytes32 assertionId = createMockAssertion(MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS);

        (bool assertionResolved, bytes32 data) = ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, false);
        assertEq(data, 0);
    }

    function testGetData() public {

        bytes32 assertionId = createMockAssertion(MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS);

        resolveMockAssertion(assertionId);


        (bool assertionResolved, bytes32 data) = ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, true);
        assertEq(data, MOCK_ASSERTION_DATA);

    }

    //==========================================================================
    // Setter Functions

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the address is 0
                reverts
            when the address is not UMA whitelisted 
                reverts
            when the address is a valid token
                sets the new address as default currency
                emits an event

    */

    function testSetDefaultCurrencyFails_whenNewCurrencyIsZero() public {
        vm.expectRevert(); // TODO: exact revert message
        ooIntegrator.setDefaultCurrency(address(0));
    }

    function testSetDefaultCurrencyFails_whenNewCurrencyIsNotWhitelisted(address nonWhitelisted)
        public
    {
              vm.expectRevert(); // TODO: exact revert message
        ooIntegrator.setDefaultCurrency(nonWhitelisted);   
    }

    function testSetDefaultCurrency(address whitelisted) public {
        whitelistAddress(whitelisted);

        ooIntegrator.setDefaultCurrency(whitelisted);

        assertEq(address(ooIntegrator.defaultCurrency), whitelisted);
    }

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the address is 0
                reverts
            when the address is not an UMA OO instance 
                reverts
            when the address is valid 
                sets the new address as optimistic oracle
                emits an event
    */
    function testSetOptimisticOracleFails_WhenNewOracleIsZero() public {}

    function testSetOptimisticOracleFails_WhenNewOracleIsNotUmaOptimiticOracle()
        public
    {}

    function testSetOptimisticOracle() public {}

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the liveness is 0
                reverts
            when the liveness is valid 
                sets the new liveness
                emits an event
    */

    function testSetDefaultAssertionLivenessFails_whenLivenessIsZero() public {}

    function testSetDefaultAssertionLiveness() public {}

    /*
        When the caller does not have asserter role
            reverts
        when the caller has the asserter role
            when the asserter address is 0
                it uses msgSender as asserter address
                    when the caller does not have enough funds for the bond
                        reverts
                    when the caller has enough funds for the bond
                        the contract takes the funds for the bond
                        the OO receives the bond
                        the assertion gets stored with a unique id
                        emits an event
            when the asserter address is not 0
                    when the caller does not have enough funds for the bond
                        reverts
                    when the caller has enough funds for the bond
                        the contract takes the funds for the bond
                        the OO receives the bond
                        the assertion gets stored with a unique id
                        emits an event


    */

    function testAssertDataFor_whenAsserterAddressIsZero() public {}
    function testAssertDataForFails_whenCallerDoesNotHaveEnoughFundsForBond()
        public
    {}
    function testAssertDataFor_whenAsserterAddressIsNotZero() public {}

    /*
        When the caller is not the OO
            it reverts
        When the caller is the OO
            If the assertion was deemed false
                deletes the assertionData linked to that assertionID
            If the assertion was deemed true
                the 'resolved' state in storage changes to true 
                emits an event
    */

    function testAssertioResolvedCallbackFails_whenCallerNotTheOO() public {}
    function testAssertioResolvedCallback() public {}

    /*
     Nothing happens (maybe necessary to mock for coverage? )
     */
    function assertionDisputedCallback(bytes32 assertionId) public virtual {}

    // Helper Functions

    function createMockAssertion(bytes32 dataId, bytes32 data, address asserter) internal returns(bytes32 assertionId){

        assertionId  = ooIntegrator.assertDataFor(dataId, data,  asserter);



    }

    function resolveMockAssertion(bytes32 assertionId) internal returns(bool assertionResult){
        
        assertionResult = ooV3.settleAndGetAssertionResult(assertionId);

                // The callback gets called in the above statement


    }
}
