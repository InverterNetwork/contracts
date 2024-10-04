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
import {FM_BC_BondingSurface_Redeeming_Repayer_SeizableV1Mock} from
    "test/modules/fundingManager/bondingCurve/utils/mocks/FM_BC_BondingSurface_Redeeming_Repayer_SeizableV1Mock.sol";

/*     
    PLEASE NOTE: The following tests have been tested in other test contracts
    - buy() & buyOrderFor()
    - sell() & sellOrderFor()
    - getStaticPriceForSelling()
    - getStaticPriceForBuying()

    Also, since the following function just wrap the Bonding Surface contract, their content is assumed to be tested in the original formula tests, not here:

    - _issueTokensFormulaWrapper(uint _depositAmount)

    */
contract FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1Test is
    ModuleTest
{
    string private constant NAME = "Topos Token";
    string private constant SYMBOL = "TPG";
    uint8 internal constant DECIMALS = 18;
    uint internal constant MAX_SUPPLY = type(uint).max;
    uint private constant CAPITAL_REQUIREMENT = 1_000_000 * 1e18; // Taken from Topos repo test case

    uint private constant SELL_FEE = 100;
    bool private constant BUY_IS_OPEN = true;
    bool private constant SELL_IS_OPEN = true;
    bool private constant BUY_AND_SELL_IS_RESTRICTED = false;
    uint32 private constant BPS = 10_000;

    bytes32 private constant RISK_MANAGER_ROLE = "RISK_MANAGER";
    bytes32 private constant COVER_MANAGER_ROLE = "COVER_MANAGER";

    uint private constant MIN_RESERVE = 1 ether;
    uint64 private constant MAX_SEIZE = 100;
    uint64 private constant MAX_SELL_FEE = 100;
    uint private constant BASE_PRICE_MULTIPLIER = 0.000001 ether;
    uint64 private constant SEIZE_DELAY = 7 days;

    FM_BC_BondingSurface_Redeeming_Repayer_SeizableV1Mock
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
    address coverManager = address(0xa1bc);
    address riskManager = address(0xb0b);
    address tokenVault = makeAddr("tokenVault");
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
        bc_properties.seize = MAX_SEIZE;

        // Set pAMM properties
        bc_properties.buyIsOpen = BUY_IS_OPEN;
        bc_properties.sellIsOpen = SELL_IS_OPEN;
        bc_properties.sellFee = SELL_FEE;
        bc_properties.buyAndSellIsRestricted = BUY_AND_SELL_IS_RESTRICTED;

        address impl =
            address(new FM_BC_BondingSurface_Redeeming_Repayer_SeizableV1Mock());

        bondingCurveFundingManager =
        FM_BC_BondingSurface_Redeeming_Repayer_SeizableV1Mock(
            Clones.clone(impl)
        );

        _setUpOrchestrator(bondingCurveFundingManager);
        _authorizer.setIsAuthorized(address(this), true);

        // Set Minter
        issuanceToken.setMinter(address(bondingCurveFundingManager), true); //@todo This wasnt set??

        // Init Module
        bondingCurveFundingManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(
                address(issuanceToken),
                _token, // fetching from ModuleTest.sol (specifically after the _setUpOrchestrator function call)
                tokenVault,
                liquidityVaultController,
                bc_properties
            )
        );
        // Mint minimal reserve necessary to operate the BC
        _token.mint(
            address(bondingCurveFundingManager),
            bondingCurveFundingManager.MIN_RESERVE()
        );

        address[] memory targets = new address[](2);
        targets[0] = buyer;
        targets[1] = seller;

        bondingCurveFundingManager.grantModuleRoleBatched(
            CURVE_INTERACTION_ROLE, targets
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
            0,
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
        // Liquidity Vault Controller
        assertEq(
            address(bondingCurveFundingManager.liquidityVaultController()),
            liquidityVaultController,
            "Initial liquidity vault controller has not been set correctly"
        );
        // Reserve Pool
        assertEq(
            address(bondingCurveFundingManager.tokenVault()),
            address(0),
            "Initial reserve pool has not been set correctly"
        );
    }

    function testReinitFails() public override {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        bondingCurveFundingManager.init(_orchestrator, _METADATA, abi.encode());
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /*  Test buy() & buyFor() functions
        Please Note: The functions have been extensively tested in the BondingCurveBase_v1.t contract. These
        tests only check for the placement of the isBuyAndSellRestricted() modifier
        ├── Given the modifier isBuyAndSellRestricted() is in place
        │   └── And the modifier condition isn't met
        │       ├── When the function buy() is called
        │       └── Then it should revert
        └── Given the modifier isBuyAndSellRestricted() is in place
            └── And the modifier condition isn't met
                └── When the function buyFor() is called
                    └── Then it should revert
    */

    function testBuy_modifierInPlace() public {
        // Set buyAndSellIsRestricted to true
        bondingCurveFundingManager.restrictBuyAndSell();
        assertEq(bondingCurveFundingManager.buyAndSellIsRestricted(), true);

        // Check for modifier
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                bondingCurveFundingManager.CURVE_INTERACTION_ROLE(),
                nonAuthorizedBuyer
            )
        );
        vm.prank(nonAuthorizedBuyer);
        bondingCurveFundingManager.buy(1, 1);
    }

    function testBuyFor_modifierInPlace() public {
        // Set buyAndSellIsRestricted to true
        bondingCurveFundingManager.restrictBuyAndSell();
        assertEq(bondingCurveFundingManager.buyAndSellIsRestricted(), true);

        // Check for modifier
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                bondingCurveFundingManager.CURVE_INTERACTION_ROLE(),
                nonAuthorizedBuyer
            )
        );
        vm.prank(nonAuthorizedBuyer);
        bondingCurveFundingManager.buyFor(seller, 1, 1);
    }

    /*  Test unrestrictBuyAndSell() function
        ├── Given the onlyModuleRole(COVER_MANAGER_ROLE) modifier is in place
        │   └── And the modifier condition isn't met
        │       └── When the function unrestrictBuyAndSell() is called
        │           └── Then it should revert
        └── Given the msg.sender is the COVER_MANAGER_ROLE
            └── When the function unrestrictBuyAndSell() is called
                └── Then it should set the buyAndSellIsRestricted to false
                    └── And it should emit an event
    */

    function testBuyAndSellIsUnrestricted_modifierInPlace() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bondingCurveFundingManager),
                    bondingCurveFundingManager.COVER_MANAGER_ROLE()
                ),
                nonAuthorizedBuyer
            )
        );
        vm.prank(nonAuthorizedBuyer);
        bondingCurveFundingManager.unrestrictBuyAndSell();
    }

    function testBuyAndSellIsUnrestricted_worksGivenCallerHasCoverManagerRole()
        public
    {
        // Setup
        bondingCurveFundingManager.restrictBuyAndSell();
        assertEq(bondingCurveFundingManager.buyAndSellIsRestricted(), true);

        // Test condition
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
            .BuyAndSellIsUnrestricted();
        bondingCurveFundingManager.unrestrictBuyAndSell();
    }

    /*  Test restrictBuyAndSell() function
        ├── Given the onlyModuleRole(COVER_MANAGER_ROLE) modifier is in place
        │   └── And the modifier condition isn't met
        │       └── When the function restrictBuyAndSell() is called
        │           └── Then it should revert
        └── Given the msg.sender is the COVER_MANAGER_ROLE
            └── When the function restrictBuyAndSell() is called
                └── Then it should set the buyAndSellIsRestricted to true
                    └── And it should emit an event
    */

    function testRestrictBuyAndSell_modifierInPlace() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.generateRoleId(
                    address(bondingCurveFundingManager),
                    bondingCurveFundingManager.COVER_MANAGER_ROLE()
                ),
                nonAuthorizedBuyer
            )
        );
        vm.prank(nonAuthorizedBuyer);
        bondingCurveFundingManager.restrictBuyAndSell();
    }

    function testUnrestrictBuyAndSell_worksGivenCallerHasCoverManagerRole()
        public
    {
        // Setup
        bondingCurveFundingManager.unrestrictBuyAndSell();
        assertEq(bondingCurveFundingManager.buyAndSellIsRestricted(), false);

        // Test condition
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
            .BuyAndSellIsRestricted();
        bondingCurveFundingManager.restrictBuyAndSell();
    }

    /*  Test internal _isBuyAndSellRestrictedModifier() function
        └── Given buy and selling is restricted
            └── And the msg.sender does not have the CURVE_INTERACTION_ROLE
                └── When the function _isBuyAndSellRestrictedModifier() is called
                    └── Then it should revert
    */

    function testInternalIsBuyAndSellRestrictedModifier_revertGivenCallerHasNotCoverManagerRole(
    ) public {
        // Setup
        bondingCurveFundingManager.restrictBuyAndSell();
        assertEq(bondingCurveFundingManager.buyAndSellIsRestricted(), true);

        // Test condition
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                bondingCurveFundingManager.CURVE_INTERACTION_ROLE(),
                nonAuthorizedBuyer
            )
        );
        vm.prank(nonAuthorizedBuyer);
        bondingCurveFundingManager.exposed_isBuyAndSellRestrictedModifier();
    }

    /*  Test burnIssuanceToken()
        ├── Given: _amount > msg.sender balance of issuance token
        │   └── When: the function burnIssuanceToken() gets called
        │       └── Then: it should revert
        └── Given: _amount <= msg.sender balance of issuance token
            └── When: the function burnIssuanceToken() gets called
                └── Then: it should burn _amount from msg.sender's balance
    */

    function testBurnIssuanceToken_revertGivenAmountBiggerThanMsgSenderBalance(
        uint _amount
    ) public {
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // balance of the burner
        uint burnerTokenBalance = _amount - 1;
        // mint issuance token to user for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when balance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceToken(_amount);
        }
    }

    function testBurnIssuanceToken_worksGivenAmountLowerThanMsgSenderBalance(
        uint _amount
    ) public {
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // balance of the burner
        uint burnerTokenBalance = _amount + 1;
        // mint issuance token to user for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Assert right amount has been minted
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceToken(_amount);

        // Assert right amount has been burned
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance - _amount);
    }

    /*  Test burnIssuanceTokenFor()
        ├── Given: _owner != msg.sender
        │   ├── And: the allowance < _amount
        │   │   └── When: the function burnIssuanceTokenFor() gets called
        │   │       └── Then: it should revert
        │   └── And: msg.sender allowance > _amount
        │       ├── And: _owner balance < _amount
        │       │   └── When: the function burnIssuanceTokenFor() gets called
        │       │       └── Then: it should revert
        │       └── And: _owner balance > _amount
        │           └── When: the function burnIssuanceTokenFor() gets called
        │                └── Then: it should burn _amount tokens from the _owner
        └── Given: _owner == msg.sender
            ├── And: _amount > _owner balance of issuance token
            │   └── When: the function burnIssuanceToken() gets called
            │       └── Then: it should revert
            └── And: _amount <= _owner balance of issuance token
                └── When: the function burnIssuanceToken() gets called
                    └── Then: it should burn _amount from _owner's balance
    */

    function testBurnIssuanceTokenFor_revertGivenAmountHigherThanOwnerAllowance(
        uint _amount
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = _amount;
        // mint issuance token to tokenOwner for burning
        _mintIssuanceTokenToAddressHelper(tokenOwner, ownerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(tokenOwner), ownerTokenBalance);
        // Approve less than amount to burner address
        vm.prank(tokenOwner);
        issuanceToken.approve(burner, _amount - 1);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when allowance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, _amount);
        }
    }

    function testBurnIssuanceTokenFor_revertGivenAmountBiggerThanOwnerBalance(
        uint _amount
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = _amount - 1;
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
            bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, _amount);
        }
    }

    function testBurnIssuanceTokenFor_worksGivenOwnerIsNotMsgSender(
        uint _amount
    ) public {
        address tokenOwner = makeAddr("tokenOwner");
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // Balance of tokenOwner
        uint ownerTokenBalance = _amount + 1;
        // mint issuance token to tokenOwner for burning
        _mintIssuanceTokenToAddressHelper(tokenOwner, ownerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(tokenOwner), ownerTokenBalance);
        // Approve tokenOwner balance to burner
        vm.prank(tokenOwner);
        issuanceToken.approve(burner, ownerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceTokenFor(tokenOwner, _amount);

        // Assert right amount has been burned
        assertEq(
            issuanceToken.balanceOf(tokenOwner), ownerTokenBalance - _amount
        );
    }

    function testBurnIssuanceTokenFor_revertGivenAmountBiggerThanMsgSenderBalance(
        uint _amount
    ) public {
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // balance of burner
        uint burnerTokenBalance = _amount - 1;
        // mint issuance token to burner for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        {
            // Revert when balance lower than amount
            vm.expectRevert();
            bondingCurveFundingManager.burnIssuanceTokenFor(burner, _amount);
        }
    }

    function testBurnIssuanceTokenFor_worksGivenMsgSenderIsNotOwner(
        uint _amount
    ) public {
        // bound value to max uint - 1
        _amount = bound(_amount, 1, UINT256_MAX - 1);
        // Balance of burner
        uint burnerTokenBalance = _amount + 1;
        // mint issuance token to burner for burning
        _mintIssuanceTokenToAddressHelper(burner, burnerTokenBalance);
        // Validate minting success
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance);

        // Execute tx
        vm.startPrank(burner);
        bondingCurveFundingManager.burnIssuanceTokenFor(burner, _amount);

        // Assert right amount has been burned
        assertEq(issuanceToken.balanceOf(burner), burnerTokenBalance - _amount);
    }

    /*  Test calculatebasePriceToCapitalRatio()
        └── When: the function calculatebasePriceToCapitalRatio() gets called
            └── Then: it should return the return value of _calculateBasePriceToCapitalRatio()
    */

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
    // Implementation Specific Public Functions

    /*  Test seizable()
        └── When: the function seizable() gets called
            └── Then: it should return the correct seizable amount
    */
    function testSeizable_works(uint _tokenBalance, uint64 _seize) public {
        _tokenBalance =
            bound(_tokenBalance, 1, (UINT256_MAX - MIN_RESERVE) / 1000); // to protect agains overflow if max balance * max seize
        _seize =
            uint64(bound(_seize, 1, bondingCurveFundingManager.MAX_SEIZE()));
        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // mint collateral to funding manager
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _tokenBalance
        );
        // set seize in contract
        bondingCurveFundingManager.adjustSeize(_seize);

        // calculate return value
        uint expectedReturnValue =
            ((_tokenBalance + tokenBalanceFundingMangerBaseline) * _seize) / BPS;

        // Execute tx
        uint returnValue = bondingCurveFundingManager.seizable();

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

    //--------------------------------------------------------------------------
    // onlyLiquidityVaultController Functions

    /*  Test transferRepayment()
        ├── Given the caller is not the liquidityVaultController
        │   └── When the function transferRepayment() is called
        │       └── Then it should revert
        ├── Given modifier validReceiver(_to) is in place: Please Note: Modifier test can be found in BondingCurveBase_v1.t
        │   └── When the function transferRepayment() is called
        │       └── Then it should revert if receiver is invalid
        └── Given: the caller is the liquidityVaultController
            └── And: the _to address is valid
                ├── And: the _amount > the repayable amount available
                │   └── When: the function transferRepayment() gets called
                │       └── Then: it should revert
                └── And: _amount <= repayable amount available
                    └── When: the function transferRepayment() gets called
                        └── Then: it should transfer _amount to the _to address
                            └── And: it should emit an event
    */

    function testTransferPayment_revertGivenCallerIsNotLiquidityVaultController(
        address _to,
        uint _amount
    ) public {
        // Valid _to address
        vm.assume(
            _to != liquidityVaultController
                && _to != address(bondingCurveFundingManager) && _to != address(0)
        );
        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                        .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidLiquidityVaultController
                        .selector,
                    seller
                )
            );
            bondingCurveFundingManager.transferRepayment(_to, _amount);
        }
    }

    function testTransferPayment_modifierInPlace(uint _amount) public {
        address to = address(0);
        _amount = bound(_amount, 2, UINT256_MAX - 1);

        // Execute Tx
        vm.startPrank(liquidityVaultController);
        {
            vm.expectRevert(
                IBondingCurveBase_v1
                    .Module__BondingCurveBase__InvalidRecipient
                    .selector
            );
            bondingCurveFundingManager.transferRepayment(to, _amount);
        }
    }

    function testTransferPayment_revertGivenAmounBiggerThanRepayableAmount(
        address _to,
        uint _amount
    ) public {
        // Valid _to address
        vm.assume(
            _to != liquidityVaultController
                && _to != address(bondingCurveFundingManager) && _to != address(0)
        );
        _amount = bound(_amount, 2, UINT256_MAX - MIN_RESERVE); // Protect agains overflow

        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // set capital available in funding manager
        uint tokenBalanceFundingManager = _amount;
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), tokenBalanceFundingManager
        );
        // Set capital requirement
        bondingCurveFundingManager.setCapitalRequired(_amount);
        // Set repayable amount < _amount
        bondingCurveFundingManager.setRepayableAmount(_amount - 1);

        // Assert that right amount tokens have been minted to funding manager
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            tokenBalanceFundingMangerBaseline + tokenBalanceFundingManager
        );

        // Execute Tx
        vm.startPrank(liquidityVaultController);
        {
            // Revert when _amount > repayableAmount
            vm.expectRevert(
                IRepayer_v1
                    .Repayer__InsufficientCollateralForRepayerTransfer
                    .selector
            );
            bondingCurveFundingManager.transferRepayment(_to, _amount);
        }
    }

    function testTransferPayment_worksGivenCallerIsLvcAndAmountIsValid(
        address _to,
        uint _amount
    ) public {
        // Valid _to address
        vm.assume(
            _to != liquidityVaultController
                && _to != address(bondingCurveFundingManager) && _to != address(0)
        );
        _amount = bound(_amount, 1, UINT256_MAX - MIN_RESERVE); // Protect agains overflow

        // Setup
        // Get balance before test
        uint tokenBalanceFundingMangerBaseline =
            _token.balanceOf(address(bondingCurveFundingManager));
        // set and mint the amount needed for this test.
        uint mintAmountForFundingManager = _amount;
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), mintAmountForFundingManager
        );
        // Set capital requirement
        bondingCurveFundingManager.setCapitalRequired(_amount);
        // Set repayable amount
        bondingCurveFundingManager.setRepayableAmount(_amount);

        // Assert that right amount tokens have been minted to funding manager, i.e. mintAmountForFundingManager + MIN_RESERVE
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            mintAmountForFundingManager + tokenBalanceFundingMangerBaseline
        );
        // Assert that receiver address does not have tokens
        assertEq(_token.balanceOf(_to), 0);

        // Execute Tx
        vm.prank(liquidityVaultController);
        vm.expectEmit(address(bondingCurveFundingManager));
        emit IRepayer_v1.RepaymentTransfer(_to, _amount);
        bondingCurveFundingManager.transferRepayment(_to, _amount);

        // Assert that _amount tokens have been withdrawn from funding manager
        assertEq(
            _token.balanceOf(address(bondingCurveFundingManager)),
            tokenBalanceFundingMangerBaseline + mintAmountForFundingManager
                - _amount
        );
        // Assert that receiver has _amount token
        assertEq(_token.balanceOf(_to), _amount);
    }

    //--------------------------------------------------------------------------
    // OnlyCoverManager Functions

    /*  Test seize()
        ├── Given: the caller has not the COVER_MANAGER_ROLE
        │   └── When: the function seize() gets called
        │       └── Then: it should revert
        └── Given: the caller has the COVER_MANAGER_ROLE
            ├── And: the parameter _amount > the seizable amount
            │   └── When: the function seize() gets called
            │       └── Then: it should revert
            ├── And: the lastSeizeTimestamp + SEIZE_DELAY > block.timestamp
            │   └── When: the function seize() gets called
            │       └── Then: it should revert
            ├── And: the capital available - _amount < MIN_RESERVE
            │   └── When: the function seize() gets called
            │       └── Then: it should transfer the value of capitalAvailable - MIN_RESERVE tokens to the msg.sender
            │           ├── And: it should set the current timeStamp to lastSeizeTimestamp
            │           └── And: it should emit an event
            └── And: the capital available - _amount > MIN_RESERVE
                └── And: the lastSeizeTimestamp + SEIZE_DELAY < block.timestamp
                    └── When: the function seize() gets called
                        └── Then: it should transfer the value of _amount tokens to the msg.sender
                            ├── And: it should set the current timeStamp to lastSeizeTimestamp
                            └── And: it should emit an event
    */
    function testSeize_revertGivenCallerHasNotCoverManagerRole() public {
        uint _amount = 1;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.COVER_MANAGER_ROLE()
                    ),
                    seller
                )
            );
            bondingCurveFundingManager.seize(_amount);
        }
    }

    function testSeize_revertGivenAmountBiggerThanSeizableAmount(uint _amount)
        public
    {
        uint currentSeizable = bondingCurveFundingManager.seizable();
        vm.assume(_amount > currentSeizable);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                    .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeizeAmount
                    .selector,
                currentSeizable
            )
        );
        bondingCurveFundingManager.seize(_amount);
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
            bondingCurveFundingManager.lastSeizeTimestamp();

        // Assert expected fail. block.timestamp == 1 without setting it in vm.warp
        assertGt((seizeTimestampBefore + SEIZE_DELAY), block.timestamp);

        // Execute Tx expecting it to revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                    .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__SeizeTimeout
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
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
            .CollateralSeized(expectedReturnValue);
        bondingCurveFundingManager.seize(amount);

        // Assert that no tokens have been sent
        assertEq(balanceBeforeBuy, balanceBeforeBuy);
    }

    function testSeize_worksGivenCapitalAmountIsReturnd(uint _amount) public {
        // Setup
        // Set block.timestamp to valid time
        vm.warp(SEIZE_DELAY + 1);
        // Bound seizable value
        _amount = bound(_amount, 1, type(uint128).max);
        // Mint enough surplus so seizing can happen
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _amount * 10_000
        );
        //Get balance before seize
        uint balanceBeforeBuy = _token.balanceOf(address(this));

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
            .CollateralSeized(_amount);
        bondingCurveFundingManager.seize(_amount);

        // Get balance after buying
        uint balanceAfterBuy = _token.balanceOf(address(this));
        // Assert that no tokens have been sent
        assertEq(balanceAfterBuy, balanceBeforeBuy + _amount);
    }

    /*    Test adjust
        ├── Given: the caller has not the COVER_MANAGER_ROLE
        │   └── When: the function adjustSeize() gets called
        │       └── Then: it should revert
        └── Given: the caller has the COVER_MANAGER_ROLE
                └── When: the function adjustSeize() gets called
                    └── Then: it should call the internal function and set the state
    */

    function testAdjustSeize_revertGivenCallerHasNotCoverManagerRole() public {
        uint64 _seize = 10_000;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.COVER_MANAGER_ROLE()
                    ),
                    seller
                )
            );
            bondingCurveFundingManager.adjustSeize(_seize);
        }
    }

    function testAdjustSeize_worksGivenCallerHasCoverManagerRole(uint64 _seize)
        public
    {
        vm.assume(_seize != bondingCurveFundingManager.currentSeize());
        _seize = uint64(bound(_seize, 1, MAX_SEIZE));

        // Execute Tx
        bondingCurveFundingManager.adjustSeize(_seize);

        assertEq(bondingCurveFundingManager.currentSeize(), _seize);
    }

    /*  Test setSellFee()
        ├── Given: the caller has not the COVER_MANAGER_ROLE
        │   └── When: the function setSellFee() gets called
        │       └── Then: it should revert
        └── Given: the caller has the COVER_MANAGER_ROLE
            ├── And: _fee > MAX_SELL_FEE
            │   └── When: the function setSellFee() getrs called
            │       └── Then: it should revert
            └── And: _fee <= MAX_SELL_FEE
                └── When: the function setSellFee() gets called
                    └── Then: it should set the state of sellFee to _fee
    */

    function testSetSellFee_revertGivenCallerHasNotCoverManagerRole() public {
        uint sellFee = 100;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.COVER_MANAGER_ROLE()
                    ),
                    seller
                )
            );
            bondingCurveFundingManager.setSellFee(sellFee);
        }
    }

    function testSetSellFee_revertGivenSeizeBiggerThanMaxSeize(uint _fee)
        public
    {
        vm.assume(_fee > MAX_SELL_FEE);

        // Execute Tx
        vm.expectRevert(
            abi.encodeWithSelector(
                IBondingCurveBase_v1
                    .Module__BondingCurveBase__InvalidFeePercentage
                    .selector
            )
        );
        bondingCurveFundingManager.setSellFee(_fee);
    }

    function testAdjustSeize_worksGivenCallerHasRoleAndSeizeIsValid(uint _fee)
        public
    {
        vm.assume(_fee != bondingCurveFundingManager.sellFee());
        _fee = bound(_fee, 1, MAX_SELL_FEE);

        // Execute Tx
        bondingCurveFundingManager.setSellFee(_fee);

        assertEq(bondingCurveFundingManager.sellFee(), _fee);
    }

    /*  Test setBuyFee()
        └──  When the function setBuyFee() gets called
            └── Then it should revert
    */
    function testSetBuyFee_revert() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                    .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidFunctionality
                    .selector
            )
        );
        bondingCurveFundingManager.setBuyFee(1);
    }

    /*  Test setRepayableAmount()
        ├── Given: the caller has not the COVER_MANAGER_ROLE
        │   └── When: the function setRepayableAmount() gets called
        │       └── Then: it should revert
        └── Given: the caller has the COVER_MANAGER_ROLE
            ├── And: _amount > either capitalAvailable or capitalRequirements
            │   └── When: the function setRepayableAmount() gets called
            │       └── Then: it should revert
            └── And: _amount <= either capitalAvailable or capitalRequirements
                └── When: the function setRepayableAmount() gets called
                    └── Then: it should set the state of repayableAmount to _amount
                        └── And: it should emit an event
    */
    function testSetRepayableAmount_revertGivenCallerHasNotCoverManagerRole()
        public
    {
        uint amount = 1000;

        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.COVER_MANAGER_ROLE()
                    ),
                    seller
                )
            );
            bondingCurveFundingManager.setRepayableAmount(amount);
        }
    }

    /*  Test setliquidityVaultControllerContract()
        ├── Given: the caller has not the COVER_MANAGER_ROLE
        │   └── When: the function setliquidityVaultControllerContract() gets called
        │       └── Then: it should revert
        └── Given: the caller has the COVER_MANAGER_ROLE
            ├── And: _lp == address(0)
            │   └── When: the function setliquidityVaultController() gets called
            │       └── Then: it should revert
            └── And: _lp != address(0)
                └── When: the function setliquidityVaultController() gets called
                    └── Then: it should set the state liquidityVaultController to _lp
                        └── And: it should emit an event
    */

    function testSetliquidityVaultControllerContract_revertGivenCallerHasNotCoverManagerRole(
        ILiquidityVaultController _lvc
    ) public {
        // Execute Tx
        vm.startPrank(seller);
        {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IModule_v1.Module__CallerNotAuthorized.selector,
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.COVER_MANAGER_ROLE()
                    ),
                    seller
                )
            );
            bondingCurveFundingManager.setLiquidityVaultControllerContract(_lvc);
        }
    }

    function testSetliquidityVaultControllerContract_revertGivenAddressIsZero()
        public
    {
        ILiquidityVaultController _lvc = ILiquidityVaultController(address(0));

        // Expect Revert
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAddress
                .selector
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(_lvc);
    }

    function testSetliquidityVaultControllerContract_revertGivenAddressIsEqualToFM(
    ) public {
        ILiquidityVaultController _lvc =
            ILiquidityVaultController(address(bondingCurveFundingManager));

        // Expect Revert
        vm.expectRevert(
            IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidInputAddress
                .selector
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(_lvc);
    }

    function testSetliquidityVaultControllerContract_worksGivenCallerHasRoleAndAddressValid(
        ILiquidityVaultController _lvc
    ) public {
        vm.assume(
            _lvc != ILiquidityVaultController(address(0))
                && _lvc
                    != ILiquidityVaultController(address(bondingCurveFundingManager))
        );

        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
            .LiquidityVaultControllerChanged(
            address(_lvc), liquidityVaultController
        );
        bondingCurveFundingManager.setLiquidityVaultControllerContract(_lvc);
    }

    //--------------------------------------------------------------------------
    // OnlyCoverManager Functions

    /*  Test setCapitalRequired()
        ├── Given: the caller has not the RISK_MANAGER_ROLE
        │   └── When: the function setCapitalRequired() is called
        │       └── Then: it should revert
        └── Given: the caller has the role of RISK_MANAGER_ROLE
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
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.RISK_MANAGER_ROLE()
                    ),
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
        ├── Given: the caller has not the RISK_MANAGER_ROLE
        │   └── When: the function setBaseMultiplier() is called
        │       └── Then: it should revert
        └── Given: the caller has the RISK_MANAGER_ROLE
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
                    _authorizer.generateRoleId(
                        address(bondingCurveFundingManager),
                        bondingCurveFundingManager.RISK_MANAGER_ROLE()
                    ),
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
    // OnlyOrchestratorAdmin Functions

    function testSetTokenVault_ModifierInPosition() public {
        // onlyOrchestratorAdmin
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                _authorizer.getAdminRole(),
                address(0)
            )
        );
        vm.prank(address(0));
        bondingCurveFundingManager.setTokenVault(address(0));
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

    function testInternalSetSeize_revertGivenSeizeBiggerThanMaxSeize(
        uint64 _seize
    ) public {
        vm.assume(_seize > MAX_SEIZE);

        // Execute Tx
        vm.expectRevert(
            abi.encodeWithSelector(
                IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1
                    .FM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1__InvalidSeize
                    .selector,
                _seize
            )
        );
        bondingCurveFundingManager.exposed_setSeize(_seize);
    }

    function testInternalSetSeize_worksGivenSeizeIsValid(uint64 _seize)
        public
    {
        vm.assume(_seize != bondingCurveFundingManager.currentSeize());
        _seize = uint64(bound(_seize, 1, MAX_SEIZE));
        uint64 currentSeize = bondingCurveFundingManager.currentSeize();

        // Execute Tx
        vm.expectEmit(
            true, true, true, true, address(bondingCurveFundingManager)
        );
        emit IFM_BC_BondingSurface_Redeeming_Repayer_Seizable_v1.SeizeChanged(
            currentSeize, _seize
        );
        bondingCurveFundingManager.adjustSeize(_seize);

        // assertEq(bondingCurveFundingManager.currentSeize(), _seize);
    }

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

    function testSetTokenVault_revertGivenAddressIsZero() public {
        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        bondingCurveFundingManager.exposed_setTokenVault(address(0));
    }

    function testSetTokenVault_worksGivenAddressIsNotZero(address newVault)
        public
    {
        vm.assume(newVault != address(0));
        // Execute Tx
        bondingCurveFundingManager.exposed_setTokenVault(newVault);
        // Assert that the token vault address has been set to the given address
        assertEq(bondingCurveFundingManager.tokenVault(), newVault);
    }

    /*    Test _calculateBasePriceToCapitalRatio()
        └── Given: the function _calculateBasePriceToCapitalRatio() gets called
            ├── When: the resulting _basePriceToCapitalRatio > 1e36
            │   └── Then is should revert
            └── When: the _basePriceToCapitalRatio < 1e36
                └── Then: it should return _basePriceToCapitalRatio
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

    /*  Test _getSmallerCaCr()
        ├── Given: the capital available is > capitalRequirement
        │   └── When: the function _getSmallerCaCr() gets called
        │       └── Then: it should return the capitalRequirement
        └── Given: the capital available is < capitalRequirement
            └── When: the function _getSmallerCaCr() gets called
                └── Then: it should return the capitalAvailable
    */

    function testGetSmallerCaCr_worksGivenCapitalAvailableIsBiggerThanCapitalRequirements(
        uint _capitalAvailable,
        uint _capitalRequirements
    ) public {
        _capitalAvailable =
            bound(_capitalAvailable, 1, UINT256_MAX - MIN_RESERVE); // protect agains overflow
        _capitalRequirements = bound(_capitalRequirements, 1, _capitalAvailable); // make capital requirements < capital available
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _capitalAvailable
        );
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);

        uint returnValue = bondingCurveFundingManager.exposed_getSmallerCaCr();

        // Assert that the smaller value got returned
        assertEq(returnValue, _capitalRequirements);
    }

    function testGetSmallerCaCr_worksGivenCapitalRequirementsIsBiggerThanCapitalAvailable(
        uint _capitalAvailable,
        uint _capitalRequirements
    ) public {
        // Set capital requirement above MIN_RESERVE, which is the capital already available
        _capitalRequirements = bound(
            _capitalRequirements, MIN_RESERVE + 1, UINT256_MAX - MIN_RESERVE
        ); // make capital requirements > capital available
        // set capital available, i.e the to be minted amount for the the test
        _capitalAvailable =
            bound(_capitalAvailable, MIN_RESERVE, _capitalRequirements);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager),
            (
                _capitalAvailable
                    - _token.balanceOf(address(bondingCurveFundingManager))
            )
        );
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);

        uint returnValue = bondingCurveFundingManager.exposed_getSmallerCaCr();

        // Assert that the smaller value got returned
        assertEq(returnValue, _capitalAvailable);
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
        uint _repayableAmount,
        uint _capitalAvailable,
        uint _capitalRequirements
    ) public {
        // Bound values
        _capitalAvailable =
            bound(_capitalAvailable, 2, UINT256_MAX - MIN_RESERVE); // Protect agains overflow
        _capitalRequirements = bound(_capitalRequirements, 2, _capitalAvailable);
        _repayableAmount = bound(_repayableAmount, 2, _capitalRequirements);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _capitalAvailable
        );
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);
        bondingCurveFundingManager.setRepayableAmount(_repayableAmount);
        // Set capital requirement < repayableAmount, which can only be done after
        // repayableAmount is set
        _capitalRequirements = _repayableAmount - 1;
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);

        // Get expected return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Expected return value
        uint expectedReturnValue = _capitalAvailable > _capitalRequirements
            ? _capitalRequirements
            : _capitalAvailable;

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, expectedReturnValue);
    }

    function testInternalGetRepayableAmount_worksGivenRepayableAmountIsZero(
        uint _capitalAvailable,
        uint _capitalRequirements
    ) public {
        // Bound values
        _capitalAvailable =
            bound(_capitalAvailable, 1, UINT256_MAX - MIN_RESERVE); // Protect agains overflow
        _capitalRequirements = bound(_capitalRequirements, 1, _capitalAvailable);
        uint repayableAmount = 0;
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _capitalAvailable
        );
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);
        bondingCurveFundingManager.setRepayableAmount(repayableAmount);

        // Get return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Get expected return value
        uint expectedReturnValue = _capitalAvailable > _capitalRequirements
            ? _capitalRequirements
            : _capitalAvailable;

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, expectedReturnValue);
    }

    function testInternalGetRepayableAmount_worksGivenRepayableAmountIsReturned(
        uint _repayableAmount,
        uint _capitalAvailable,
        uint _capitalRequirements
    ) public {
        // Bound values
        _capitalAvailable =
            bound(_capitalAvailable, 1, UINT256_MAX - MIN_RESERVE);
        _capitalRequirements = bound(_capitalRequirements, 1, _capitalAvailable);
        _repayableAmount = bound(_repayableAmount, 1, _capitalRequirements);
        // Setup
        _mintCollateralTokenToAddressHelper(
            address(bondingCurveFundingManager), _capitalAvailable
        );
        bondingCurveFundingManager.setCapitalRequired(_capitalRequirements);
        bondingCurveFundingManager.setRepayableAmount(_repayableAmount);

        // Get return value
        uint returnValueInternalFunction =
            bondingCurveFundingManager.exposed_getRepayableAmount();

        // Assert return value == as repayableAmount
        assertEq(returnValueInternalFunction, _repayableAmount);
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
