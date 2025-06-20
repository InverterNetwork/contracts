// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {
    IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2,
    FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2,
    IFundingManager_v1,
    IIssuanceBase_v2
} from
    "@fm/bondingCurve/FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2.sol";

import {IFM_BC_QuadraticPrice_Redeeming_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_v2.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

import {IERC165} from "@oz/utils/introspection/IERC165.sol";

// Internal Dependencies
import {
    ModuleTest,
    IModule_v2,
    IOrchestrator_v2
} from "@unitTest/modules/ModuleTest.sol";
import {QuadraticPriceFormula} from
    "@fm/bondingCurve/formulas/QuadraticPriceFormula.sol";
import {IIssuanceBase_v2} from
    "@fm/bondingCurve/interfaces/IIssuanceBase_v2.sol";
import {
    IRedeemingIssuanceBase_v2,
    IRedeemingIssuanceBase_v2
} from "@fm/bondingCurve/abstracts/RedeemingIssuanceBase_v2.sol";
import {IQuadraticPriceFormula} from
    "@fm/bondingCurve/interfaces/IQuadraticPriceFormula.sol";
import {IFM_BC_QuadraticPrice_Redeeming_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_v2.sol";
import {IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2} from
    "@fm/bondingCurve/interfaces/IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2.sol";
import {IRepayer_v1} from "@fm/bondingCurve/interfaces/IRepayer_v1.sol";
import {FixedPointMathLib} from "src/modules/lib/FixedPointMathLib.sol";

// Errors
import {OZErrors} from "@testUtilities/OZErrors.sol";

// Mocks
import {
    FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed
} from
    "@mocks/modules/fundingManager/bondingCurve/FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed.sol";

/*     
    PLEASE NOTE: The following tests have been tested in other test contracts 
    - buy() & buyOrderFor()
    - sell() & sellOrderFor()
    */
contract FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2_Test is
    ModuleTest
{
    string private constant NAME = "Topos Token";
    string private constant SYMBOL = "TPG";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    uint private constant CAPITAL_REQUIREMENT = 1_000_000 * 1e18; // Taken from Topos repo test case

    uint private constant BUY_FEE = 100;
    uint private constant SELL_FEE = 100;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;
    bool private constant BUY_AND_SELL_IS_RESTRICTED = false;
    uint32 private constant BPS = 10_000;

    uint private MIN_RESERVE = 10 ** _token.decimals();
    uint64 private constant MAX_SEIZE = 100;
    uint64 private constant MAX_SELL_FEE = 100;
    uint private constant BASE_PRICE_MULTIPLIER = 0.000001 ether;
    uint64 private constant SEIZE_DELAY = 7 days;

    FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed
        bondingCurveFundingManager;
    address formula;
    ERC20Issuance_v1 issuanceToken;

    // Addresses
    address owner_address = address(0xA1BA);
    address liquidityVaultController = makeAddr("liquidityVaultController");
    address nonAuthorizedBuyer = makeAddr("nonAuthorizedBuyer");
    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address burner = makeAddr("burner");
    address tokenVault = makeAddr("tokenVault");

    function setUp() public {
        // Deploy contracts
        issuanceToken = new ERC20Issuance_v1(NAME, SYMBOL, DECIMALS, MAX_SUPPLY);
        issuanceToken.setMinter(address(this), true);

        FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
            .BondingCurveProperties memory bc_properties;

        // Deploy formula and cast to address for encoding
        QuadraticPriceFormula QuadraticPriceFormula =
            new QuadraticPriceFormula();
        formula = address(QuadraticPriceFormula);

        // Set Formula contract properties
        bc_properties.formula = formula;
        bc_properties.capitalRequired = CAPITAL_REQUIREMENT;
        bc_properties.basePriceMultiplier = BASE_PRICE_MULTIPLIER;

        // Set pAMM properties
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;

        address impl = address(
            new FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            )
        );

        bondingCurveFundingManager =
        FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            Clones.clone(impl)
        );

        _setUpOrchestrator(bondingCurveFundingManager);

        // Every caller has permission for every permissioned function
        _authorizer.setAllAuthorized(true);

        // Set Minter
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                address(_token), // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                bc_properties,
                liquidityVaultController,
                MAX_SEIZE,
                BUY_AND_SELL_IS_RESTRICTED
            )
        );
        // Mint minimal reserve necessary to operate the BC
        _token.mint(
            address(bondingCurveFundingManager),
            bondingCurveFundingManager.MIN_RESERVE()
        );
    }

    // -------------------------------------------------------------------------
    // Test: Initialization

    //This function also tests all the getters
    // -------------------------------------------------------------------------
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
        // MIN_RESERVE
        assertEq(
            bondingCurveFundingManager.MIN_RESERVE(),
            MIN_RESERVE,
            "MIN_RESERVE has not been set correctly"
        );
        // MIN_RESERVE
        assertEq(
            bondingCurveFundingManager.MIN_RESERVE(),
            MIN_RESERVE,
            "MIN_RESERVE has not been set correctly"
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
            bondingCurveFundingManager.getQuadraticPriceFormulaFormula(),
            formula,
            "Formula has not been set correctly"
        );
        assertEq(
            bondingCurveFundingManager.getCapitalRequired(),
            CAPITAL_REQUIREMENT,
            "Initial capital requirements has not been set correctly"
        );
        // Liquidity Vault Controller
        assertEq(
            address(bondingCurveFundingManager.getLiquidityVaultController()),
            liquidityVaultController,
            "Initial liquidity vault controller has not been set correctly"
        );
        // Reserve Pool
        assertEq(
            address(bondingCurveFundingManager.getTokenVault()),
            address(0),
            "Initial reserve pool has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    /*
    Test: Init
    └── Given: decimals_ are not 18
        └── When: the function init is called
            └── Then: it should adapt the MIN_RESERVE accordingly
    */

    function testInit_GivenDecimalsAreNot18(uint8 decimals_) public {
        //uint 256 only has 77 Decimals
        if (decimals_ == 1 || decimals_ > 77) decimals_ = 1;

        // set new decimals
        _token.setDecimals(decimals_);

        // Setup bondingCurve properties
        IFM_BC_QuadraticPrice_Redeeming_v2.BondingCurveProperties memory
            bc_properties;

        // Deploy formula and cast to address for encoding
        QuadraticPriceFormula QuadraticPriceFormula =
            new QuadraticPriceFormula();
        formula = address(QuadraticPriceFormula);

        // Set Formula contract properties
        bc_properties.formula = formula;
        bc_properties.capitalRequired = CAPITAL_REQUIREMENT;
        bc_properties.basePriceMultiplier = BASE_PRICE_MULTIPLIER;

        // Set pAMM properties
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.buyFee = BUY_FEE;
        bc_properties.sellFee = SELL_FEE;

        address impl = address(
            new FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            )
        );

        bondingCurveFundingManager =
        FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            Clones.clone(impl)
        );

        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                address(_token), // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                bc_properties,
                liquidityVaultController,
                MAX_SEIZE,
                BUY_AND_SELL_IS_RESTRICTED
            )
        );

        //assert that MIN_RESERVE is set correctly
        assertEq(
            bondingCurveFundingManager.MIN_RESERVE(),
            10 ** decimals_,
            "MIN_RESERVE has not been set correctly"
        );
    }

    // -------------------------------------------------------------------------
    // Modifiers

    /*
    Test: OnlyLiquidityVaultController Modifier
    └── Given: the caller_ is not the liquidityVaultController
        └── When: the function buy() is called
            └── Then: it should revert
     */

    function testOnlyLiquidityVaultControllerModifier(
        address caller_,
        bool isLiquidityVaultController_
    ) public {
        vm.assume(caller_ != liquidityVaultController);
        if (isLiquidityVaultController_) {
            caller_ = liquidityVaultController;
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                        .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidLiquidityVaultController
                        .selector,
                    caller_
                )
            );
        }

        vm.prank(caller_);
        bondingCurveFundingManager.exposed_onlyLiquidityVaultControllerModifier(
        );
    }

    // ========================================================================
    // Init Functions

    /*
    Test: Init fails for invalid formula
    └── When: the formula in BondingCurveProperties is not a valid QuadraticPriceFormula
        └── Then: it should revert
    */

    function testInitFailsForInvalidFormula() public {
        IFM_BC_QuadraticPrice_Redeeming_v2.BondingCurveProperties memory
            bc_properties;
        bc_properties.formula = address(
            new FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            )
        );

        address impl = address(
            new FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            )
        );

        bondingCurveFundingManager =
        FM_BC_QuadraticPriceFormula_Redeeming_Restricted_Repayer_Seizable_v2_Exposed(
            Clones.clone(impl)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_v2
                    .FM_BC_QuadraticPrice_Redeeming_v2__InvalidQuadraticPriceFormulaFormula
                    .selector
            )
        );

        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                address(_token), // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                bc_properties,
                liquidityVaultController,
                MAX_SEIZE,
                BUY_AND_SELL_IS_RESTRICTED
            )
        );
    }

    // -------------------------------------------------------------------------
    // Tests: Supports Interface

    function testSupportsInterface() public override(ModuleTest) {
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(
                    IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                ).interfaceId
            )
        );
        assertTrue(
            bondingCurveFundingManager.supportsInterface(
                type(IRepayer_v1).interfaceId
            )
        );
    }

    // ========================================================================
    // Public Getter Functions

    // -------------------------------------------------------------------------
    // Implementation Specific Public Functions

    /*  Test seizable()
        └── When: the function seizable() gets called
            └── Then: it should return the correct seizable amount
    */

    function testSeizable_works(uint tokenBalance_, uint64 seize_) public {
        tokenBalance_ =
            bound(tokenBalance_, 1, (UINT256_MAX - MIN_RESERVE) / 1000); // to protect agains overflow if max balance * max seize
        seize_ =
            uint64(bound(seize_, 1, bondingCurveFundingManager.MAX_SEIZE()));
        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // mint collateral to funding manager
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), tokenBalance_
        );
        // set seize in contract
        bondingCurveFundingManager.adjustSeize(seize_);

        // calculate return value
        uint expectedReturnValue =
            ((tokenBalance_ + tokenBalanceFundingMangerBaseline) * seize_) / BPS;

        // Execute tx
        uint returnValue = bondingCurveFundingManager.getSeizableAmount();

        // Assert right return value
        assertEq(returnValue, expectedReturnValue);
    }

    /*  Test getRepayableAmount()
        └── When: the function getRepayableAmount() gets called
            └── Then: it should return the return value of _getRepayableAmount()
    */

    function testPublicGetRepayableAmount_works() public {
        // get return value from internal function
        uint internalFunctionResult =
            bondingCurveFundingManager.exposed_getRepayableAmount();
        // Get return value from public function
        uint publicFunctionResult =
            bondingCurveFundingManager.getRepayableAmount();
        // Assert they are equal
        assertEq(internalFunctionResult, publicFunctionResult);
    }

    // ========================================================================
    // Public Mutating Functions

    // ------------------------------------------------------------------------
    // Mutating - Permissioned Functions

    /*  Test burnIssuanceToken()
        ├── Given: caller is not permissioned
        │   └── When: the function burnIssuanceToken() gets called
        │       └── Then: it should revert (modifier in position)
        ├── Given: amount_ > msg.sender balance of issuance token
        │   └── When: the function burnIssuanceToken() gets called
        │       └── Then: it should revert
        └── Given: amount_ <= msg.sender balance of issuance token
            └── When: the function burnIssuanceToken() gets called
                └── Then: it should burn amount_ from msg.sender's balance
    */
    function testBurnIssuanceToken_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.burnIssuanceToken(0);
    }

    function testBurnIssuanceToken_revertGivenAmountBiggerThanMsgSenderBalance(
        uint amount_
    ) public {
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // balance of the burner
        uint burnerTokenBalance = amount_ - 1;
        // mint issuance token to user for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when balance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceToken(amount_);
        }
    }

    function testBurnIssuanceToken_worksGivenAmountLowerThanMsgSenderBalance(
        uint amount_
    ) public {
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // balance of the burner
        uint burnerTokenBalance = amount_ + 1;
        // mint issuance token to user for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Assert right amount has been minted
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceToken(amount_);

        // Assert right amount has been burned
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance - amount_);
    }

    /*  Test burnIssuanceTokenFor()
        ├── Given: caller is not permissioned
        │   └── When: the function burnIssuanceToken() gets called
        │       └── Then: it should revert (modifier in position)
        ├── Given: _owner != msg.sender
        │   ├── And: the allowance < amount_
        │   │   └── When: the function burnIssuanceTokenFor() gets called
        │   │       └── Then: it should revert
        │   └── And: msg.sender allowance > amount_
        │       ├── And: _owner balance < amount_
        │       │   └── When: the function burnIssuanceTokenFor() gets called
        │       │       └── Then: it should revert
        │       └── And: _owner balance > amount_
        │           └── When: the function burnIssuanceTokenFor() gets called
        │                └── Then: it should burn amount_ tokens from the _owner
        └── Given: _owner == msg.sender
            ├── And: amount_ > _owner balance of issuance token
            │   └── When: the function burnIssuanceToken() gets called
            │       └── Then: it should revert
            └── And: amount_ <= _owner balance of issuance token
                └── When: the function burnIssuanceToken() gets called
                    └── Then: it should burn amount_ from _owner's balance
    */
    function testBurnIssuanceTokenFor_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.burnIssuanceTokenFor(address(0), 0);
    }

    function testBurnIssuanceTokenFor_revertGivenAmountHigherThanOwnerAllowance(
        uint amount_
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = amount_;
        // mint issuance token to tokenOwner for burning
        _mintIssuanceTokenToAddressHelper(tokenOwner, ownerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(tokenOwner), ownerTokenBalance);
        // Approve less than amount to burner address
        vm.prank(tokenOwner);
        issuanceToken.approve(burner, amount_ - 1);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when allowance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, amount_);
        }
    }

    function testBurnIssuanceTokenFor_revertGivenAmountBiggerThanOwnerBalance(
        uint amount_
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = amount_ - 1;
        // mint issuance token to tokenOwner for burning
        _mintIssuanceTokenToAddressHelper(tokenOwner, ownerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(tokenOwner), ownerTokenBalance);
        // Approve tokenOwner balance to burner
        vm.prank(tokenOwner);
        issuanceToken.approve(burner, ownerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when allowance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, amount_);
        }
    }

    function testBurnIssuanceTokenFor_worksGivenOwnerIsNotMsgSender(
        uint amount_
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = amount_ + 1;
        // mint issuance token to tokenOwner for burning
        _mintIssuanceTokenToAddressHelper(tokenOwner, ownerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(tokenOwner), ownerTokenBalance);
        // Approve tokenOwner balance to burner
        vm.prank(tokenOwner);
        issuanceToken.approve(burner, ownerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, amount_);

        // Assert right amount has been burned
        assertEq(
            issuanceToken.balanceOf(tokenOwner), ownerTokenBalance - amount_
        );
    }

    function testBurnIssuanceTokenFor_revertGivenAmountBiggerThanMsgSenderBalance(
        uint amount_
    ) public {
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // balance of burner
        uint burnerTokenBalance = amount_ - 1;
        // mint issuance token to burner for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when balance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceTokenFor(burner, amount_);
        }
    }

    function testBurnIssuanceTokenFor_worksGivenMsgSenderIsNotOwner(
        uint amount_
    ) public {
        // bound value to max uint - 1
        amount_ = bound(amount_, 1, UINT256_MAX - 1);
        // Balance of burner
        uint burnerTokenBalance = amount_ + 1;
        // mint issuance token to burner for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceTokenFor(burner, amount_);

        // Assert right amount has been burned
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance - amount_);
    }

    /*  Test seize()
        ├── Given: the calleris not permissioned
        │   └── When: the function seize() gets called
        │       └── Then: it should revert (modifier in position)
        └── Given: the caller_ is permissioned
            ├── And: the parameter amount_ > the seizable amount
            │   └── When: the function seize() gets called
            │       └── Then: it should revert
            ├── And: the lastSeizeTimestamp + SEIZE_DELAY > block.timestamp
            │   └── When: the function seize() gets called
            │       └── Then: it should revert
            ├── And: the capital available - amount_ < MIN_RESERVE
            │   └── When: the function seize() gets called
            │       └── Then: it should transfer the value of capitalAvailable - MIN_RESERVE tokens to the msg.sender
            │           ├── And: it should set the current timeStamp to lastSeizeTimestamp
            │           └── And: it should emit an event
            └── And: the capital available - amount_ > MIN_RESERVE
                └── And: the lastSeizeTimestamp + SEIZE_DELAY < block.timestamp
                    └── When: the function seize() gets called
                        └── Then: it should transfer the value of amount_ tokens to the msg.sender
                            ├── And: it should set the current timeStamp to lastSeizeTimestamp
                            └── And: it should emit an event
    */
    function testSeize_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.seize(0);
    }

    function testSeize_revertGivenAmountBiggerThanSeizableAmount(uint amount_)
        public
    {
        uint currentSeizable = bondingCurveFundingManager.getSeizableAmount();
        vm.assume(amount_ > currentSeizable);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                    .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeizeAmount
                    .selector,
                currentSeizable
            )
        );
        bondingCurveFundingManager.seize(amount_);
    }

    function testSeize_revertGivenLastSeizeTimerNotReset() public {
        uint seizeAmount = 1 ether;
        // Setup
        // Mint collateral for enough capital available
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), seizeAmount * 100
        );
        // Check Seize timestamp before calling function
        uint seizeTimestampBefore =
            bondingCurveFundingManager.getLastSeizeTimestamp();

        // Assert expected fail. block.timestamp == 1 without setting it in vm.warp
        assertGt((seizeTimestampBefore + SEIZE_DELAY), block.timestamp);

        // Execute Tx expecting it to revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                    .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__SeizeTimeout
                    .selector,
                (
                    seizeTimestampBefore
                        + bondingCurveFundingManager.SEIZE_DELAY()
                )
            )
        );
        bondingCurveFundingManager.seize(seizeAmount);
    }

    function testSeize_worksGivenCapitalAvailableMinusMinReserveIsReturned()
        public
    {
        // Setup
        // Set block.timestamp to valid time
        vm.warp(SEIZE_DELAY + 1);
        // Amount has to be smaller than seizable amount which is (currentBalance * currentSeize) / BPS
        // i.e. (1 ether * 200 ) / 10_000
        uint amount = 1e16; // 0.01 ether
        // Return value check for emit. Expected return is 0. Capital available - MIN_RESERVE
        uint expectedReturnValue = bondingCurveFundingManager
            .exposed_getCapitalAvailable() - MIN_RESERVE;
        assertEq(expectedReturnValue, 0);

        //Get balance before seize
        uint balanceBeforeBuy = _token.balanceOf(address(this));

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
            .CollateralSeized(expectedReturnValue);
        bondingCurveFundingManager.seize(amount);

        // Assert that no tokens have been sent
        assertEq(balanceBeforeBuy, balanceBeforeBuy);
    }

    function testSeize_worksGivenCapitalAmountIsReturnd(uint amount_) public {
        // Setup
        // Set block.timestamp to valid time
        vm.warp(SEIZE_DELAY + 1);
        // Bound seizable value
        amount_ = bound(amount_, 1, type(uint128).max);
        // Mint enough surplus so seizing can happen
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), amount_ * 10_000
        );
        //Get balance before seize
        uint balanceBeforeBuy = _token.balanceOf(address(this));

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
            .CollateralSeized(amount_);
        bondingCurveFundingManager.seize(amount_);

        // Get balance after buying
        uint balanceAfterBuy = _token.balanceOf(address(this));
        // Assert that no tokens have been sent
        assertEq(balanceAfterBuy, balanceBeforeBuy + amount_);
    }

    /*    Test adjust size
        ├── Given: the caller_ is not permissioned
        │   └── When: the function adjustSeize() gets called
        │       └── Then: it should revert (modifier in position)
        └── Given: the caller_ is permissioned
                └── When: the function adjustSeize() gets called
                    └── Then: it should call the internal function and set the state
    */

    function testAdjustSeize_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));

        bondingCurveFundingManager.adjustSeize(0);
    }

    function testAdjustSeize_permissioned(uint64 seize_) public {
        vm.assume(seize_ != bondingCurveFundingManager.getCurrentSeize());
        seize_ = uint64(bound(seize_, 1, MAX_SEIZE));

        // Execute Tx
        bondingCurveFundingManager.adjustSeize(seize_);

        assertEq(bondingCurveFundingManager.getCurrentSeize(), seize_);
    }

    /*  Test setliquidityVaultControllerContract()
        ├── Given: the caller_ is not permissioned
        │   └── When: the function setliquidityVaultControllerContract() gets called
        │       └── Then: it should revert (modifier in position)
        └── Given: the caller_ is permissioned
            ├── And: _lp == address(0)
            │   └── When: the function setliquidityVaultController() gets called
            │       └── Then: it should revert
            └── And: _lp != address(0)
                └── When: the function setliquidityVaultController() gets called
                    └── Then: it should set the state liquidityVaultController to _lp
                        └── And: it should emit an event
    */
    function testSetliquidityVaultControllerContract_ModifierInPosition()
        public
    {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.setLiquidityVaultControllerContract(
            address(0)
        );
    }

    function testSetliquidityVaultControllerContract_revertGivenAddressIsZero()
        public
    {
        address lvc_ = address(0);

        // Expect Revert
        vm.expectRevert(
            IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidInputAddress
                .selector
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(lvc_);
    }

    function testSetliquidityVaultControllerContract_revertGivenAddressIsEqualToFM(
    ) public {
        address lvc = address(bondingCurveFundingManager);

        // Expect Revert
        vm.expectRevert(
            IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidInputAddress
                .selector
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(lvc);
    }

    function testSetliquidityVaultControllerContract_permissioned(address lvc_)
        public
    {
        vm.assume(
            lvc_ != address(0) && lvc_ != address(bondingCurveFundingManager)
        );

        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
            .LiquidityVaultControllerChanged(
            address(lvc_), liquidityVaultController
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(lvc_);
    }

    /*  Test setRepayableAmount()
        ├── Given: the caller_ is not permissioned
        │   └── When: the function setRepayableAmount() gets called
        │       └── Then: it should revert (modifier in position)
        └── Given: the caller_ is permissioned
            ├── And: amount_ > either capitalAvailable or capitalRequirements
            │   └── When: the function setRepayableAmount() gets called
            │       └── Then: it should revert
            └── And: amount_ <= either capitalAvailable or capitalRequirements
                └── When: the function setRepayableAmount() gets called
                    └── Then: it should set the state of repayableAmount to amount_
                        └── And: it should emit an event
    */
    function testSetRepayableAmount_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.setRepayableAmount(0);
    }

    function testSetRepayableAmount_permissioned(uint amount_) public {
        amount_ = bound(
            amount_,
            bondingCurveFundingManager.exposed_getSmallerCaCr() + 1,
            type(uint).max
        );

        // Execute Tx
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_v2
                    .FM_BC_QuadraticPrice_Redeeming_v2__InvalidInputAmount
                    .selector
            )
        );
        bondingCurveFundingManager.setRepayableAmount(amount_);
    }

    /* Test: setTokenVault() modifier in position
        └── Given: the caller_ is permissioned
            └── When: the function setTokenVault() gets called
                └── Then: it should revert (modifier in position)
        └── Given: the caller_ is permissioned
            └── When: the function setTokenVault() gets called
                └── Then: it should change the _tokenVault address to the given address
    */
    function testSetTokenVault_ModifierInPosition() public {
        // permissioned

        // Turn off all adresses are permissioned to call all functions
        _authorizer.setAllAuthorized(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v2.Module__CallerNotPermissioned.selector
            )
        );
        vm.prank(address(0xB0B));
        bondingCurveFundingManager.setTokenVault(address(0));
    }

    function testSetTokenVault_permissioned(address _tokenVault) public {
        vm.assume(_tokenVault != address(0));
        vm.assume(_tokenVault != address(bondingCurveFundingManager));
        bondingCurveFundingManager.setTokenVault(_tokenVault);

        assertEq(_tokenVault, bondingCurveFundingManager.getTokenVault());
    }

    // -------------------------------------------------------------------------
    // onlyLiquidityVaultController Functions

    /*  Test transferRepayment()
        ├── Given the caller_ is not the liquidityVaultController
        │   └── When the function transferRepayment() is called
        │       └── Then it should revert
        ├── Given modifier validReceiver(to_) is in place: Please Note: Modifier test can be found in IssuanceBase_v2.t
        │   └── When the function transferRepayment() is called
        │       └── Then it should revert if receiver is invalid
        └── Given: the caller_ is the liquidityVaultController
            └── And: the to_ address is valid
                ├── And: the amount_ > the repayable amount available
                │   └── When: the function transferRepayment() gets called
                │       └── Then: it should revert
                ├── And: the amount_ > the repayable amount available
                │   └── When: the function transferRepayment() gets called
                │       └── Then: it should revert
                └── And: amount_ <= repayable amount available
                    └── When: the function transferRepayment() gets called
                        └── Then: it should transfer amount_ to the to_ address
                            └── And: it should emit an event
    */

    function testTransferPayment_revertGivenCallerIsNotLiquidityVaultController(
        address to_,
        uint amount_
    ) public {
        // Valid to_ address
        vm.assume(
            to_ != liquidityVaultController
                && to_ != address(bondingCurveFundingManager) && to_ != address(0)
        );
        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                        .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidLiquidityVaultController
                        .selector,
                    seller
                )
            );
            bondingCurveFundingManager.transferRepayment(to_, amount_);
        }
    }

    function testTransferPayment_modifierInPlace(uint amount_) public {
        address to = address(0);
        amount_ = bound(amount_, 2, UINT256_MAX - 1);

        // Execute Tx
        vm.startPrank(liquidityVaultController);
        {
            vm.expectRevert(
                IIssuanceBase_v2
                    .Module__BondingCurveBase__InvalidRecipient
                    .selector
            );
            bondingCurveFundingManager.transferRepayment(to, amount_);
        }
    }

    function testTransferPayment_revertGivenAmounBiggerThanRepayableAmount(
        address to_,
        uint amount_
    ) public {
        // Valid to_ address
        vm.assume(
            to_ != liquidityVaultController
                && to_ != address(bondingCurveFundingManager) && to_ != address(0)
        );
        amount_ = bound(amount_, 2, UINT256_MAX - MIN_RESERVE); // Protect agains overflow

        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // set capital available in funding manager
        uint tokenBalanceFundingManager = amount_;
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), tokenBalanceFundingManager
        );
        // Set capital requirement
        bondingCurveFundingManager.setCapitalRequired(amount_);
        // Set repayable amount < amount_
        bondingCurveFundingManager.setRepayableAmount(amount_ - 1);

        // Assert that right amount tokens have been minted to funding manager
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            tokenBalanceFundingMangerBaseline + tokenBalanceFundingManager
        );

        // Execute Tx
        vm.startPrank(liquidityVaultController);
        {
            // Revert when amount_ > repayableAmount
            vm.expectRevert(
                IRepayer_v1
                    .Repayer__InsufficientCollateralForRepayerTransfer
                    .selector
            );
            bondingCurveFundingManager.transferRepayment(to_, amount_);
        }
    }

    function testTransferPayment_revertGivenMinReserveIsReached(
        address to_,
        uint amount_
    ) public {
        // Valid to_ address
        vm.assume(
            to_ != liquidityVaultController
                && to_ != address(bondingCurveFundingManager) && to_ != address(0)
        );
        amount_ = bound(amount_, 1, UINT256_MAX - MIN_RESERVE); // Protect agains overflow

        // Setup
        // set and mint the amount needed for this test.
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), amount_
        );
        // Set capital requirement
        bondingCurveFundingManager.setCapitalRequired(amount_ + MIN_RESERVE);
        // Set repayable amount
        bondingCurveFundingManager.setRepayableAmount(amount_ + MIN_RESERVE);

        // Execute Tx
        vm.prank(liquidityVaultController);
        vm.expectRevert(
            IFM_BC_QuadraticPrice_Redeeming_v2
                .FM_BC_QuadraticPrice_Redeeming_v2__MinReserveReached
                .selector
        );
        bondingCurveFundingManager.transferRepayment(to_, amount_ + MIN_RESERVE);
    }

    function testTransferPayment_worksGivenCallerIsLvcAndAmountIsValid(
        address to_,
        uint amount_
    ) public {
        // Valid to_ address
        vm.assume(
            to_ != liquidityVaultController
                && to_ != address(bondingCurveFundingManager) && to_ != address(0)
        );
        amount_ = bound(amount_, 1, UINT256_MAX - MIN_RESERVE); // Protect agains overflow

        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // set and mint the amount needed for this test.
        uint mintAmountForFundingManager = amount_;
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), mintAmountForFundingManager
        );
        // Set capital requirement
        bondingCurveFundingManager.setCapitalRequired(amount_);
        // Set repayable amount
        bondingCurveFundingManager.setRepayableAmount(amount_);

        // Assert that right amount tokens have been minted to funding manager, i.e. mintAmountForFundingManager + MIN_RESERVE
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            mintAmountForFundingManager + tokenBalanceFundingMangerBaseline
        );
        // Assert that receiver address does not have tokens
        assertEq(_token.balanceOf(to_), 0);

        // Execute Tx
        vm.prank(liquidityVaultController);
        vm.expectEmit(address(bondingCurveFundingManager));
        emit IRepayer_v1.RepaymentTransfer(to_, amount_);
        bondingCurveFundingManager.transferRepayment(to_, amount_);

        // Assert that amount_ tokens have been withdrawn from funding manager
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            tokenBalanceFundingMangerBaseline + mintAmountForFundingManager
                - amount_
        );
        // Assert that receiver has amount_ token
        assertEq(_token.balanceOf(to_), amount_);
    }

    // -------------------------------------------------------------------------
    // Mutating - Out of Order

    /* Test: withdrawProjectCollateralFee
        └── When: the function withdrawProjectCollateralFee() gets called
            └── Then: it should revert

    */
    function testWithdrawProjectCollateralFee_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                    .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidFunctionality
                    .selector
            )
        );
        bondingCurveFundingManager.withdrawProjectCollateralFee(address(0), 0);
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /*    Test _setSeize()
        ├── Given: the parameter seize_ > MAX_SEIZE
        │   └── When: the function _setSeize() gets called
        │       └── Then: it should revert
        └── Given: the parameter seize_ <= MAX_SEIZE
            └── When: the function _setSeize() gets called
                └── Then: it should emit an event
                    └── And: it should succeed in writing a new value to state
    */

    function testInternalSetSeize_revertGivenSeizeBiggerThanMaxSeize(
        uint64 seize_
    ) public {
        vm.assume(seize_ > MAX_SEIZE);

        // Execute Tx
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
                    .FM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2__InvalidSeize
                    .selector,
                seize_
            )
        );
        bondingCurveFundingManager.exposed_setSeize(seize_);
    }

    function testInternalSetSeize_worksGivenSeizeIsValid(uint64 seize_)
        public
    {
        vm.assume(seize_ != bondingCurveFundingManager.getCurrentSeize());
        seize_ = uint64(bound(seize_, 1, MAX_SEIZE));
        uint64 currentSeize = bondingCurveFundingManager.getCurrentSeize();

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_QuadraticPrice_Redeeming_Restricted_Repayer_Seizable_v2
            .SeizeChanged(currentSeize, seize_);
        bondingCurveFundingManager.adjustSeize(seize_);

        assertEq(bondingCurveFundingManager.getCurrentSeize(), seize_);
    }

    /*    Test _setTokenVault()
        └── Given: the function _setTokenVault() gets called
            ├── When: the given address is address(0)
            │   └── Then is should revert
            ├── When: the given address is address(this)
            │   └── Then is should revert
            └── When: the given address is not address(0) or address(this)
                └── Then: it should set the token vault address to the given address
    */

    function testSetTokenVault_revertGivenAddressIsZero() public {
        vm.expectRevert(IModule_v2.Module__InvalidAddress.selector);
        bondingCurveFundingManager.exposed_setTokenVault(address(0));
    }

    function testSetTokenVault_revertGivenAddressIsSameContract() public {
        vm.expectRevert(IModule_v2.Module__InvalidAddress.selector);
        bondingCurveFundingManager.exposed_setTokenVault(
            address(bondingCurveFundingManager)
        );
    }

    function testSetTokenVault_worksGivenAddressIsNotInvalid(address newVault_)
        public
    {
        vm.assume(
            newVault_ != address(0)
                && newVault_ != address(bondingCurveFundingManager)
        );
        // Execute Tx
        bondingCurveFundingManager.exposed_setTokenVault(newVault_);
        // Assert that the token vault address has been set to the given address
        assertEq(bondingCurveFundingManager.getTokenVault(), newVault_);
    }

    /*  Test _getSmallerCaCr()
        ├── Given: the capital available is > capitalRequirement
        │   └── When: the function _getSmallerCaCr() gets called
        │       └── Then: it should return the capitalRequirement
        └── Given: the capital available is < capitalRequirement
            └── When: the function _getSmallerCaCr() gets called
                └── Then: it should return the capitalAvailable
    */

    function testGetSmallerCaCr_worksGivenCapitalAvailableIsBiggerThanCapitalRequirements(
        uint capitalAvailable_,
        uint capitalRequirements_
    ) public {
        capitalAvailable_ =
            bound(capitalAvailable_, 1, UINT256_MAX - MIN_RESERVE); // protect agains overflow
        capitalRequirements_ = bound(capitalRequirements_, 1, capitalAvailable_); // make capital requirements < capital available
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), capitalAvailable_
        );
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);

        uint returnValue = bondingCurveFundingManager.exposed_getSmallerCaCr();

        // Assert that the smaller value got returned
        assertEq(returnValue, capitalRequirements_);
    }

    function testGetSmallerCaCr_worksGivenCapitalRequirementsIsBiggerThanCapitalAvailable(
        uint capitalAvailable_,
        uint capitalRequirements_
    ) public {
        // Set capital requirement above MIN_RESERVE, which is the capital already available
        capitalRequirements_ = bound(
            capitalRequirements_, MIN_RESERVE + 1, UINT256_MAX - MIN_RESERVE
        ); // make capital requirements > capital available
        // set capital available, i.e the to be minted amount for the the test
        capitalAvailable_ =
            bound(capitalAvailable_, MIN_RESERVE, capitalRequirements_);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager),
            (
                capitalAvailable_
                    - _token.balanceOf(address(bondingCurveFundingManager))
            )
        );
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);

        uint returnValue = bondingCurveFundingManager.exposed_getSmallerCaCr();

        // Assert that the smaller value got returned
        assertEq(returnValue, capitalAvailable_);
    }

    /*  Test _getRepayableAmount()
        ├── Given: repayableAmount > the return value _getSmallerCaCr()
        │   └── When: the function _getRepayableAmount() gets called
        │       └── Then: it should return the return value of _getSmallerCaCr()
        ├── Given: repayableAmount == 0
        │   └── When: the function _getRepayableAmount() gets called
        │       └── Then: it should return the return value of _getSmallerCaCr()
        └── Given: the repayableAmount != 0 || repayableAmount <= the return value _getSmallerCaCr()
            └── When: the function _getRepayableAmount() gets called
                └── Then: it should return the state variable repayableAmount
    */

    function testInternalGetRepayableAmount_worksGivenRepayableAmountBiggerReturnGetSmallerCaCr(
        uint repayableAmount_,
        uint capitalAvailable_,
        uint capitalRequirements_
    ) public {
        // Bound values
        capitalAvailable_ =
            bound(capitalAvailable_, 2, UINT256_MAX - MIN_RESERVE); // Protect agains overflow
        capitalRequirements_ = bound(capitalRequirements_, 2, capitalAvailable_);
        repayableAmount_ = bound(repayableAmount_, 2, capitalRequirements_);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), capitalAvailable_
        );
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);
        bondingCurveFundingManager.setRepayableAmount(repayableAmount_);
        // Set capital requirement < repayableAmount, which can only be done after
        // repayableAmount is set
        capitalRequirements_ = repayableAmount_ - 1;
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);

        // Get expected return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Expected return value
        uint expectedReturnValue = capitalAvailable_ > capitalRequirements_
            ? capitalRequirements_
            : capitalAvailable_;

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, expectedReturnValue);
    }

    function testInternalGetRepayableAmount_worksGivenRepayableAmountIsZero(
        uint capitalAvailable_,
        uint capitalRequirements_
    ) public {
        // Bound values
        capitalAvailable_ =
            bound(capitalAvailable_, 1, UINT256_MAX - MIN_RESERVE); // Protect agains overflow
        capitalRequirements_ = bound(capitalRequirements_, 1, capitalAvailable_);
        uint repayableAmount = 0;
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), capitalAvailable_
        );
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);
        bondingCurveFundingManager.setRepayableAmount(repayableAmount);

        // Get return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Get expected return value
        uint expectedReturnValue = capitalAvailable_ > capitalRequirements_
            ? capitalRequirements_
            : capitalAvailable_;

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, expectedReturnValue);
    }

    function testInternalGetRepayableAmount_worksGivenRepayableAmountIsReturned(
        uint repayableAmount_,
        uint capitalAvailable_,
        uint capitalRequirements_
    ) public {
        // Bound values
        capitalAvailable_ =
            bound(capitalAvailable_, 1, UINT256_MAX - MIN_RESERVE);
        capitalRequirements_ = bound(capitalRequirements_, 1, capitalAvailable_);
        repayableAmount_ = bound(repayableAmount_, 1, capitalRequirements_);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), capitalAvailable_
        );
        bondingCurveFundingManager.setCapitalRequired(capitalRequirements_);
        bondingCurveFundingManager.setRepayableAmount(repayableAmount_);

        // Get return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, repayableAmount_);
    }

    /*  Test _projectFeeCollected()
        └── Given: a tokenVault is set
            └── And: Tokens are available to be collected
                └── When: function _projectFeeCollected is called
                    └── Then: it should immediatley transfer the fee to the tokenVault
                        └── And: Emit ProjectCollateralFeeWithdrawn event
    */

    function testInternalProjectFeeCollected_worksGivenTokenVaultIsSetAndTokensAreAvailableToBeCollected(
        uint amount_
    ) public {
        amount_ = bound(amount_, 1, type(uint128).max);

        // Set tokenVault
        bondingCurveFundingManager.setTokenVault(tokenVault);

        //mint tokens to fundingManager
        _token.mint(address(bondingCurveFundingManager), amount_);

        vm.expectEmit(true, true, true, true);
        emit IIssuanceBase_v2.ProjectCollateralFeeWithdrawn(tokenVault, amount_);

        //call exposed function
        bondingCurveFundingManager.exposed_projectFeeCollected(amount_);

        assertEq(_token.balanceOf(tokenVault), amount_);
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)), MIN_RESERVE
        );
    }
    // -------------------------------------------------------------------------
    // Test Helper Functions

    function _mintIssuanceTokenToAddressHelper(address account_, uint amount_)
        internal
    {
        bondingCurveFundingManager.exposed_mint(account_, amount_);
    }

    function _mintCollateralTokenToAddressHelper(address account_, uint amount_)
        internal
    {
        vm.prank(owner_address);
        _token.mint(account_, amount_);
    }

    function _buyTokensForSetupHelper(address buyer_, uint amount_) internal {
        vm.startPrank(buyer_);
        {
            _token.approve(address(bondingCurveFundingManager), amount_);
            bondingCurveFundingManager.buy(amount_, 0); // Not testing actual return values here, so minAmount out can be 0
        }
        vm.stopPrank();
    }

    function _sellTokensForSetupHelper(address seller_, uint amount_)
        internal
    {
        vm.startPrank(seller_);
        {
            issuanceToken.approve(address(bondingCurveFundingManager), amount_);
            bondingCurveFundingManager.sell(amount_, 0); // Not testing actual return values here, so minAmount out can be 0
        }
        vm.stopPrank();
    }

    function _setProjectCollateralFeeCollectedHelper(uint amount_) internal {
        bondingCurveFundingManager.exposed_projectCollateralFeeCollected(
            amount_
        );
    }
}
