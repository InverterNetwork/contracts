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

    // ========================================================================
    // Storage

    /// @notice Token that is accepted by this funding manager for deposits.
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
        address collateralToken;
        PackedSegment[] memory initialSegments;

        (collateralToken, initialSegments) =
            abi.decode(configData_, (address, PackedSegment[]));

        __Module_init(orchestrator_, metadata_);
        __FM_BC_Discrete_Redeeming_VirtualSupply_v1_Init(
            collateralToken, initialSegments
        );
    }

    /// @notice Initializes the Discrete Redeeming Virtual Supply Contract.
    /// @dev    Only callable during the initialization.
    /// @param  collateralToken_ The token that is accepted as collateral.
    /// @param  initialSegments_ The initial array of packed segments for the curve.
    function __FM_BC_Discrete_Redeeming_VirtualSupply_v1_Init(
        address collateralToken_,
        PackedSegment[] memory initialSegments_
    ) internal onlyInitializing {
        // Set collateral token.
        _token = IERC20(collateralToken_);
        _setSegments(initialSegments_);

        emit OrchestratorTokenSet(
            collateralToken_, IERC20Metadata(address(_token)).decimals()
        );
    }

    // =========================================================================
    // Public - Getters

    // IFundingManager_v1 implementations
    function token()
        external
        view
        override(IFundingManager_v1)
        returns (IERC20)
    {
        return _token;
    }

    /// @inheritdoc IFM_BC_Discrete_Redeeming_VirtualSupply_v1
    function getSegments() external view returns (PackedSegment[] memory) {
        return _segments;
    }

    function getStaticPriceForBuying()
        external
        view
        virtual
        override(BondingCurveBase_v1, IBondingCurveBase_v1)
        returns (uint)
    {
        revert("NOT IMPLEMENTED");
    }

    // =========================================================================
    // Public - Mutating

    function transferOrchestratorToken(address to, uint amount) external {
        revert("NOT IMPLEMENTED");
    }

    // VirtualIssuanceSupplyBase_v1 implementations
    function setVirtualIssuanceSupply(uint _virtualSupply)
        external
        virtual
        override
    {
        revert("NOT IMPLEMENTED");
    }

    // VirtualCollateralSupplyBase_v1 implementations
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        virtual
        override
    {
        revert("NOT IMPLEMENTED");
    }

    // RedeemingBondingCurveBase_v1 implementations
    function getStaticPriceForSelling()
        external
        view
        virtual
        override
        returns (uint)
    {
        revert("NOT IMPLEMENTED");
    }

    // =========================================================================
    // Internal

    /// @notice Sets the segments for the discrete bonding curve.
    /// @dev    Can only be called once during initialization.
    /// @param  newSegments_ The array of packed segments.
    function _setSegments(PackedSegment[] memory newSegments_) internal {
        DiscreteCurveMathLib_v1._validateSegmentArray(newSegments_);
        _segments = newSegments_;
        emit SegmentsSet(newSegments_);
    }

    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        override
        returns (uint)
    {
        revert("NOT IMPLEMENTED");
    }

    function _handleCollateralTokensAfterSell(
        address _receiver,
        uint _collateralTokenAmount
    ) internal virtual override {
        revert("NOT IMPLEMENTED");
    }

    // BondingCurveBase_v1 implementations (inherited via RedeemingBondingCurveBase_v1)
    function _handleCollateralTokensBeforeBuy(address _provider, uint _amount)
        internal
        virtual
        override
    {
        revert("NOT IMPLEMENTED");
    }

    function _handleIssuanceTokensAfterBuy(address _receiver, uint _amount)
        internal
        virtual
        override
    {
        revert("NOT IMPLEMENTED");
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        override
        returns (uint)
    {
        revert("NOT IMPLEMENTED");
    }
}
