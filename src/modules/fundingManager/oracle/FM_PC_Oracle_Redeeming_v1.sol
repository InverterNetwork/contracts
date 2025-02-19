// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal
import {IFM_PC_Oracle_Redeeming_v1} from
    "@fm/oracle/interfaces/IFM_PC_Oracle_Redeeming_v1.sol";
import {IERC20Issuance_Blacklist_v1} from
    "@ex/token/interfaces/IERC20Issuance_Blacklist_v1.sol";
import {IOraclePrice_v1} from "@lm/interfaces/IOraclePrice_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {FM_BC_Tools} from "@fm/bondingCurve/FM_BC_Tools.sol";
import {
    ERC20PaymentClientBase_v2,
    IERC20PaymentClientBase_v2
} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {IERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";

/**
 * @title   External Price Oracle Funding Manager with Payment Client
 *
 * @notice  A funding manager implementation that manages token issuance and
 *          redemption based on external oracle price feeds. While token
 *          issuance is processed immediately, redemption requests are added
 *          to a queue for delayed processing through an integrated payment
 *          client system.
 *
 * @dev     Inherits functionality from:
 *          - IFM_PC_Oracle_Redeeming_v1: Implementation interface
 *          - ERC20PaymentClientBase_v2: Payment processing capabilities
 *          - RedeemingBondingCurveBase_v1: Token issuance and redemption logic
 *
 *          Key features:
 *              - Oracle-driven token pricing
 *                Uses external price feeds to determine token value for all
 *                issuance and redemption operations
 *
 *              - Token issuance and redemption
 *                Mints new tokens during purchases and burns tokens during
 *                sell operations at oracle-determined prices
 *
 *              - Whitelisting system for controlled token distribution
 *                Restricts token purchases and sales to approved addresses
 *
 *              - Queue-based redemption and payment processing
 *                Creates payment orders in a queue and sends them to the payment
 *                processor for executing token redemptions.
 *
 *              - Fee management on buy/sell operations
 *                Configurable fee structure for trading operations
 *
 * @custom:setup    This module requires the following MANDATORY setup steps:
 *
 *                  1. Grant Minting Permission:
 *                     - Purpose: The module needs direct minting/burning
 *                                capability to handle token issuance and
 *                                redemption operations. Without this permission,
 *                                the module cannot mint or burn tokens.
 *                     - How:     The owner of the issuance token contract must
 *                                call the minter setting function to authorize
 *                                this module
 *                     - Example: issuanceToken.setMinter(moduleAddress, true);
 *
 *                  2. Configure Oracle:
 *                     - Purpose: Since the Oracle is a separate module, it
 *                                cannot be set during initialization. The Oracle
 *                                provides price feed data needed for token
 *                                valuations during issuance and redemption.
 *                     - How:     The OrchestratorAdmin must first get the
 *                                deployed Oracle module's address, then call the
 *                                setter function
 *                     - Example: module.setOracleAddress(oracleAddress);
 *
 *                  3. Setup Whitelist:
 *                     - Purpose: Implements access control for buy/sell
 *                                functions. Only whitelisted addresses can
 *                                participate in token buy & sell operations to
 *                                provide a security layer for controlled token
 *                                distribution and compliance.
 *                     - How:     The OrchestratorAdmin (or WHITELIST_ROLE_ADMIN
 *                                if configured) must:
 *                                1. Retrieve the whitelist role identifier
 *                                2. Grant the role to desired addresses
 *                     - Example: module.grantModuleRole(
 *                                module.getWhitelistRole(),
 *                                userAddress
 *                                );
 *
 *                  4. Setup Queue Executors:
 *                     - Purpose: Implements access control for authorized
 *                                addresses that can process the redemption queue.
 *                     - How:     The OrchestratorAdmin (or
 *                                QUEUE_EXECUTOR_ROLE_ADMIN if configured) must:
 *                                1. Retrieve the executor role identifier
 *                                2. Grant the role to designated executors
 *                     - Example: module.grantModuleRole(
 *                                 module.getQueueExecutorRole(),
 *                                 executorAddress
 *                                );
 *
 *                  5. Enable Trading:
 *                     - Purpose: Activates the buy/sell functionality of the
 *                                contract. Trading must be explicitly enabled.
 *                     - How:     The OrchestratorAdmin must enable both buying
 *                                and selling operations separately
 *                     - Example: module.openBuy();
 *                                module.openSell();
 *
 *                  OPTIONAL setup steps for enhanced administration:
 *
 *                  1. Custom Whitelist Admin:
 *                     - Purpose: Enables delegation of whitelist management to a
 *                                dedicated admin role instead of relying on the
 *                                OrchestratorAdmin. This allows for more granular
 *                                access control and operational flexibility.
 *                     - How:     The OrchestratorAdmin must:
 *                                1. Generate the role IDs for both roles
 *                                2. Transfer admin rights through the Authorizer
 *                     - Example: authorizer.transferAdminRole(
 *                                authorizer.generateRoleId(
 *                                  moduleAddress,
 *                                   module.getWhitelistRole()
 *                                ),
 *                                authorizer.generateRoleId(
 *                                   moduleAddress,
 *                                   module.getWhitelistRoleAdmin()
 *                                 )
 *                                );
 *
 *                  2. Custom Queue Executor Admin:
 *                     - Purpose: Allows delegation of queue executor management
 *                                to a dedicated admin role instead of the
 *                                OrchestratorAdmin. This allows for more granular
 *                                access control and operational flexibility.
 *                     - How:     The OrchestratorAdmin must:
 *                                1. Generate the role IDs for both roles
 *                                2. Transfer admin rights through the Authorizer
 *                     - Example: authorizer.transferAdminRole(
 *                                authorizer.generateRoleId(
 *                                   moduleAddress,
 *                                   module.getQueueExecutorRole()
 *                                ),
 *                                authorizer.generateRoleId(
 *                                   moduleAddress,
 *                                   module.getQueueExecutorRoleAdmin()
 *                                 )
 *                                );
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @custom:version  v1.0.0
 *
 * @custom:standard-version v1.0.0
 *
 * @author  Zealynx Security
 */
contract FM_PC_Oracle_Redeeming_v1 is
    IFM_PC_Oracle_Redeeming_v1,
    ERC20PaymentClientBase_v2,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        override(ERC20PaymentClientBase_v2, RedeemingBondingCurveBase_v1)
        returns (bool isSupported_)
    {
        return interfaceId_ == type(IFM_PC_Oracle_Redeeming_v1).interfaceId
            || interfaceId_ == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }

    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants

    /// @notice Role identifier for accounts who are whitelisted to buy and sell.
    bytes32 private constant WHITELIST_ROLE = "WHITELIST_ROLE";

    /// @notice Role identifier for the admin authorized to assign the whitelist
    ///         role.
    /// @dev    This role should be set as the role admin for the WHITELIST_ROLE
    ///         within the Authorizer module.
    bytes32 private constant WHITELIST_ROLE_ADMIN = "WHITELIST_ROLE_ADMIN";

    /// @notice Role identifier for accounts who are allowed to manually execute
    ///         the redemption queue.
    bytes32 private constant QUEUE_EXECUTOR_ROLE = "QUEUE_EXECUTOR_ROLE";

    /// @notice Role identifier for the admin authorized to assign the queue
    ///         execution role.
    ///         role.
    /// @dev    This role should be set as the role admin for the
    ///         QUEUE_EXECUTOR_ROLE within the Authorizer module.
    bytes32 private constant QUEUE_EXECUTOR_ROLE_ADMIN =
        "QUEUE_EXECUTOR_ROLE_ADMIN";

    /// @notice Flag used for the payment order.
    uint private constant FLAG_ORDER_ID = 0;

    // -------------------------------------------------------------------------
    // State Variables

    /// @notice Oracle price feed contract used for price discovery.
    /// @dev    Contract that provides external price information for token
    ///         valuation.
    IOraclePrice_v1 private _oracle;

    /// @notice Token that is accepted by this funding manager for deposits.
    /// @dev    The ERC20 token contract used for collateral in this funding
    ///         manager.
    IERC20 private _token;

    /// @notice Token decimals of the issuance token.
    /// @dev    Number of decimal places used by the issuance token for proper
    ///         decimal handling.
    uint8 private _issuanceTokenDecimals;

    /// @notice Token decimals of the Orchestrator token.
    /// @dev    Number of decimal places used by the collateral token for proper
    ///         decimal handling.
    uint8 private _collateralTokenDecimals;

    /// @notice Maximum fee that can be charged for sell operations, in base
    ///         points.
    /// @dev    Maximum allowed project fee percentage that can be charged when
    ///         selling tokens.
    uint private _maxProjectSellFee;

    /// @notice Maximum fee that can be charged for buy operations, in base
    ///         points.
    /// @dev    Maximum allowed project fee percentage for buying tokens.
    uint private _maxProjectBuyFee;

    /// @notice Order ID counter for tracking individual orders.
    /// @dev    Unique identifier for the current order being processed.
    uint private _orderId;

    /// @notice Total amount of collateral tokens currently in redemption
    ///         process.
    /// @dev    Tracks the sum of all pending redemption orders.
    uint private _openRedemptionAmount;

    /// @notice Flag indicating if direct operations are only allowed.
    bool internal _isDirectOperationsOnly;

    /// @notice Address of the project treasury which will receive the
    ///         collateral tokens.
    address private _projectTreasury;

    // -------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to check if only direct operations are allowed.
    modifier thirdPartyOperationsEnabled() {
        if (_isDirectOperationsOnly) {
            revert
                Module__FM_PC_ExternalPrice_Redeeming_ThirdPartyOperationsDisabled();
        }
        _;
    }

    // -------------------------------------------------------------------------
    // Initialization Function

    /// @notice The module's initializer function.
    /// @dev	CAN be overridden by downstream contract.
    /// @dev	MUST call `__Module_init()`.
    /// @param orchestrator_ The orchestrator contract.
    /// @param metadata_ The metadata of the module.
    /// @param configData_ The config data of the module, comprised of:
    ///     - address: projectTreasury: The project treasury address.
    ///     - address: issuanceToken: The issuance token address.
    ///     - address: acceptedToken: The accepted token address.
    ///     - uint: buyFee: The project buy fee.
    ///     - uint: sellFee: The project sell fee.
    ///     - uint: maxSellFee: The maximum project sell fee.
    ///     - uint: maxProjectBuyFee: The maximum project buy fee.
    ///     - bool: isDirectOperationsOnly: Whether only direct operations
    ///       are allowed.
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external override(Module_v1) initializer {
        // Initialize base module.
        __Module_init(orchestrator_, metadata_);

        // Decode config data.
        (
            address projectTreasury_,
            address issuanceToken_,
            address acceptedToken_,
            uint buyFee_,
            uint sellFee_,
            uint maxSellFee_,
            uint maxProjectBuyFee_,
            bool isDirectOperationsOnly_
        ) = abi.decode(
            configData_,
            (address, address, address, uint, uint, uint, uint, bool)
        );

        // Set accepted token.
        _token = IERC20(acceptedToken_);

        // Cache token decimals for collateral.
        _collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Initialize base functionality (should handle token settings).
        _setIssuanceToken(issuanceToken_);

        // Set max fees.
        _setMaxProjectBuyFee(maxProjectBuyFee_);
        _setMaxProjectSellFee(maxSellFee_);

        // Set fees.
        _setBuyFee(buyFee_);
        _setSellFee(sellFee_);

        // Set project treasury.
        _setProjectTreasury(projectTreasury_);

        // Set direct operations only flag.
        _setIsDirectOperationsOnly(isDirectOperationsOnly_);

        bytes32 flags;
        flags |= bytes32(1 << FLAG_ORDER_ID);

        __ERC20PaymentClientBase_v2_init(flags);
    }

    // -------------------------------------------------------------------------
    // View Functions

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getWhitelistRole() public pure virtual returns (bytes32 role_) {
        return WHITELIST_ROLE;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getWhitelistRoleAdmin()
        public
        pure
        virtual
        returns (bytes32 role_)
    {
        return WHITELIST_ROLE_ADMIN;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getQueueExecutorRole()
        public
        pure
        virtual
        returns (bytes32 role_)
    {
        return QUEUE_EXECUTOR_ROLE;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getQueueExecutorRoleAdmin()
        public
        pure
        virtual
        returns (bytes32 role_)
    {
        return QUEUE_EXECUTOR_ROLE_ADMIN;
    }

    /// @inheritdoc IFundingManager_v1
    function token() public view virtual override returns (IERC20 token_) {
        return _token;
    }

    /// @inheritdoc IBondingCurveBase_v1
    function getStaticPriceForBuying()
        public
        view
        virtual
        override(BondingCurveBase_v1)
        returns (uint buyPrice_)
    {
        return _oracle.getPriceForIssuance();
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function getStaticPriceForSelling()
        public
        view
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        returns (uint sellPrice_)
    {
        return _oracle.getPriceForRedemption();
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getOpenRedemptionAmount()
        external
        view
        virtual
        returns (uint amount_)
    {
        return _openRedemptionAmount;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getOrderId() external view virtual returns (uint orderId_) {
        return _orderId;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getProjectTreasury()
        external
        view
        virtual
        returns (address treasury_)
    {
        return _projectTreasury;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getIsDirectOperationsOnly()
        public
        view
        virtual
        returns (bool isDirectOnly_)
    {
        return _isDirectOperationsOnly;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getOracle() external view virtual returns (address oracle_) {
        return address(_oracle);
    }

    // -------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function depositReserve(uint amount_) external virtual {
        if (amount_ == 0) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidAmount();
        }

        // Transfer collateral from sender to FM.
        IERC20(token()).safeTransferFrom(_msgSender(), address(this), amount_);

        emit ReserveDeposited(_msgSender(), amount_);
    }

    // -------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc BondingCurveBase_v1
    function buy(uint collateralAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
    {
        super.buyFor(_msgSender(), collateralAmount_, minAmountOut_);
    }

    /// @inheritdoc BondingCurveBase_v1
    function buyFor(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(BondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
        thirdPartyOperationsEnabled
    {
        super.buyFor(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    function sell(uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
    {
        super.sellTo(_msgSender(), depositAmount_, minAmountOut_);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    function sellTo(address receiver_, uint depositAmount_, uint minAmountOut_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyModuleRole(WHITELIST_ROLE)
        thirdPartyOperationsEnabled
    {
        super.sellTo(receiver_, depositAmount_, minAmountOut_);
    }

    /// @inheritdoc IERC20PaymentClientBase_v2
    function amountPaid(address token_, uint amount_)
        public
        virtual
        override(ERC20PaymentClientBase_v2, IERC20PaymentClientBase_v2)
    {
        _deductFromOpenRedemptionAmount(amount_);
        super.amountPaid(token_, amount_);
    }

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to_, uint amount_)
        external
        virtual
        onlyPaymentClient
    {
        token().safeTransfer(to_, amount_);

        emit TransferOrchestratorToken(to_, amount_);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function setSellFee(uint fee_)
        public
        virtual
        override(RedeemingBondingCurveBase_v1, IRedeemingBondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        _setSellFee(fee_);
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getSellFee() public view virtual returns (uint fee_) {
        return sellFee;
    }

    /// @inheritdoc IBondingCurveBase_v1
    function setBuyFee(uint fee_)
        external
        virtual
        override(BondingCurveBase_v1)
        onlyOrchestratorAdmin
    {
        _setBuyFee(fee_);
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function setProjectTreasury(address projectTreasury_)
        external
        virtual
        onlyOrchestratorAdmin
    {
        _setProjectTreasury(projectTreasury_);
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function setOracleAddress(address oracle_)
        external
        virtual
        onlyOrchestratorAdmin
    {
        _setOracleAddress(oracle_);
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getBuyFee() public view virtual returns (uint buyFee_) {
        return buyFee;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getMaxProjectBuyFee()
        public
        view
        virtual
        returns (uint maxProjectBuyFee_)
    {
        return _maxProjectBuyFee;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function getMaxProjectSellFee()
        public
        view
        virtual
        returns (uint maxProjectSellFee_)
    {
        return _maxProjectSellFee;
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function setIsDirectOperationsOnly(bool isDirectOperationsOnly_)
        public
        virtual
        onlyOrchestratorAdmin
    {
        _setIsDirectOperationsOnly(isDirectOperationsOnly_);
    }

    /// @inheritdoc IFM_PC_Oracle_Redeeming_v1
    function executeRedemptionQueue()
        external
        virtual
        onlyModuleRole(QUEUE_EXECUTOR_ROLE)
    {
        (bool success,) = address(__Module_orchestrator.paymentProcessor()).call(
            abi.encodeWithSignature(
                "executePaymentQueue(address)", address(this)
            )
        );
        if (!success) {
            revert Module__FM_PC_ExternalPrice_Redeeming_QueueExecutionFailed();
        }
    }

    // -------------------------------------------------------------------------
    // Internal Functions

    /// @notice Sets the value of the `isDirectOperationsOnly` flag.
    /// @param  isDirectOperationsOnly_ The new value of the flag.
    function _setIsDirectOperationsOnly(bool isDirectOperationsOnly_)
        internal
        virtual
    {
        emit DirectOperationsOnlyUpdated(
            _isDirectOperationsOnly, isDirectOperationsOnly_
        );
        _isDirectOperationsOnly = isDirectOperationsOnly_;
    }

    /// @notice Creates and emits a new redemption order.
    /// @dev    This function wraps the `_createAndEmitOrder` internal function
    ///         with specified parameters to handle the transaction and direct
    ///         the proceeds.
    /// @param  receiver_ The address that will receive the redeemed tokens.
    /// @param  depositAmount_ The amount of tokens to be sold.
    /// @param  collateralRedeemAmount_ The amount of collateral to redeem.
    /// @param  projectCollateralFeeAmount_ The amount of redemption fee to charge.
    function _createAndEmitOrder(
        address receiver_,
        uint depositAmount_,
        uint collateralRedeemAmount_,
        uint projectCollateralFeeAmount_
    ) internal virtual {
        // Generate new order ID.
        _orderId = ++_orderId;

        // Update open redemption amount.
        _addToOpenRedemptionAmount(collateralRedeemAmount_);

        bytes32 flags;
        bytes32[] memory data;

        {
            bytes32[] memory paymentParameters = new bytes32[](1);
            paymentParameters[0] = bytes32(_orderId);

            (flags, data) = _assemblePaymentConfig(paymentParameters);
        }
        // Create and add payment order.
        PaymentOrder memory order = PaymentOrder({
            recipient: receiver_,
            paymentToken: address(token()),
            amount: collateralRedeemAmount_,
            originChainId: block.chainid,
            targetChainId: block.chainid,
            flags: flags,
            data: data
        });

        // Add order to payment client.
        _addPaymentOrder(order);

        // Process payments through the payment processor.
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClientBase_v2(address(this))
        );

        // Emit event with order details.
        emit RedemptionOrderCreated(
            address(this),
            _orderId,
            _msgSender(),
            receiver_,
            depositAmount_,
            _oracle.getPriceForRedemption(),
            sellFee,
            projectCollateralFeeAmount_,
            collateralRedeemAmount_,
            address(token()),
            RedemptionState.PENDING
        );
    }

    /// @notice Executes a sell order, with the proceeds being sent directly to
    ///         the _receiver's address.
    /// @dev    This function wraps the `_sellOrder` internal function with
    ///         the specified parameters to handle the transaction and direct
    ///         the proceeds.
    /// @param  _receiver The address that will receive the redeemed tokens.
    /// @param  _depositAmount The amount of tokens to be sold.
    /// @param  _minAmountOut The minimum acceptable amount of proceeds that the
    ///         receiver should receive from the sale.
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    )
        internal
        virtual
        override(RedeemingBondingCurveBase_v1)
        returns (
            uint totalCollateralTokenMovedOut_,
            uint projectCollateralFeeAmount_
        )
    {
        _ensureNonZeroTradeParameters(_depositAmount, _minAmountOut);
        // Get protocol fee percentages and treasury addresses.
        (
            address protocolCollateralTreasury,
            address protocolIssuanceTreasury,
            uint protocolCollateralSellFeePercentage,
            uint protocolIssuanceSellFeePercentage
        ) = _getFunctionFeesAndTreasuryAddresses(
            bytes4(keccak256(bytes("_sellOrder(address,uint,uint)")))
        );

        uint protocolIssuanceFeeAmount;
        uint protocolCollateralFeeAmount;
        uint netDeposit;

        // Get net amount, protocol and project fee amounts. Currently there is
        // no issuance project fee enabled.
        (netDeposit, protocolIssuanceFeeAmount, /* projectFee */ ) =
        _calculateNetAndSplitFees(
            _depositAmount, protocolIssuanceSellFeePercentage, 0
        );

        // Calculate redeem amount based on upstream formula.
        totalCollateralTokenMovedOut_ = _redeemTokensFormulaWrapper(netDeposit);

        // Burn issued token from user.
        _burn(_msgSender(), _depositAmount);

        // Process the protocol fee. We can re-mint some of the burned tokens,
        // since we aren't paying out the backing collateral.
        _processProtocolFeeViaMinting(
            protocolIssuanceTreasury, protocolIssuanceFeeAmount
        );

        // Cache Collateral Token.
        IERC20 collateralToken = __Module_orchestrator.fundingManager().token();

        uint netCollateralRedeemAmount;
        // Get net amount, protocol and project fee amounts.
        (
            netCollateralRedeemAmount,
            protocolCollateralFeeAmount,
            projectCollateralFeeAmount_
        ) = _calculateNetAndSplitFees(
            totalCollateralTokenMovedOut_,
            protocolCollateralSellFeePercentage,
            sellFee
        );

        // Process the protocol fee.
        _processProtocolFeeViaTransfer(
            protocolCollateralTreasury,
            collateralToken,
            protocolCollateralFeeAmount
        );

        // Add project fee if applicable.
        if (projectCollateralFeeAmount_ > 0) {
            _projectFeeCollected(projectCollateralFeeAmount_);
        }

        // Revert when the redeem amount is lower than minimum amount the user
        // expects.
        if (netCollateralRedeemAmount < _minAmountOut) {
            revert Module__BondingCurveBase__InsufficientOutputAmount();
        }

        // Create and emit the order.
        _createAndEmitOrder(
            _receiver,
            _depositAmount,
            netCollateralRedeemAmount,
            projectCollateralFeeAmount_
        );

        // Emit event for tokens sold.
        emit TokensSold(
            _receiver, _depositAmount, netCollateralRedeemAmount, _msgSender()
        );
    }

    /// @dev    Internal function which only emits the event for amount of
    ///         project fee collected. The contract does not hold collateral
    ///         as the payout is managed through a redemption queue.
    /// @param  _projectFeeAmount The amount of fee collected.
    function _projectFeeCollected(uint _projectFeeAmount)
        internal
        virtual
        override(BondingCurveBase_v1)
    {
        emit ProjectCollateralFeeAdded(_projectFeeAmount);
    }

    /// @notice Sets the maximum fee that can be charged for buy operations.
    /// @param  fee_ The maximum fee percentage to set.
    function _setMaxProjectBuyFee(uint fee_) internal virtual {
        if (fee_ >= BPS) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, BPS
            );
        }
        _maxProjectBuyFee = fee_;
        emit MaxProjectBuyFeeSet(_maxProjectBuyFee);
    }

    /// @notice Sets the maximum fee that can be charged for sell operations.
    /// @param  fee_ The maximum fee percentage to set.
    function _setMaxProjectSellFee(uint fee_) internal virtual {
        if (fee_ >= BPS) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, BPS
            );
        }
        _maxProjectSellFee = fee_;
        emit MaxProjectSellFeeSet(_maxProjectSellFee);
    }

    /// @notice Sets the sell fee.
    /// @dev    Overrides the internal function from RedeemingBondingCurveBase_v1.
    ///         Revert if sell fee exceeds max project sell fee.
    /// @param  fee_ The fee percentage to set.
    function _setSellFee(uint fee_)
        internal
        virtual
        override(RedeemingBondingCurveBase_v1)
    {
        // Check that fee doesn't exceed maximum allowed
        if (fee_ > _maxProjectSellFee) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, _maxProjectSellFee
            );
        }

        super._setSellFee(fee_);
    }

    /// @notice Sets the buy fee.
    /// @dev    Overrides the internal function from BondingCurveBase_v1.
    ///         Revert if buy fee exceeds max project buy fee.
    /// @param  fee_ The fee percentage to set.
    function _setBuyFee(uint fee_)
        internal
        virtual
        override(BondingCurveBase_v1)
    {
        // Check that fee doesn't exceed maximum allowed.
        if (fee_ > _maxProjectBuyFee) {
            revert Module__FM_PC_ExternalPrice_Redeeming_FeeExceedsMaximum(
                fee_, _maxProjectBuyFee
            );
        }
        super._setBuyFee(fee_);
    }

    /// @param  depositAmount_ The amount being deposited.
    /// @return mintAmount_ The calculated token amount.
    function _issueTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        virtual
        override(BondingCurveBase_v1)
        returns (uint mintAmount_)
    {
        // Calculate the mint amount.
        mintAmount_ = depositAmount_ * (10 ** _collateralTokenDecimals)
            / _oracle.getPriceForIssuance();

        // Convert mint amount to issuance token decimals.
        mintAmount_ = FM_BC_Tools._convertAmountToRequiredDecimal(
            mintAmount_, _collateralTokenDecimals, _issuanceTokenDecimals
        );
    }

    /// @param  depositAmount_ The amount being redeemed.
    /// @return redeemAmount_ The calculated collateral amount.
    function _redeemTokensFormulaWrapper(uint depositAmount_)
        internal
        view
        virtual
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount_)
    {
        // Convert issuance token deposit amount to collateral token decimals.
        uint collateralDecimalsConverterdDepositAmount = FM_BC_Tools
            ._convertAmountToRequiredDecimal(
            depositAmount_, _issuanceTokenDecimals, _collateralTokenDecimals
        );

        // Calculate the redeem amount.
        redeemAmount_ = (
            _oracle.getPriceForRedemption()
                * collateralDecimalsConverterdDepositAmount
        ) / 10 ** _collateralTokenDecimals;
    }

    /// @dev    Sets the issuance token.
    ///         This function overrides the internal function set in
    ///         {BondingCurveBase_v1}, and it updates the `issuanceToken` state
    ///         variable and caches the decimals as `_issuanceTokenDecimals`.
    /// @param  issuanceToken_ The token which will be issued by the Bonding Curve.
    function _setIssuanceToken(address issuanceToken_)
        internal
        virtual
        override(BondingCurveBase_v1)
    {
        uint8 decimals_ = IERC20Metadata(issuanceToken_).decimals();

        issuanceToken = IERC20Issuance_v1(issuanceToken_);
        _issuanceTokenDecimals = decimals_;
        emit IssuanceTokenSet(issuanceToken_, decimals_);
    }

    /// @notice Sets the oracle address.
    /// @dev    May revert with
    ///         Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface.
    /// @param  oracleAddress_ The address of the oracle.
    function _setOracleAddress(address oracleAddress_) internal virtual {
        if (
            !ERC165Upgradeable(oracleAddress_).supportsInterface(
                type(IOraclePrice_v1).interfaceId
            )
        ) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidOracleInterface(
            );
        }
        emit OracleUpdated(address(_oracle), oracleAddress_);
        _oracle = IOraclePrice_v1(oracleAddress_);
    }

    /// @notice Sets the project treasury address.
    /// @dev    May revert with
    ///         Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury.
    /// @param  projectTreasury_ The address of the project treasury.
    function _setProjectTreasury(address projectTreasury_) internal virtual {
        if (projectTreasury_ == address(0)) {
            revert Module__FM_PC_ExternalPrice_Redeeming_InvalidProjectTreasury(
            );
        }
        emit ProjectTreasuryUpdated(_projectTreasury, projectTreasury_);
        _projectTreasury = projectTreasury_;
    }

    /// @notice Deducts the amount of redeemed tokens from the open redemption
    ///         amount.
    /// @param  processedRedemptionAmount_ The amount of redemption tokens that
    ///         were processed.
    function _deductFromOpenRedemptionAmount(uint processedRedemptionAmount_)
        internal
        virtual
    {
        _openRedemptionAmount -= processedRedemptionAmount_;
        emit RedemptionAmountUpdated(_openRedemptionAmount);
    }

    /// @notice Adds the amount of redeemed tokens to the open redemption
    ///         amount.
    /// @param  addedOpenRedemptionAmount_ The amount of redeemed tokens to add.
    function _addToOpenRedemptionAmount(uint addedOpenRedemptionAmount_)
        internal
        virtual
    {
        _openRedemptionAmount += addedOpenRedemptionAmount_;
        emit RedemptionAmountUpdated(_openRedemptionAmount);
    }

    /// @inheritdoc BondingCurveBase_v1
    function _handleIssuanceTokensAfterBuy(address recipient_, uint amount_)
        internal
        virtual
        override
    {
        // Transfer issuance tokens to recipient.
        IERC20Issuance_v1(issuanceToken).mint(recipient_, amount_);
    }

    /// @inheritdoc BondingCurveBase_v1
    /// @dev    Implementation transfer collateral tokens to the project treasury.
    function _handleCollateralTokensBeforeBuy(address _provider, uint _amount)
        internal
        virtual
        override
    {
        IERC20(token()).safeTransferFrom(_provider, _projectTreasury, _amount);
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    /// @dev    Implementation does not transfer collateral tokens to recipient
    ///         as the payout is managed through a redemption queue.
    function _handleCollateralTokensAfterSell(address recipient_, uint amount_)
        internal
        virtual
        override
    {
        // This function is not used in this implementation.
    }

    /// @inheritdoc ERC20PaymentClientBase_v2
    /// @dev	We do not need to ensure the token balance because all the
    ///         collateral is taken out.
    function _ensureTokenBalance(address token_) internal virtual override {
        // No balance check needed.
    }

    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;
}
