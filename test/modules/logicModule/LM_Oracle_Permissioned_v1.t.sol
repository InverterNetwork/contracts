// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Tests and Mocks
import {Test} from "forge-std/Test.sol";
import {LM_Oracle_Permissioned_v1_Exposed} from
    "test/modules/logicModule/LM_Oracle_Permissioned_v1_Exposed.sol";
import {ERC20Decimals_Mock} from "test/utils/mocks/ERC20Decimals_Mock.sol";

// System under testing
import {
    LM_Oracle_Permissioned_v1,
    ILM_Oracle_Permissioned_v1
} from "@lm/LM_Oracle_Permissioned_v1.sol";

/**
 * @title   LM_Oracle_Permissioned_v1_Test
 * @dev     Test contract for LM_Oracle_Permissioned_v1
 * @author  Zealynx Security
 */
contract LM_Oracle_Permissioned_v1_Test is ModuleTest {
    // ================================================================================
    // Constants
    uint8 constant TOKEN_DECIMALS = 6;
    string constant TOKEN_NAME = "MOCK USDC";
    string constant TOKEN_SYMBOL = "M-USDC";

    // ================================================================================
    // State
    LM_Oracle_Permissioned_v1_Exposed manualExternalPriceSetter;
    ERC20Decimals_Mock collateralToken;

    // ================================================================================
    // Setup
    function setUp() public {
        // Create mock token with 6 decimals like USDC
        collateralToken =
            new ERC20Decimals_Mock(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS);

        // Setup manual external price setter
        address impl = address(new LM_Oracle_Permissioned_v1_Exposed());
        manualExternalPriceSetter =
            LM_Oracle_Permissioned_v1_Exposed(Clones.clone(impl));
        _setUpOrchestrator(manualExternalPriceSetter);

        // Init module
        bytes memory configData = abi.encode(address(collateralToken));
        manualExternalPriceSetter.init(_orchestrator, _METADATA, configData);

        // Grant PRICE_SETTER_ROLE and PRICE_SETTER_ROLE_ADMIN to the test contract
        manualExternalPriceSetter.grantModuleRole(
            manualExternalPriceSetter.getPriceSetterRole(), address(this)
        );
        manualExternalPriceSetter.grantModuleRole(
            manualExternalPriceSetter.getPriceSetterRoleAdmin(), address(this)
        );
    }

    // ================================================================================
    // Test Init

    // This function also tests all the getters
    function testInit() public override(ModuleTest) {
        assertEq(
            manualExternalPriceSetter.getCollateralTokenDecimals(),
            TOKEN_DECIMALS,
            "Token decimals not set correctly"
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        manualExternalPriceSetter.init(
            _orchestrator, _METADATA, abi.encode(address(collateralToken))
        );
    }

    function testSupportsInterface_GivenValidInterface() public {
        assertTrue(
            manualExternalPriceSetter.supportsInterface(
                type(ILM_Oracle_Permissioned_v1).interfaceId
            )
        );
    }

    // ================================================================================
    // Test External (public + external)

    /* Test: Function SetIssuancePrice()
        ├── Given the caller has not PRICE_SETTER_ROLE
        │   └── When the function setIssuancePrice() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller has PRICE_SETTER_ROLE
            └── When the function setIssuancePrice() is called
                └── Then the price should be set correctly (redirects to internal func)
    */

    function testSetIssuancePrice_worksGivenModifierInPlace(
        address unauthorized_,
        uint price_
    ) public {
        // Setup
        vm.assume(unauthorized_ != address(this));
        vm.assume(price_ > 0);
        bytes32 roleId = _authorizer.generateRoleId(
            address(manualExternalPriceSetter),
            manualExternalPriceSetter.getPriceSetterRole()
        );

        // Test
        vm.startPrank(unauthorized_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                unauthorized_
            )
        );
        manualExternalPriceSetter.setIssuancePrice(price_);
    }

    function testSetIssuancePrice_worksGivenPriceIsSet(
        uint initialPrice_,
        uint updatePrice_
    ) public {
        // Setup
        vm.assume(initialPrice_ > 0 && updatePrice_ > 0);
        vm.assume(initialPrice_ != updatePrice_);
        // Set initial price
        manualExternalPriceSetter.setIssuancePrice(initialPrice_);
        // pre-condition
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            initialPrice_,
            "Initial issuance price not set correctly"
        );

        // Test
        manualExternalPriceSetter.setIssuancePrice(updatePrice_);

        // Assert
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            updatePrice_,
            "Issuance price not set correctly"
        );
    }

    /* Test: Function: SetRedemptionPrice()
        ├── Given the caller has not PRICE_SETTER_ROLE
        │   └── When the function setRedemptionPrice() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller has PRICE_SETTER_ROLE
            └── When the function setRedemptionPrice() is called
                └── Then the price should be set correctly (redirects to internal func)
    */

    function testSetRedemptionPrice_worksGivenModifierInPlace(
        address unauthorized_,
        uint price_
    ) public {
        // Setup
        vm.assume(unauthorized_ != address(this));
        vm.assume(price_ > 0);
        bytes32 roleId = _authorizer.generateRoleId(
            address(manualExternalPriceSetter),
            manualExternalPriceSetter.getPriceSetterRole()
        );

        // Test
        vm.startPrank(unauthorized_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                unauthorized_
            )
        );
        manualExternalPriceSetter.setRedemptionPrice(price_);
    }

    function testSetRedemptionPrice_worksGivenPriceIsSet(
        uint initialPrice_,
        uint updatePrice_
    ) public {
        // Setup
        vm.assume(initialPrice_ > 0 && updatePrice_ > 0);
        vm.assume(initialPrice_ != updatePrice_);
        // Set initial price
        manualExternalPriceSetter.setRedemptionPrice(initialPrice_);
        // pre-condition
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            initialPrice_,
            "Initial redemption price not set correctly"
        );

        // Test
        manualExternalPriceSetter.setRedemptionPrice(updatePrice_);

        // Assert
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            updatePrice_,
            "Redemption price not set correctly"
        );
    }

    /* Test: Function: SetIssuanceAndRedemptionPrice()
        ├── Given the caller has not PRICE_SETTER_ROLE
        │   └── When the function setIssuanceAndRedemptionPrice() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller has PRICE_SETTER_ROLE
            └── When the function setIssuanceAndRedemptionPrice() is called
                └── Then the price should be set correctly (redirects to internal funcs)
    */

    function testSetIssuanceAndRedemptionPrice_worksGivenModifierInPlace(
        address unauthorized_,
        uint issuancePrice_,
        uint redemptionPrice_
    ) public {
        // Setup
        vm.assume(unauthorized_ != address(this));
        vm.assume(issuancePrice_ > 0 && redemptionPrice_ > 0);
        bytes32 roleId = _authorizer.generateRoleId(
            address(manualExternalPriceSetter),
            manualExternalPriceSetter.getPriceSetterRole()
        );

        // Test
        vm.startPrank(unauthorized_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                unauthorized_
            )
        );
        manualExternalPriceSetter.setIssuanceAndRedemptionPrice(
            issuancePrice_, redemptionPrice_
        );
    }

    function testSetIssuanceAndRedemptionPrice_worksGivenPricesAreSet(
        uint initialIssuancePrice_,
        uint initialRedemptionPrice_,
        uint updateIssuancePrice_,
        uint updateRedemptionPrice_
    ) public {
        // Setup
        vm.assume(
            initialIssuancePrice_ > 0 && initialRedemptionPrice_ > 0
                && updateIssuancePrice_ > 0 && updateRedemptionPrice_ > 0
        );
        vm.assume(initialIssuancePrice_ != updateIssuancePrice_);
        vm.assume(initialRedemptionPrice_ != updateRedemptionPrice_);
        // Set initial prices
        manualExternalPriceSetter.setIssuanceAndRedemptionPrice(
            initialIssuancePrice_, initialRedemptionPrice_
        );
        // pre-condition
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            initialIssuancePrice_,
            "Initial issuance price not set correctly"
        );
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            initialRedemptionPrice_,
            "Initial redemption price not set correctly"
        );

        // Test
        manualExternalPriceSetter.setIssuanceAndRedemptionPrice(
            updateIssuancePrice_, updateRedemptionPrice_
        );

        // Assert
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            updateIssuancePrice_,
            "Issuance price not set correctly"
        );
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            updateRedemptionPrice_,
            "Redemption price not set correctly"
        );
    }

    /* Test: Function getPriceForIssuance()
        └── Given a price is set
            └── When the function getPriceForIssuance() is called
                └── Then the function should return the correct price
    */

    function testGetPriceForIssuance_worksGivenPriceIsSet(uint price_) public {
        // Setup
        vm.assume(price_ > 0);
        manualExternalPriceSetter.setIssuancePrice(price_);

        // Test
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            price_,
            "Issuance price not set correctly"
        );
    }

    /* Test: Function getPriceForRedemption()
        └── Given a price is set
            └── When the function getPriceForRedemption() is called
                └── Then the function should return the correct price
    */

    function testGetPriceForRedemption_worksGivenPriceIsSet(uint price_)
        public
    {
        // Setup
        vm.assume(price_ > 0);
        manualExternalPriceSetter.setRedemptionPrice(price_);

        // Test
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            price_,
            "Redemption price not set correctly"
        );
    }

    // ================================================================================
    // Test Internal

    /* Test: Function _setIssuancePrice()
        ├── Given the price is 0
        │   └── When the function _setIssuancePrice() is called
        │       └── Then it should revert
        └── Given the price is bigger than 0
            └── When the function _setIssuancePrice() is called
                ├── Then it should set the issuance price correctly
                    └── And it should emit an event
    */

    function testInternalSetIssuancePrice_revertGivenPriceIsZero() public {
        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_Oracle_Permissioned_v1
                    .Module__LM_ExternalPriceSetter__InvalidPrice
                    .selector
            )
        );
        manualExternalPriceSetter.exposed_setIssuancePrice(0);
    }

    function testInternalSetIssuancePrie_worksGivenPriceGreaterThanZero(
        uint price_
    ) public {
        // Setup
        vm.assume(price_ > 0);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IOraclePrice_v1.IssuancePriceSet(price_, address(this));
        manualExternalPriceSetter.exposed_setIssuancePrice(price_);

        // Assert
        assertEq(
            manualExternalPriceSetter.getPriceForIssuance(),
            price_,
            "Issuance price not set correctly"
        );
    }
    /* Test: Function _setRedemptionPrice()
        ├── Given the price is 0
        │   └── When the function _setRedemptionPrice() is called
        │       └── Then it should revert
        └── Given the price is bigger than 0
            └── When the function _setRedemptionPrice() is called
                ├── Then it should set the redemption price correctly
                    └── And it should emit an event
    */

    function testInternalSetRedemptionPrice_revertGivenPriceIsZero() public {
        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_Oracle_Permissioned_v1
                    .Module__LM_ExternalPriceSetter__InvalidPrice
                    .selector
            )
        );
        manualExternalPriceSetter.exposed_setRedemptionPrice(0);
    }

    function testInternalSetRedemptionPrice_worksGivenPriceGreaterThanZero(
        uint price_
    ) public {
        // Setup
        vm.assume(price_ > 0);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IOraclePrice_v1.RedemptionPriceSet(price_, address(this));
        manualExternalPriceSetter.exposed_setRedemptionPrice(price_);

        // Assert
        assertEq(
            manualExternalPriceSetter.getPriceForRedemption(),
            price_,
            "Redemption price not set correctly"
        );
    }
}
