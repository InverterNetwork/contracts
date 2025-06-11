// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Internal
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {VirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualIssuanceSupplyBase_v1.sol";
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
    VirtualIssuanceSupplyBase_v1,
    VirtualCollateralSupplyBase_v1,
    RedeemingBondingCurveBase_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            RedeemingBondingCurveBase_v1,
            VirtualCollateralSupplyBase_v1,
            VirtualIssuanceSupplyBase_v1
        )
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
        _setIssuanceToken(ERC20Issuance_v1(issuanceTokenAddress_)); // collateralDecimals argument removed

        // Set initial segments.
        _setSegments(initialSegments_);

        _token = IERC20(collateralTokenAddress_);
        emit IFundingManager_v1.OrchestratorTokenSet(
            collateralTokenAddress_,
            IERC20Metadata(collateralTokenAddress_).decimals()
        );
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
            _segments._findPositionForSupply(virtualIssuanceSupply);
        return priceAtCurrentStep;
    }

    // =========================================================================
    // Public - Mutating

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

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function setVirtualIssuanceSupply(uint virtualSupply_)
        external
        virtual
        override(
            VirtualIssuanceSupplyBase_v1, IFM_BC_Discrete_Redeeming_VirtualSupply_v1
        )
        onlyOrchestratorAdmin
    {
        _setVirtualIssuanceSupply(virtualSupply_);
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
            newSegments_._calculateReserveForSupply(virtualIssuanceSupply);

        if (newCalculatedReserve != currentVirtualCollateralSupply) {
            revert InvarianceCheckFailed(
                newCalculatedReserve, currentVirtualCollateralSupply
            );
        }

        _setSegments(newSegments_);
    }

    // =========================================================================
    // Internal

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

    /// @dev    Internal function to directly set the virtual collateral supply to a new value.
    /// @param  virtualSupply_ The new value to set for the virtual collateral supply.
    function _setVirtualCollateralSupply(uint virtualSupply_)
        internal
        override(VirtualCollateralSupplyBase_v1)
    {
        super._setVirtualCollateralSupply(virtualSupply_);
    }

    /// @dev    Internal function to directly set the virtual issuance supply to a new value.
    /// @param  virtualSupply_ The new value to set for the virtual issuance supply.
    function _setVirtualIssuanceSupply(uint virtualSupply_)
        internal
        override(VirtualIssuanceSupplyBase_v1)
    {
        super._setVirtualIssuanceSupply(virtualSupply_);
    }

    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        override
        returns (uint)
    {
        (uint collateralToReturn,) = _segments._calculateSaleReturn(
            _depositAmount, virtualIssuanceSupply
        );
        return collateralToReturn;
    }

    function _handleCollateralTokensAfterSell(
        address _receiver,
        uint _collateralTokenAmount
    ) internal virtual override {
        revert("NOT IMPLEMENTED"); // TODO: Implement
    }

    // BondingCurveBase_v1 implementations (inherited via RedeemingBondingCurveBase_v1)
    function _handleCollateralTokensBeforeBuy(address _provider, uint _amount)
        internal
        virtual
        override
    {
        _token.safeTransferFrom(_provider, address(this), _amount);
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
            _depositAmount, virtualIssuanceSupply
        );
        return tokensToMint;
    }
}
