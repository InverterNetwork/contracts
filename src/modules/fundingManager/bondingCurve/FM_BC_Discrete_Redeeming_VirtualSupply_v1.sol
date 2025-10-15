// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {VirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualCollateralSupplyBase_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IFM_BC_Discrete_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Discrete_Redeeming_VirtualSupply_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {PackedSegment} from
    "src/modules/fundingManager/bondingCurve/types/PackedSegment_v1.sol";
import {DiscreteCurveMathLib_v1} from
    "src/modules/fundingManager/bondingCurve/formulas/DiscreteCurveMathLib_v1.sol";

// External
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

contract FM_BC_Discrete_Redeeming_VirtualSupply_v1 is
    IFM_BC_Discrete_Redeeming_VirtualSupply_v1,
    IFundingManager_v1,
    VirtualCollateralSupplyBase_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(RedeemingBondingCurveBase_v1, VirtualCollateralSupplyBase_v1)
        returns (bool)
    {
        return interfaceId
            == type(IFM_BC_Discrete_Redeeming_VirtualSupply_v1).interfaceId
            || interfaceId == type(IFundingManager_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using DiscreteCurveMathLib_v1 for PackedSegment[];
    using SafeERC20 for IERC20;

    // ========================================================================
    // Storage

    IERC20 internal _token;

    /// @notice The array of packed segments that define the discrete bonding curve.
    PackedSegment[] internal _segments;
    // Cached protocol fee data
    IFM_BC_Discrete_Redeeming_VirtualSupply_v1.ProtocolFeeCache internal
        _protocolFeeCache;

    // --- Fee Related Storage ---
    /// @dev Project fee for buy operations, in Basis Points (BPS). 100 BPS = 1%.
    uint internal constant PROJECT_BUY_FEE_BPS = 100;
    /// @dev Project fee for sell operations, in Basis Points (BPS). 100 BPS = 1%.
    uint internal constant PROJECT_SELL_FEE_BPS = 100;

    /// @dev Cached function selectors for buy operations.
    bytes4 internal constant BUY_ORDER_SELECTOR =
        bytes4(keccak256("_buyOrder(address,uint,uint)"));
    /// @dev Cached function selectors for sell operations.
    bytes4 internal constant SELL_ORDER_SELECTOR =
        bytes4(keccak256("_sellOrder(address,uint,uint)"));
    /// @dev Cached function selectors for calculating purchase returns.
    bytes4 internal constant CALCULATE_PURCHASE_RETURN_SELECTOR =
        this.calculatePurchaseReturn.selector;
    /// @dev Cached function selectors for calculating sale returns.
    bytes4 internal constant CALCULATE_SALE_RETURN_SELECTOR =
        this.calculateSaleReturn.selector;

    // --- End Fee Related Storage ---

    /// @notice Storage gap for future upgrades.
    uint[50] private __gap;

    // =========================================================================
    // Constructor & Init

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata_,
        bytes memory configData_
    ) external virtual override(Module_v1) initializer {
        address issuanceTokenAddress;
        address collateralTokenAddress;
        PackedSegment[] memory initialSegments;

        (issuanceTokenAddress, collateralTokenAddress, initialSegments) =
            abi.decode(configData_, (address, address, PackedSegment[]));

        __Module_init(orchestrator_, metadata_);
        __FM_BC_Discrete_Redeeming_VirtualSupply_v1_Init(
            issuanceTokenAddress, collateralTokenAddress, initialSegments
        );
    }

    /// @notice Initializes the Discrete Redeeming Virtual Supply Contract.
    /// @dev    Only callable during the initialization.
    /// @param  issuanceTokenAddress_ The address of the token to be issued.
    /// @param  collateralTokenAddress_ The token that is accepted as collateral.
    /// @param  initialSegments_ The initial array of packed segments for the curve.
    function __FM_BC_Discrete_Redeeming_VirtualSupply_v1_Init(
        address issuanceTokenAddress_,
        address collateralTokenAddress_,
        PackedSegment[] memory initialSegments_
    ) internal onlyInitializing {
        // Set issuance token.
        _setIssuanceToken(ERC20Issuance_v1(issuanceTokenAddress_));

        // Set initial segments.
        _setSegments(initialSegments_);

        _token = IERC20(collateralTokenAddress_);
        emit IFundingManager_v1.OrchestratorTokenSet(
            collateralTokenAddress_,
            IERC20Metadata(collateralTokenAddress_).decimals()
        );

        // Initialize project fees
        _setBuyFee(PROJECT_BUY_FEE_BPS);
        _setSellFee(PROJECT_SELL_FEE_BPS);
    }

    // =========================================================================
    // Public - Getters

    // IFundingManager_v1 implementations
    function token(
    ) // This is the collateral token
     external view override(IFundingManager_v1) returns (IERC20) {
        return _token;
    }

    /// @inheritdoc IBondingCurveBase_v1
    function getIssuanceToken()
        external
        view
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        returns (address)
    {
        return address(issuanceToken);
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function getSegments()
        external
        view
        override
        returns (PackedSegment[] memory)
    {
        return _segments;
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function getStaticPriceForBuying()
        external
        view
        virtual
        override(
            BondingCurveBase_v1,
            IBondingCurveBase_v1,
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1
        )
        returns (uint)
    {
        (,, uint priceAtCurrentStep) =
            _segments._findPositionForSupply(virtualCollateralSupply + 1);
        return priceAtCurrentStep;
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function getStaticPriceForSelling()
        external
        view
        virtual
        override(
            RedeemingBondingCurveBase_v1, IFM_BC_Discrete_Redeeming_VirtualSupply_v1
        )
        returns (uint)
    {
        (,, uint priceAtCurrentStep) =
            _segments._findPositionForSupply(issuanceToken.totalSupply());
        return priceAtCurrentStep;
    }

    // =========================================================================
    // Public - Mutating

    /// @inheritdoc IBondingCurveBase_v1
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        buyingIsEnabled
        validReceiver(_receiver)
    {
        uint totalIssuanceTokenMinted;
        uint collateralFeeAmount;
        (totalIssuanceTokenMinted, collateralFeeAmount) =
            _buyOrder(_receiver, _depositAmount, _minAmountOut);

        // Add the net collateral (after fees) to the virtual collateral supply
        uint netCollateralAdded = _depositAmount - collateralFeeAmount;
        _addVirtualCollateralAmount(netCollateralAdded);
    }

    /// @inheritdoc IRedeemingBondingCurveBase_v1
    function sellTo(address _receiver, uint _depositAmount, uint _minAmountOut)
        public
        virtual
        override(RedeemingBondingCurveBase_v1)
        sellingIsEnabled
        validReceiver(_receiver)
    {
        (uint totalCollateralTokenMovedOut,) =
            _sellOrder(_receiver, _depositAmount, _minAmountOut);

        // Update virtual collateral supply by subtracting the total collateral that left the FM.
        _subVirtualCollateralAmount(totalCollateralTokenMovedOut);
    }

    // ------------------------------------------------------------------------
    // Public - Authorization

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function updateProtocolFeeCache() external {
        // Populate the cache directly for buy operations
        (
            _protocolFeeCache.collateralTreasury,
            _protocolFeeCache.issuanceTreasury,
            _protocolFeeCache.collateralFeeBuyBps,
            _protocolFeeCache.issuanceFeeBuyBps
        ) = super._getFunctionFeesAndTreasuryAddresses(BUY_ORDER_SELECTOR);

        address sellCollateralTreasury; // Temporary variable for sell collateral treasury
        address sellIssuanceTreasury; // Temporary variable for sell issuance treasury
        (
            sellCollateralTreasury,
            sellIssuanceTreasury,
            _protocolFeeCache.collateralFeeSellBps,
            _protocolFeeCache.issuanceFeeSellBps
        ) = super._getFunctionFeesAndTreasuryAddresses(SELL_ORDER_SELECTOR);

        // Logic to ensure consistent treasury addresses are stored in the cache,
        // prioritizing non-zero addresses from buy operations if FeeManager could return different ones.
        // Typically, a FeeManager provides consistent treasuries for a given (orchestrator, module) pair.
        if (
            _protocolFeeCache.collateralTreasury == address(0)
                && sellCollateralTreasury != address(0)
        ) {
            _protocolFeeCache.collateralTreasury = sellCollateralTreasury;
        }
        // Add assertion or handling if buyCollateralTreasury and sellCollateralTreasury are different and non-zero
        // require(buyCollateralTreasury == sellCollateralTreasury || sellCollateralTreasury == address(0) || buyCollateralTreasury == address(0) , "Inconsistent collateral treasuries");

        if (
            _protocolFeeCache.issuanceTreasury == address(0)
                && sellIssuanceTreasury != address(0)
        ) {
            _protocolFeeCache.issuanceTreasury = sellIssuanceTreasury;
        }
        // Add assertion or handling if buyIssuanceTreasury and sellIssuanceTreasury are different and non-zero
        // require(buyIssuanceTreasury == sellIssuanceTreasury || sellIssuanceTreasury == address(0) || buyIssuanceTreasury == address(0), "Inconsistent issuance treasuries");
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function setVirtualCollateralSupply(uint virtualSupply_)
        external
        virtual
        override(
            VirtualCollateralSupplyBase_v1,
            IFM_BC_Discrete_Redeeming_VirtualSupply_v1
        )
        onlyOrchestratorAdmin
    {
        _setVirtualCollateralSupply(virtualSupply_);
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function reconfigureSegments(PackedSegment[] memory newSegments_)
        external
        override
        onlyOrchestratorAdmin
    {
        uint currentVirtualCollateralSupply = virtualCollateralSupply;

        uint newCalculatedReserve =
            newSegments_._calculateReserveForSupply(issuanceToken.totalSupply());

        if (newCalculatedReserve != currentVirtualCollateralSupply) {
            revert InvarianceCheckFailed(
                newCalculatedReserve, currentVirtualCollateralSupply
            );
        }

        _setSegments(newSegments_);
    }

    // ------------------------------------------------------------------------
    // Public - OnlyPaymentClient

    /// @inheritdoc IFundingManager_v1
    function transferOrchestratorToken(address to_, uint amount_)
        external
        virtual
        onlyPaymentClient
    {
        if (
            amount_
                > _token.balanceOf(address(this)) - projectCollateralFeeCollected
        ) {
            revert InvalidOrchestratorTokenWithdrawAmount();
        }
        _token.safeTransfer(to_, amount_);

        emit TransferOrchestratorToken(to_, amount_);
    }

    // =========================================================================
    // Public - View - Fee Calculations (Overrides)

    /// @inheritdoc BondingCurveBase_v1
    function calculatePurchaseReturn(uint _depositAmount)
        public
        view
        virtual
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        returns (uint mintAmount)
    {
        _ensureNonZeroTradeParameters(_depositAmount, 1);

        uint netDeposit;
        // Deduct protocol and project buy fee from collateral
        (netDeposit,,) = _calculateNetAndSplitFees(
            _depositAmount,
            _protocolFeeCache.collateralFeeBuyBps, // Use cached protocol fee for buy collateral
            buyFee // Use project buyFee state variable (set in init)
        );

        // Get issuance token return from formula (using our discrete math wrapper)
        uint grossMintAmount = _issueTokensFormulaWrapper(netDeposit);

        // Deduct protocol buy fee from issuance tokens, if applicable
        (mintAmount,,) = _calculateNetAndSplitFees(
            grossMintAmount,
            _protocolFeeCache.issuanceFeeBuyBps, // Use cached protocol fee for buy issuance
            0 // No project fee on issuance side for now
        );
    }

    /// @inheritdoc RedeemingBondingCurveBase_v1
    function calculateSaleReturn(uint _depositAmount)
        public
        view
        virtual
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount)
    {
        _ensureNonZeroTradeParameters(_depositAmount, 1);

        uint netIssuanceDeposit;
        // Deduct protocol sell fee from deposited issuance tokens
        (netIssuanceDeposit,,) = _calculateNetAndSplitFees(
            _depositAmount,
            _protocolFeeCache.issuanceFeeSellBps, // Use cached protocol fee for sell issuance
            0 // No project fee on issuance side
        );

        // Get collateral token return from formula (using our discrete math wrapper)
        uint grossRedeemAmount = _redeemTokensFormulaWrapper(netIssuanceDeposit);

        // Deduct protocol and project sell fee from collateral tokens
        (redeemAmount,,) = _calculateNetAndSplitFees(
            grossRedeemAmount,
            _protocolFeeCache.collateralFeeSellBps, // Use cached protocol fee for sell collateral
            _getSellFee()
        );
    }

    // =========================================================================
    // Internal

    // ------------------------------------------------------------------------
    // Internal - Setters

    /// @notice Sets the issuance token for the bonding curve.
    /// @param  newIssuanceToken_ The new issuance token.
    function _setIssuanceToken(ERC20Issuance_v1 newIssuanceToken_) internal {
        // collateralDecimals_ argument removed
        issuanceToken = newIssuanceToken_;

        emit IBondingCurveBase_v1.IssuanceTokenSet(
            address(newIssuanceToken_),
            IERC20Metadata(address(newIssuanceToken_)).decimals()
        );
    }

    /// @notice Sets the segments for the discrete bonding curve.
    /// @param  newSegments_ The array of packed segments.
    function _setSegments(PackedSegment[] memory newSegments_) internal {
        DiscreteCurveMathLib_v1._validateSegmentArray(newSegments_);
        _segments = newSegments_;
        emit SegmentsSet(newSegments_);
    }

    // ------------------------------------------------------------------------
    // Internal - Overrides - BondingCurveBase_v1

    // BondingCurveBase_v1 implementations (inherited via RedeemingBondingCurveBase_v1)
    function _processCollateralTokensForBuyOperation(uint _amount)
        internal
        virtual
        override
    {
        // This function is not used in this implementation.
    }

    function _handleIssuanceTokensAfterBuy(address _receiver, uint _amount)
        internal
        virtual
        override
    {
        issuanceToken.mint(_receiver, _amount);
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        override
        returns (uint)
    {
        (uint tokensToMint,) = _segments._calculatePurchaseReturn(
            _depositAmount, issuanceToken.totalSupply()
        );
        return tokensToMint;
    }

    // ------------------------------------------------------------------------
    // Internal - Overrides - RedeemingBondingCurveBase_v1

    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        override
        returns (uint)
    {
        (uint collateralToReturn,) = _segments._calculateSaleReturn(
            _depositAmount, issuanceToken.totalSupply()
        );
        return collateralToReturn;
    }

    function _handleCollateralTokensAfterSell(
        address _receiver,
        uint _collateralTokenAmount
    ) internal virtual override {
        _token.safeTransfer(_receiver, _collateralTokenAmount);
    }

    // ------------------------------------------------------------------------
    // Internal - Overrides - VirtualCollateralSupplyBase_v1

    /// @dev    Internal function to directly set the virtual collateral supply to a new value.
    /// @param  virtualSupply_ The new value to set for the virtual collateral supply.
    function _setVirtualCollateralSupply(uint virtualSupply_)
        internal
        override(VirtualCollateralSupplyBase_v1)
    {
        super._setVirtualCollateralSupply(virtualSupply_);
    }

    // ------------------------------------------------------------------------
    // Internal - Overrides - Module_v1

    /**
     * @notice  Overrides the base function to return cached protocol fees and treasury addresses
     *          for buy and sell operations specific to this funding manager.
     * @dev     This ensures that fee calculations within `calculatePurchaseReturn`, `calculateSaleReturn`,
     *          `_buyOrder`, and `_sellOrder` use the fees fetched and cached during initialization,
     *          avoiding repeated calls to the FeeManager for these operations.
     *          For other function selectors, it defers to the super implementation.
     * @param   functionSelector_ The selector of the function for which fees are being queried.
     * @return  collateralTreasury_ The address of the protocol's collateral fee treasury.
     * @return  issuanceTreasury_ The address of the protocol's issuance fee treasury.
     * @return  collateralFeeBps_ The protocol fee percentage for collateral tokens.
     * @return  issuanceFeeBps_ The protocol fee percentage for issuance tokens.
     */
    function _getFunctionFeesAndTreasuryAddresses(bytes4 functionSelector_)
        internal
        view
        override // Overrides Module_v1._getFunctionFeesAndTreasuryAddresses
        returns (
            address collateralTreasury_,
            address issuanceTreasury_,
            uint collateralFeeBps_,
            uint issuanceFeeBps_
        )
    {
        // Set common treasuries once
        collateralTreasury_ = _protocolFeeCache.collateralTreasury;
        issuanceTreasury_ = _protocolFeeCache.issuanceTreasury;

        // Then just handle the different fees
        if (
            functionSelector_ == BUY_ORDER_SELECTOR
                || functionSelector_ == CALCULATE_PURCHASE_RETURN_SELECTOR
        ) {
            collateralFeeBps_ = _protocolFeeCache.collateralFeeBuyBps;
            issuanceFeeBps_ = _protocolFeeCache.issuanceFeeBuyBps;
        } else if (
            functionSelector_ == SELL_ORDER_SELECTOR
                || functionSelector_ == CALCULATE_SALE_RETURN_SELECTOR
        ) {
            collateralFeeBps_ = _protocolFeeCache.collateralFeeSellBps;
            issuanceFeeBps_ = _protocolFeeCache.issuanceFeeSellBps;
        } else {
            // For any other selectors not handled by this cache, defer to the base implementation
            // which would typically query the FeeManager directly.
            return super._getFunctionFeesAndTreasuryAddresses(functionSelector_);
        }
    }
}
