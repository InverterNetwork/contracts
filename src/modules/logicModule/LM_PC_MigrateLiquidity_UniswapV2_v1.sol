// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ILM_PC_MigrateLiquidity_UniswapV2_v1} from
    "@lm/interfaces/ILM_PC_MigrateLiquidity_UniswapV2_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/abstracts/ERC20PaymentClientBase_v1.sol";

// Internal Dependencies
import {
    ERC20PaymentClientBase_v1,
    Module_v1
} from "@lm/abstracts/ERC20PaymentClientBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";

// External Interfaces
import {IUniswapV2Router02} from "@ex/interfaces/uniswap/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@ex/interfaces/uniswap/IUniswapV2Factory.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Issuance_v1} from "src/external/token/IERC20Issuance_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

interface BondingCurve is IBondingCurveBase_v1 {
    /// @notice Transfer a specified amount of Tokens to a designated receiver address.
    /// @dev    This function MUST be restricted to be called only by the {Orchestrator_v1}.
    /// @dev    This function CAN update internal user balances to account for the new token balance.
    /// @param  to The address that will receive the tokens.
    /// @param  amount The amount of tokens to be transfered.
    function transferOrchestratorToken(address to, uint amount) external;
}

contract LM_PC_MigrateLiquidity_UniswapV2_v1 is
    ILM_PC_MigrateLiquidity_UniswapV2_v1,
    ERC20PaymentClientBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClientBase_v1)
        returns (bool)
    {
        return interfaceId
            == type(ILM_PC_MigrateLiquidity_UniswapV2_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier notExecuted() {
        if (_executed) {
            revert Module__LM_PC_MigrateLiquidity__AlreadyExecuted();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Address of the funding manager
    address private _fundingManagerAddress;

    /// @dev Address of the issuance token
    address private _issuanceTokenAddress;

    /// @dev Address of the collateral token
    address private _collateralTokenAddress;

    /// @dev LP Recipient Address
    address private _lpRecipientAddress;

    /// @dev State of the current migration
    LiquidityMigrationConfig private _currentMigration;

    /// @dev Bonding Curve instance
    BondingCurve private _bondingCurve;

    /// @dev Executed flag
    bool private _executed;

    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        _fundingManagerAddress = address(orchestrator().fundingManager());
        _bondingCurve = BondingCurve(_fundingManagerAddress);
        _collateralTokenAddress =
            address(orchestrator().fundingManager().token());
        _issuanceTokenAddress = address(_bondingCurve.getIssuanceToken());
        (_currentMigration) = abi.decode(configData, (LiquidityMigrationConfig));
        _lpRecipientAddress = _currentMigration.lpTokenRecipientAddress;
    }

    //--------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function getExecuted() external view returns (bool) {
        return _executed;
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function getMigrationConfig()
        external
        view
        returns (LiquidityMigrationConfig memory)
    {
        return _currentMigration;
    }

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function isMigrationReady() public view returns (bool) {
        // Check if migration has been executed
        if (_executed) {
            return false;
        }

        uint collateralBalance =
            IERC20(_collateralTokenAddress).balanceOf(_fundingManagerAddress);

        if (collateralBalance < _currentMigration.collateralMigrateThreshold) {
            return false;
        }

        return true;
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc ILM_PC_MigrateLiquidity_UniswapV2_v1
    function executeMigration()
        external
        notExecuted
        returns (LiquidityMigrationResult memory)
    {
        if (!isMigrationReady()) {
            revert Module__LM_PC_MigrateLiquidity__ThresholdNotReached();
        }

        // Get the UniswapV2 Router
        IUniswapV2Router02 router =
            IUniswapV2Router02(_currentMigration.dexRouterAddress);

        // Get token addresses from the payment processor
        address tokenA = _collateralTokenAddress;
        address tokenB = _issuanceTokenAddress;

        // Transfer collateral tokens to this contract
        _bondingCurve.transferOrchestratorToken(
            address(this), _currentMigration.collateralMigrationAmount
        );

        // Calculate issuance migration amount
        uint issuanceMigrationAmount = _bondingCurve.calculatePurchaseReturn(
            _currentMigration.collateralMigrationAmount
        );

        // Mint issuance tokens to be used as liquidity
        IERC20Issuance_v1(_issuanceTokenAddress).mint(
            address(this), issuanceMigrationAmount
        );

        // Approve router to spend tokens
        IERC20(tokenA).approve(
            _currentMigration.dexRouterAddress,
            _currentMigration.collateralMigrationAmount
        );
        IERC20(tokenB).approve(
            _currentMigration.dexRouterAddress, issuanceMigrationAmount
        );

        address lpTokenAddress =
            IUniswapV2Factory(router.factory()).createPair(tokenA, tokenB);

        // Add liquidity
        (uint amountA, uint amountB, uint lpTokenAmount) = router.addLiquidity(
            tokenA,
            tokenB,
            _currentMigration.collateralMigrationAmount,
            issuanceMigrationAmount,
            _currentMigration.collateralMigrationAmount * 95 / 100, // 5% slippage tolerance
            issuanceMigrationAmount * 95 / 100, // 5% slippage tolerance
            _lpRecipientAddress != address(0)
                ? _lpRecipientAddress
                : orchestrator().authorizer().getRoleMember(
                    0x0000000000000000000000000000000000000000000000000000000000000000,
                    0
                ),
            block.timestamp + 15 minutes
        );

        // Verify the liquidity addition was successful
        require(amountA > 0 && amountB > 0, "Liquidity addition failed");

        // Mark as executed before emitting event
        _executed = true;

        LiquidityMigrationResult memory result = LiquidityMigrationResult({
            lpTokenAddress: lpTokenAddress,
            lpTokenAmount: lpTokenAmount,
            token0: tokenA,
            token1: tokenB,
            amount0: amountA,
            amount1: amountB
        });

        emit MigrationExecuted(result);

        return result;
    }
}
