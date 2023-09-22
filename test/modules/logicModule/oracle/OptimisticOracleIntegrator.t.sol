// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

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

    // Setup + Init


    // Tests

    /*
        Gets the stored data
            When the assertion is not resolved
                 returns false and 0
            When the assertion is resolved
                 returns true + the correct data


    */
    function testGetData_ReturnsZeroWhenAssertionNotResolved(){

    }

    function testGetData(){}

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

    function testSetDefaultCurrencyFails_whenNewCurrencyIsZero(){

    }

    function testSetDefaultCurrencyFails_whenNewCurrencyIsNotWhitelisted(){
        
    }

    function testSetDefaultCurrency(){
        
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
    function testSetOptimisticOracleFails_WhenNewOracleIsZero(){

    }

    function testSetOptimisticOracleFails_WhenNewOracleIsNotUmaOptimiticOracle(){

    }

    function testSetOptimisticOracle(){

    }

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

    function testSetDefaultAssertionLivenessFails_whenLivenessIsZero(){

    }

    function testSetDefaultAssertionLiveness(){

    }

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

    function testAssertDataFor_whenAsserterAddressIsZero(){}
    function testAssertDataForFails_whenCallerDoesNotHaveEnoughFundsForBond(){}
    function testAssertDataFor_whenAsserterAddressIsNotZero();


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

    function testAssertioResolvedCallbackFails_whenCallerNotTheOO(){

    }
    function testAssertioResolvedCallback(){

    }

    /*
     Nothing happens (maybe necessary to mock for coverage? )
     */
    function assertionDisputedCallback(bytes32 assertionId) public virtual {}


}