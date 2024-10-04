// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {
    IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1,
    FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1,
    IFundingManager_v1,
    IBondingCurveBase_v1
} from "@fm/bondingCurve/FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1.sol";

import {IFM_BC_BondingSurface_Redeeming_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_v1.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {BondingSurface} from "@fm/bondingCurve/formulas/BondingSurface.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {
    IRedeemingBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";
import {IBondingSurface} from "@fm/bondingCurve/interfaces/IBondingSurface.sol";
import {IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Mocks
import {FM_BC_BondingSurface_RedeemingV1_exposed} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/FM_BC_BondingSurface_RedeemingV1_exposed.sol";

/*     
    PLEASE NOTE: The following tests have been tested in other test contracts
    - buy() & buyOrderFor()
    - sell() & sellOrderFor()
    - getStaticPriceForSelling()
    - getStaticPriceForBuying()

    Also, since the following function just wrap the Bonding Surface contract, their content is assumed to be tested in the original formula tests, not here:

    - _issueTokensFormulaWrapper(uint _depositAmount)

    */
contract FM_BC_BondingSurface_Redeeming_v1Test is ModuleTest {
    string private constant NAME = "Bonding Surface Token";
    string private constant SYMBOL = "BST";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    uint private constant CAPITAL_REQUIREMENT = 1_000_000 * 1e18;

    uint private constant BUY_FEE = 100;
    uint private constant SELL_FEE = 100;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;
    uint32 private constant BPS = 10_000;

    uint private constant MIN_RESERVE = 1 ether;
    uint private constant BASE_PRICE_MULTIPLIER = 0.000001 ether;

    FM_BC_BondingSurface_RedeemingV1_exposed bondingCurveFundingManager;
    address formula;
    ERC20Issuance_v1 issuanceToken;

    // Addresses
    address owner_address = address(0xA1BA);
    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address burner = makeAddr("burner");
    bytes32 CURVE_INTERACTION_ROLE = "CURVE_USER";

    function setUp() public {
        // Deploy contracts
        issuanceToken = new ERC20Issuance_v1(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this)
        );
        IFM_BC_BondingSurface_Redeeming_v1.BondingCurveProperties memory
            bc_properties;

        // Deploy formula and cast to address for encoding
        BondingSurface bondingSurface = new BondingSurface();
        formula = address(bondingSurface);

        // Set Formula contract properties
        bc_properties.formula = formula;
        bc_properties.capitalRequired = CAPITAL_REQUIREMENT;
        bc_properties.basePriceMultiplier = BASE_PRICE_MULTIPLIER;

        // Set pAMM properties
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;

        address impl = address(new FM_BC_BondingSurface_RedeemingV1_exposed());

        bondingCurveFundingManager =
            FM_BC_BondingSurface_RedeemingV1_exposed(Clones.clone(impl));

        _setUpOrchestrator(bondingCurveFundingManager);
        _authorizer.setIsAuthorized(address(this), true);

        // Set Minter
        issuanceToken.setMinter(address(bondingCurveFundingManager), true); //@todo Marvin G This wasnt set??

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                _token, // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                bc_properties
            )
        );
        // Mint minimal reserve necessary to operate the BC
        _token.mint(
            address(bondingCurveFundingManager),
            bondingCurveFundingManager.MIN_RESERVE()
        );
    }
    //--------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    //--------------------------------------------------------------------------
    // Tests: Initialization
    function testInit() public override {
        // Issuance Token
        assertEq(
            issuanceToken.name(),
            string(abi.encodePacked(NAME)),
            "Name has not been set correctly"
        );
        assertEq(
            issuanceToken.symbol(),
            string(abi.encodePacked(SYMBOL)),
            "Symbol has not been set correctly"
        );
        // Collateral Token
        assertEq(
            address(bondingCurveFundingManager.token()),
            address(_token),
            "Collateral token not set correctly"
        );
        // Buy/Sell conditions
        assertEq(
            bondingCurveFundingManager.sellFee(),
            SELL_FEE,
            "Initial fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyFee(),
            BUY_FEE,
            "Buy fee has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            BUY_IS_OPEN,
            "Buy-is-open has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.buyIsOpen(),
            SELL_IS_OPEN,
            "Sell-is-open has not been set correctly"
        );
        // Bonding Curve Properties
        assertEq(
            address(bondingCurveFundingManager.formula()),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.capitalRequired(),
            CAPITAL_REQUIREMENT,
            "Initial capital requirements has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    //--------------------------------------------------------------------------
    // Tests: Supports Interface

    function testSupportsInterface() public {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IFM_BC_BondingSurface_Redeeming_v1).interfaceId
            )
        );
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IFundingManager_v1).interfaceId
            )
        );
    }

    //--------------------------------------------------------------------------
    // Public Functions

    function testCalculatebasePriceToCapitalRatio_worksGivenReturnValueInternalFunction(
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) public {
        // Set bounds so when values used for calculation, the result < 1e36
        _capitalRequirements = bound(_capitalRequirements, 1, 1e18);
        _basePriceMultiplier = bound(_basePriceMultiplier, 1, 1e18);

        // Setup
        bondingCurveFundingManager.setBasePriceMultiplier(_basePriceMultiplier);
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);

        // Use expected value from internal function
        uint expectedReturnValue = bondingCurveFundingManager
            .exposed_calculateBasePriceToCapitalRatio(
            _capitalRequirements, _basePriceMultiplier
        );

        // Execute Tx
        uint functionReturnValue = bondingCurveFundingManager
            .exposed_calculateBasePriceToCapitalRatio(
            _capitalRequirements, _basePriceMultiplier
        );

        // Assert expected return value
        assertEq(functionReturnValue, expectedReturnValue);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestratorAdmin Functions

    /*  Test setCapitalRequired()
        ├── Given: the caller is not the OrchestratorAdmin
        │   └── When: the function setCapitalRequired() is called
        │       └── Then: it should revert
        └── Given: the caller is the OrchestratorAdmin
            └── When: the function setCapitalRequired() is called
                └── Then: it should call the internal function and set the state
    */

    function testSetCapitalRequired_revertGivenCallerHasNotRiskManagerRole()
        public
    {
        uint newCapitalRequired = 1 ether;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.getAdminRole(),
                    seller
                )
            );
            bondingCurveFundingManager.setCapitalRequired(newCapitalRequired);
        }
    }

    function testSetCapitalRequired_worksGivenCallerHasRiskManagerRole(
        uint _newCapitalRequired
    ) public {
        vm.assume(
            _newCapitalRequired != bondingCurveFundingManager.capitalRequired()
        );
        _newCapitalRequired = bound(_newCapitalRequired, 1, 1e18);

        // Execute Tx
        bondingCurveFundingManager.setCapitalRequired(_newCapitalRequired);

        // Get current state value
        uint stateValue = bondingCurveFundingManager.capitalRequired();

        // Assert state has been updated
        assertEq(stateValue, _newCapitalRequired);
    }

    /*  Test setBaseMultiplier()
        ├── Given: the caller is not the OrchestratorAdmin
        │   └── When: the function setBaseMultiplier() is called
        │       └── Then: it should revert
        └── Given: the caller is the OrchestratorAdmin
            └── When: the function setBaseMultiplier() is called
                └── Then: it should call the internal function and set the state
    */

    function testSetBaseMultiplier_revertGivenCallerHasNotRiskManagerRole()
        public
    {
        uint newBaseMultiplier = 1;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.getAdminRole(),
                    seller
                )
            );
            bondingCurveFundingManager.setBasePriceMultiplier(newBaseMultiplier);
        }
    }

    function testSetBaseMultiplier_worksGivenCallerHasRiskManagerRole(
        uint _newBaseMultiplier
    ) public {
        vm.assume(
            _newBaseMultiplier
                != bondingCurveFundingManager.basePriceMultiplier()
        );
        _newBaseMultiplier = bound(_newBaseMultiplier, 1, 1e18);

        // Execute Tx
        bondingCurveFundingManager.setBasePriceMultiplier(_newBaseMultiplier);

        // Get current state value
        uint stateValue = bondingCurveFundingManager.basePriceMultiplier();

        // Assert state has been updated
        assertEq(stateValue, _newBaseMultiplier);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /*  Test _issueTokensFormulaWrapper()
        ├── Given: capital available == 0
        │   └── When: the function _issueTokensFormulaWrapper() gets called
        │       └── Then: it should revert
        └── Given: capital available > 0
            └── When: the function _issueTokensFormulaWrapper() gets called
                └── Then: it should return the same as formula.tokenIn
    */

    function testInternalIssueTokensFormulaWrapper_revertGivenCapitalAvailableIsZero(
    ) public {
        uint _depositAmount = 1;

        // Transfer all capital that is in the bonding curve funding manager
        vm.prank(address(bondingCurveFundingManager));
        _token.transfer(seller, MIN_RESERVE);

        // Execute Tx
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__NoCapitalAvailable
                .selector
        );
        bondingCurveFundingManager.exposed_issueTokensFormulaWrapper(
            _depositAmount
        );
    }

    function testInternalIssueTokensFormulaWrapper_works(uint _depositAmount)
        public
    {
        // Setup
        // protect agains overflow
        _depositAmount = bound(
            _depositAmount,
            1,
            1e36 - bondingCurveFundingManager.exposed_getCapitalAvailable()
        );

        // Get expected return value
        uint expectedReturnValue = IBondingSurface(formula).tokenOut(
            _depositAmount,
            bondingCurveFundingManager.exposed_getCapitalAvailable(),
            bondingCurveFundingManager.basePriceToCapitalRatio()
        );
        // Actual return value
        uint functionReturnValue = bondingCurveFundingManager
            .exposed_issueTokensFormulaWrapper(_depositAmount);

        // Assert eq
        assertEq(functionReturnValue, expectedReturnValue);
    }

    /*  Test _redeemTokensFormulaWrapper()
        ├── Given: capital available == 0
        │   └── When: the function _redeemTokensFormulaWrapper() gets called
        │       └── Then: it should revert
        ├── Given: (capitalAvailable - redeemAmount) < MIN_RESERVE
        │   └── When: the function _redeemTokensFormulaWrapper() gets called
        │       └── Then: it should return (capitalAvailable - MIN_RESERVE) instead of redeemAmount
        └── Given: (capitalAvailable - redeemAmount) >= MIN_RESERVE
            └── When: the function _redeemTokensFormulaWrapper() gets called
                └── Then: it should return redeemAmount
    */

    function testInternalRedeemTokensFormulaWrapper_revertGivenCapitalAvailableIsZero(
    ) public {
        uint _depositAmount = 1;

        // Transfer all capital that is in the bonding curve funding manager
        vm.prank(address(bondingCurveFundingManager));
        _token.transfer(seller, MIN_RESERVE);

        // Execute Tx
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__NoCapitalAvailable
                .selector
        );
        bondingCurveFundingManager.exposed_redeemTokensFormulaWrapper(
            _depositAmount
        );
    }

    function testInternalRedeemTokensFormulaWrapper_worksGivenItReturnsCapitalAvailableMinusMinReserve(
        uint _depositAmount
    ) public {
        // protect agains overflow
        _depositAmount = bound(_depositAmount, 1, 1e36 - MIN_RESERVE);

        // Calculate expected return value. Because capital available == MIN_RESERVE, any redeem amount
        // triggers a change in return value as the balance may never dip below MIN_RESERVE, making the return
        // value 0
        uint expectedReturnValue = bondingCurveFundingManager
            .exposed_getCapitalAvailable() - MIN_RESERVE;

        // Get return value
        uint functionReturnValue = bondingCurveFundingManager
            .exposed_redeemTokensFormulaWrapper(_depositAmount);

        // Assert equal
        assertEq(functionReturnValue, expectedReturnValue);
    }

    function testInternalRedeemTokensFormulaWrapper_worksGivenItReturnsRedeemAmount(
        uint _depositAmount
    ) public {
        // protect agains under/overflow
        _depositAmount = bound(
            _depositAmount,
            1e16,
            1e36 - bondingCurveFundingManager.exposed_getCapitalAvailable()
        );
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _depositAmount
        );

        // Get expected return value
        uint redeemAmount = IBondingSurface(formula).tokenIn(
            _depositAmount,
            bondingCurveFundingManager.exposed_getCapitalAvailable(),
            bondingCurveFundingManager.basePriceToCapitalRatio()
        );
        // Get return value
        uint functionReturnValue = bondingCurveFundingManager
            .exposed_redeemTokensFormulaWrapper(_depositAmount);

        // Because of precision loss, the assert is done to be in range of 0.0000000001% of each other
        assertApproxEqRel(functionReturnValue, redeemAmount, 0.0000000001e18);
    }

    /*  Test internal _getCapitalAvailable()
        └── When the function _getCapitalAvailable() is called
            └── Then it should return balance of contract - project fee collected
    */

    function testInternalGetCapitalAvailable_worksGivenValueReturnedHasFeeSubtracted(
        uint _amount
    ) public {
        // Setup
        // Collateral amount
        _amount = bound(_amount, 1, 1e36);
        // Fee collected of 2%
        uint _projectCollateralFeeCollected = _amount * 200 / 10_000;
        // Mint collateral to funding manager
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager),
            _amount + _projectCollateralFeeCollected
        );
        // Set project fee collected through helper
        _setProjectCollateralFeeCollectedHelper(_projectCollateralFeeCollected);

        // Get state value of fee collected
        uint feeCollected =
            bondingCurveFundingManager.projectCollateralFeeCollected();
        // Calculate expected return value
        uint expectedReturnValue =
            _token.balanceOf(address(bondingCurveFundingManager)) - feeCollected;
        // Get return value
        uint returnValue =
            bondingCurveFundingManager.exposed_getCapitalAvailable();

        // Assert value
        assertEq(returnValue, expectedReturnValue);
    }

    /*  Test _setCapitalRequired()
        ├── Given: the parameter _newCapitalRequired == 0
        │   └── When: the function _setCapitalRequired() is called
        │       └── Then: it should revert
        └── Given: the parameter _newCapitalRequired > 0
            └── When: the function _setCapitalRequired() is called
                └── Then: it should succeed in writing the new value to state
                    ├── And: it should emit an event
                    └── And: it should call _updateVariables() to update basePriceToCapitalRatio
     */

    function testInternalSetCapitalRequired_revertGivenValueIsZero() public {
        // Set invalid value
        uint capitalRequirements = 0;
        // Expect Revert
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount
                .selector
        );
        bondingCurveFundingManager.exposed_setBasePriceMultiplier(
            capitalRequirements
        );
    }

    function testInternalSetCapitalRequired_worksGivenValueIsNotZero(
        uint _capitalRequirements
    ) public {
        _capitalRequirements = bound(_capitalRequirements, 1, 1e18);

        // Get current value for expected emit
        uint currentCapitalRequirements =
            bondingCurveFundingManager.capitalRequired();

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_v1.CapitalRequiredChanged(
            currentCapitalRequirements, _capitalRequirements
        );
        bondingCurveFundingManager.exposed_setCapitalRequired(
            _capitalRequirements
        );

        // Get assert values
        uint expectUpdatedCapitalRequired =
            bondingCurveFundingManager.capitalRequired();
        uint expectbasePriceToCapitalRatio = bondingCurveFundingManager
            .exposed_calculateBasePriceToCapitalRatio(
            _capitalRequirements,
            bondingCurveFundingManager.basePriceMultiplier()
        );
        uint actualBasePriceToCapitalRatio =
            bondingCurveFundingManager.basePriceToCapitalRatio();

        // Assert value has been set succesfully
        assertEq(expectUpdatedCapitalRequired, _capitalRequirements);
        // Assert _updateVariables has been called succesfully
        assertEq(expectbasePriceToCapitalRatio, actualBasePriceToCapitalRatio);
    }

    /*    Test _setSeize()
        ├── Given: the parameter _seize > MAX_SEIZE
        │   └── When: the function _setSeize() gets called
        │       └── Then: it should revert
        └── Given: the parameter _seize <= MAX_SEIZE
            └── When: the function _setSeize() gets called
                └── Then: it should emit an event
                    └── And: it should succeed in writing a new value to state
    */

    /*  Test _setBasePriceMultiplier()
        ├── Given: the parameter _newBasePriceMultiplier == 0
        │   └── When: the function _setBasePriceMultiplier() is called
        │       └── Then: it should revert
        └── Given: the parameter _newBasePriceMultiplier > 0
            └── When: the function _setBasePriceMultiplier() is called
                └── Then: it should succeed in writing the new value to state
                    ├── And: it should emit an event
                    └── And: it should call _updateVariables() to update basePriceToCapitalRatio
     */

    function testInternalSetBasePriceMultiplier_revertGivenValueIsZero()
        public
    {
        // Set invalid value
        uint basePriceMultiplier = 0;
        // Expect Revert
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount
                .selector
        );
        bondingCurveFundingManager.exposed_setBasePriceMultiplier(
            basePriceMultiplier
        );
    }

    function testInternalSetBasePriceMultiplier_worksGivenValueIsNotZero(
        uint _basePriceMultiplier
    ) public {
        // Set capital required to fixed value so no revert can happen when fuzzing basePriceMultiplier
        uint capitalRequirement = 1e18;
        _basePriceMultiplier = bound(_basePriceMultiplier, 1, 1e18);

        // setup
        bondingCurveFundingManager.setCapitalRequired(capitalRequirement);

        // Get current value for expected emit
        uint currentBasePriceMultiplier =
            bondingCurveFundingManager.basePriceMultiplier();

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_v1.BasePriceMultiplierChanged(
            currentBasePriceMultiplier, _basePriceMultiplier
        );
        bondingCurveFundingManager.exposed_setBasePriceMultiplier(
            _basePriceMultiplier
        );

        // Get assert values
        uint expectUpdatedBasePriceMultiplier =
            bondingCurveFundingManager.basePriceMultiplier();
        uint expectbasePriceToCapitalRatio = bondingCurveFundingManager
            .exposed_calculateBasePriceToCapitalRatio(
            capitalRequirement, _basePriceMultiplier
        );
        uint actualBasePriceToCapitalRatio =
            bondingCurveFundingManager.basePriceToCapitalRatio();

        // Assert value has been set succesfully
        assertEq(expectUpdatedBasePriceMultiplier, _basePriceMultiplier);
        // Assert _updateVariables has been called succesfully
        assertEq(expectbasePriceToCapitalRatio, actualBasePriceToCapitalRatio);
    }

    /*    Test _setTokenVault()
        └── Given: the function _setTokenVault() gets called
            ├── When: the given address is address(0)
            │   └── Then is should revert
            └── When: the given address is not address(0)
                └── Then: it should set the token vault address to the given address
    */

    function testCalculatebasePriceToCapitalRatio_revertGivenCalculationResultBiggerThan1ToPower36(
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) public {
        // Set bounds so when values used for calculation, the result is > 1e36
        _capitalRequirements = bound(_capitalRequirements, 1, 1e18); // Lower minimum bound
        _basePriceMultiplier = bound(_basePriceMultiplier, 1e37, 1e38); // Higher minimum bound

        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAmount
                .selector
        );
        bondingCurveFundingManager.exposed_calculateBasePriceToCapitalRatio(
            _capitalRequirements, _basePriceMultiplier
        );
    }

    function testCalculatebasePriceToCapitalRatio_worksGivenCalculationResultLowerThan1ToPower36(
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) public {
        // Set bounds so when values used for calculation, the result < 1e36
        _capitalRequirements = bound(_capitalRequirements, 1, 1e18);
        _basePriceMultiplier = bound(_basePriceMultiplier, 1, 1e18);

        // Use calculation for expected return value
        uint expectedReturnValue = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequirements, FixedPointMathLib.WAD
        );

        // Get function return value
        uint functionReturnValue = bondingCurveFundingManager
            .exposed_calculateBasePriceToCapitalRatio(
            _capitalRequirements, _basePriceMultiplier
        );

        // Assert expected return value
        assertEq(functionReturnValue, expectedReturnValue);
    }

    /*    Test _updateVariables()
        └── Given: the function _updateVariables() gets called
            └── Then: it should emit an event
                └── And: it should update the state variable basePriceToCapitalRatio
    */

    function testUpdateVariables_worksGivenBasePriceToCapitalRatioStateIsSet(
        uint _capitalRequirements,
        uint _basePriceMultiplier
    ) public {
        // Set bounds so when values used for calculation, the result < 1e36
        _capitalRequirements = bound(_capitalRequirements, 1, 1e18);
        _basePriceMultiplier = bound(_basePriceMultiplier, 1, 1e18);

        // Setup
        bondingCurveFundingManager.setBasePriceMultiplier(_basePriceMultiplier);
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);

        // Use calculation for expected return value
        uint expectedReturnValue = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequirements, FixedPointMathLib.WAD
        );
        uint currentBasePriceToCapitalRatio =
            bondingCurveFundingManager.basePriceToCapitalRatio();

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_v1.BasePriceToCapitalRatioChanged(
            currentBasePriceToCapitalRatio, expectedReturnValue
        );
        bondingCurveFundingManager.exposed_updateVariables();
        // Get set state value
        uint setStateValue =
            bondingCurveFundingManager.basePriceToCapitalRatio();

        // Assert expected return value
        assertEq(setStateValue, expectedReturnValue);
    }

    //--------------------------------------------------------------------------
    // Test Helper Functions

    function _mintIssuanceTokenToAddressHelper(address _account, uint _amount)
        internal
    {
        bondingCurveFundingManager.exposed_mint(_account, _amount);
    }

    function _mintCollateralTokenToAddressHelper(address _account, uint _amount)
        internal
    {
        vm.prank(owner_address);
        _token.mint(_account, _amount);
    }

    function _buyTokensForSetupHelper(address _buyer, uint _amount) internal {
        vm.startPrank(_buyer);
        {
            _token.approve(address(bondingCurveFundingManager), _amount);
            bondingCurveFundingManager.buy(_amount, 0); // Not testing actual return values here, so minAmount out can be 0
        }
        vm.stopPrank();
    }

    function _sellTokensForSetupHelper(address _seller, uint _amount)
        internal
    {
        vm.startPrank(_seller);
        {
            issuanceToken.approve(address(bondingCurveFundingManager), _amount);
            bondingCurveFundingManager.sell(_amount, 0); // Not testing actual return values here, so minAmount out can be 0
        }
        vm.stopPrank();
    }

    function _setProjectCollateralFeeCollectedHelper(uint _amount) internal {
        bondingCurveFundingManager.exposed_projectCollateralFeeCollected(
            _amount
        );
    }
}
