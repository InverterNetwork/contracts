// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {FixedPointMathLib} from "@lib/FixedPointMathLib.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {SharedStructs} from "@lib/SharedStructs.sol";

// Internal Interfaces
import {IRepayer_v1} from "@lm/interfaces/IRepayer_v1.sol";
import {ILiquidityVaultController} from
    "@lm/interfaces/ILiquidityVaultController.sol";
import {ILiquidityVault} from "@lm/interfaces/ILiquidityVault.sol";
import {IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract LiquidityVaultController is
    ILiquidityVaultController,
    IRepayer_v1,
    Module_v1
{
    using SafeERC20 for IERC20;
    // -----------------CLEAN
    /// @dev Token that is accepted by this liquidity pool deposits.

    IERC20 public collateralAsset;
    IERC20 public issuanceAsset;
    IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1 public fundingManager;

    // ---------- NOT CLEAN
    uint16 internal constant BPS = 10_000;
    uint public repayable;
    uint16 public insuranceTolerance;
    uint16 public riskFactor;
    string public name;

    /// @notice mapping of the allowed Liquity Pool Interfaces: address => AllowedLPI
    mapping(address => AuthorizedLiquidityVault) public authorizedLiquidityVault;
    /// @notice indexing array for the allowed LVI mapping
    address[] public vaultAddresses;
    /// @notice array for the repayment interfaces
    IRepayer_v1[] public repayers;

    // ToDo: Manager has to be set through the authorizer
    bytes32 public constant LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE =
        "LV_CONTROLLER_MANAGER";

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyAuthorizedLiquidityVault() {
        if (authorizedLiquidityVault[msg.sender].authorized != true) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    /* CHANGES MADE
    - Manager address now gets managed through Authorizer
    - Add Init2 to get funding manager address
    - Stored funding manager address to two values to accomodate future splitting, as well asl
        make it more readable and not needing to cast it to different interfaces all the time

    */

    /* TODOs:
    - Replace where the `asset` is used with the collateralAsset
    - Replace where TPG is used with issuanceAsset
    - Rename Funding Manager once we come up with different name
    - Need better name for the role and/or contract name :(
    - Rename errors so the contract name is prepend and in style of other modules
    - Update events to match function names
    - Implement Repayer functionalities for Interface
    - Think about if the Liqudity Vault should be called Pool after all , as it hold both tokens
    - Clean up inline comments for function _assessRiskBasedCollateralRequirements()
    - Add inline comments for restoreInsurance()
    - Check if all functions are in interface
    - Write comments for all functions, state variables, events and errors
    - `

    */

    //--------------------------------------------------------------------------
    // Initialization

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        address _collateralAsset;

        (_collateralAsset) = abi.decode(configData, (address));

        collateralAsset = IERC20(_collateralAsset);
        issuanceAsset = __Module_orchestrator.fundingManager().token();
        fundingManager = IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1(
            address(__Module_orchestrator.fundingManager())
        );
    }

    // function init2(IOrchestrator_v1, bytes memory dependencyData)
    //     external
    //     override(Module_v1)
    //     initializer2
    // {
    //     address _issuanceAsset;
    //     address _fundingManager;

    //     (_issuanceAsset, _fundingManager) =
    //         abi.decode(dependencyData, (address, address));

    //     issuanceAsset = IERC20(_issuanceAsset);
    //     fundingManager = IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1(
    //         _fundingManager
    //     );
    // }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc ILiquidityVaultController
    function calculateInsurance()
        external
        returns (
            uint necessaryCollateralForCoverage,
            uint additionalCollateralRequired,
            uint convertedIssuanceToCollateralBalance
        )
    {
        (
            necessaryCollateralForCoverage,
            additionalCollateralRequired,
            convertedIssuanceToCollateralBalance
        ) = _assessRiskBasedCollateralRequirements();
    }

    /// @inheritdoc ILiquidityVaultController
    function assessRepaymentPotential(
        uint _totalRepaymentDue,
        IRepayer_v1[] calldata _additionalRepayers
    )
        external
        returns (
            uint repaymentDeficit,
            SharedStructs.AddressAmount[] memory repayerContributions
        )
    {
        uint totalRepayableAmount;
        (totalRepayableAmount, repayerContributions) =
            _calculateRepaymentCapacity(_totalRepaymentDue, _additionalRepayers);
        return
            ((_totalRepaymentDue - totalRepayableAmount), repayerContributions);
    }

    /// @inheritdoc IRepayer_v1
    function getRepayableAmount() external returns (uint) {
        return _issuanceToCollateralBalance();
    }

    /// @inheritdoc ILiquidityVaultController
    function processRepayment(
        address _to,
        uint _totalRepaymentDue,
        IRepayer_v1[] calldata _additionalRepayers
    ) external onlyAuthorizedLiquidityVault {
        // Get total repayable amount and Repayers + how much they can contribute
        (
            uint totalRepayableAmount,
            SharedStructs.AddressAmount[] memory repayerContributions
        ) = _calculateRepaymentCapacity(_totalRepaymentDue, _additionalRepayers);
        // Total repayable amount must be equal to total amount due (no partial or over repayment)
        if (totalRepayableAmount != _totalRepaymentDue) revert NotEnoughFunds();
        // Iterate through repayer contributions list and transfer amounts
        for (uint8 _i = 0; _i < repayerContributions.length; _i++) {
            // Skip repayers who can not contribute
            if (repayerContributions[_i].amount == 0) {
                continue;
            }
            // If repayer is address(this) then redeem issuance token for collateral before sending
            // collateral to _to address
            if (address(this) == repayerContributions[_i].addr) {
                _redeemIssuanceAndTransferCollateral(
                    _to, repayerContributions[_i].amount
                );
            } else {
                // Sent calculated amount to _to address
                IRepayer_v1(repayerContributions[_i].addr).transferRepayment(
                    _to, repayerContributions[_i].amount
                );
            }
        }
    }

    //--------------------------------------------------------------------------
    // Only Liquidity Vault Contoller Manager Functions

    /// @inheritdoc ILiquidityVaultController
    function authorizeLiquidityVault(ILiquidityVault _liquidityVault)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        address _address = address(_liquidityVault);
        // Check for address in mapping
        if (!authorizedLiquidityVault[_address].authorized) {
            // Add address to list
            vaultAddresses.push(_address);
            // Add address list index to mapping -> struct
            authorizedLiquidityVault[_address].listIndex =
                vaultAddresses.length - 1;
        }
        // Set address as authorized
        authorizedLiquidityVault[_address].authorized = true;
        // Emit event for indexing
        emit LiquidityVaultAuthorized(_address);
    }

    /// @inheritdoc ILiquidityVaultController
    function revokeLiquidityVault(ILiquidityVault _liquidityVault)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        address _address = address(_liquidityVault);
        // Get index of address in list
        uint _index = authorizedLiquidityVault[_address].listIndex;
        // Revert if it doesn't exist, it hasn't been authorized
        if (vaultAddresses[_index] != _address) {
            revert AddressesListMismatch(_address);
        }
        // Set last address in list to index of address we want to revoke
        vaultAddresses[_index] = vaultAddresses[vaultAddresses.length - 1];
        // Update index of address which has been moved in mapping
        authorizedLiquidityVault[vaultAddresses[_index]].listIndex = _index;
        // Remove last element of list
        vaultAddresses.pop();
        // Delete mapping entry
        delete authorizedLiquidityVault[_address];
        // Emit event for indexing
        emit LiquidityVaultRevoked(_address);
    }

    /// @inheritdoc ILiquidityVaultController
    function setFundingManager(
        IFM_BC_BondingSurface_Redeemable_Repayer_Seizable_v1 _newFundingManager
    ) external onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE) {
        // Emit event for indexing
        emit FundingManagerChanged(_newFundingManager, fundingManager);
        // Set new funding manager
        fundingManager = _newFundingManager;
    }

    /// @inheritdoc ILiquidityVaultController
    function setRepayers(IRepayer_v1[] calldata _repayers)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        // Get length of _repayer list
        uint _length = _repayers.length;
        // Revert if length > 127
        if (_length > 0x7F) revert InputNotValid();
        // Delete repayers list
        delete repayers;
        // Set parameter as new repayers list
        for (uint8 _i = 0; _i < _length; _i++) {
            repayers.push(_repayers[_i]);
        }
        // Emit event for indexing
        emit RepayersChanged();
    }

    /// @inheritdoc ILiquidityVaultController
    function setInsuranceTolerance(uint16 _newInsuranceTolerance)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        // Revert if new insurance tolerance > BPS (10_000)
        if (_newInsuranceTolerance > BPS) revert InputNotValid();
        // Emit event for indexing
        emit InsuranceToleranceChanged(
            _newInsuranceTolerance, insuranceTolerance
        );
        // Set new insurance tolerance
        insuranceTolerance = _newInsuranceTolerance;
    }

    /// @inheritdoc ILiquidityVaultController
    function setRiskFactor(uint16 _newRiskFactor)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        // Revert if new risk factor > BPS (10_000)
        if (_newRiskFactor > BPS) revert InputNotValid();
        // Emit event for indexing
        emit RiskFactorChanged(_newRiskFactor, riskFactor);
        // Set new risk factor
        riskFactor = _newRiskFactor;
    }

    /// @inheritdoc IRepayer_v1
    function setRepayableAmount(uint _amount)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {}

    // TODO: Decide if this might be a better name for this function, more descriptive: settleRepaymentWithCollateral

    /// @inheritdoc IRepayer_v1
    function transferRepayment(address _to, uint _amount)
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        _redeemIssuanceAndTransferCollateral(_to, _amount);
    }

    /// @inheritdoc ILiquidityVaultController
    function restoreInsurance()
        external
        onlyModuleRole(LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE)
    {
        uint amountIssuanceAssetMinted;
        uint amountCollateralAssetRedeemed;
        uint coverageSurplusPercent;
        // Asses insurance level
        (
            uint necessaryCollateralForCoverage,
            uint additionalCollateralRequired,
            uint convertedIssuanceToCollateralBalance
        ) = _assessRiskBasedCollateralRequirements();
        // If enough issuance asset is available in the contract, then sell it for collateral to
        // restore insurance
        if (
            convertedIssuanceToCollateralBalance
                > necessaryCollateralForCoverage
        ) {
            // Calculate the excess amount of coverage
            uint excessCoverageAmount = convertedIssuanceToCollateralBalance
                - necessaryCollateralForCoverage;
            // TODO: return when exessCoverageAmount == 0
            // Get issuance asset balance
            uint issuanceAssetBalance = issuanceAsset.balanceOf(address(this));
            // Calculate what percentage the excess coverage amount is of
            // total (issuance converted) collateral available in contract
            coverageSurplusPercent = FixedPointMathLib.fdiv(
                excessCoverageAmount, convertedIssuanceToCollateralBalance, BPS
            );
            //
            if (coverageSurplusPercent >= insuranceTolerance) {
                amountCollateralAssetRedeemed = FixedPointMathLib.fmul(
                    issuanceAssetBalance,
                    coverageSurplusPercent - insuranceTolerance,
                    BPS
                );
                // Approve and sell/redeem issuance token for collateral
                issuanceAsset.approve(
                    address(fundingManager), amountCollateralAssetRedeemed
                );
                IRedeemingBondingCurveBase_v1(address(fundingManager)).sell(
                    amountCollateralAssetRedeemed, 0
                );
            }
            // If not enough issuance asset in contract to convert to collateral then buy issuance asset
            // to restore insurance
        } else if (
            convertedIssuanceToCollateralBalance
                < necessaryCollateralForCoverage
        ) {
            // If not enough collateral is in contract, revert
            if (
                collateralAsset.balanceOf(address(this))
                    < additionalCollateralRequired
            ) {
                revert InsufficientAssets(additionalCollateralRequired);
            }
            // Expected amount of issuance asset needed to cover collateral required to restore
            // insurance
            amountIssuanceAssetMinted = IBondingCurveBase_v1(
                address(fundingManager)
            ).calculatePurchaseReturn(additionalCollateralRequired);
            // Approve and buy issuance asset with collateral
            collateralAsset.approve(
                address(fundingManager), additionalCollateralRequired
            );
            IBondingCurveBase_v1(address(fundingManager)).buy(
                additionalCollateralRequired, 0
            );
        }
        // Emit event:
        // - Collateral amount needed to restore coverage
        // - Issuance asset minted. If greater than 0 then collateral asset was used to restore
        //      coverage
        // - Collateral asset redeemed. If greater than 0 then issuance asset was used to restore
        //      coverage
        // - Value of issuance asset to collateral conversion
        emit InsuranceRestored(
            necessaryCollateralForCoverage,
            amountIssuanceAssetMinted,
            amountCollateralAssetRedeemed,
            _issuanceToCollateralBalance()
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice it calculates the amount of collateral asset needed for insurance, given the risk
    ///     factor and amount of the active investments
    /// @return necessaryCollateralForCoverage  The necessary collateral for insurance coverage.
    /// @return additionalCollateralRequired The additional collateral asset needed by the Liquidity
    ///     Vault Controller to restore insurance coverage.
    /// @return convertedIssuanceToCollateralBalance The current value of issuance asset converted
    ///     to collateral asset
    function _assessRiskBasedCollateralRequirements()
        internal
        returns (
            uint necessaryCollateralForCoverage,
            uint additionalCollateralRequired,
            uint convertedIssuanceToCollateralBalance
        )
    {
        // Calculate collateral equivalent of issuance asset balance
        convertedIssuanceToCollateralBalance = _issuanceToCollateralBalance();
        // If risk factor is not set, no insurance is needed
        if (riskFactor == 0) {
            return (0, 0, convertedIssuanceToCollateralBalance);
        }
        uint totalActiveInvestments;
        // Loop through Liquidity Vaults to get the amount of active investments
        for (uint8 _i = 0; _i < vaultAddresses.length; _i++) {
            address _address = vaultAddresses[_i];
            // Skip the non authorized ones
            if (authorizedLiquidityVault[_address].authorized == false) {
                continue;
            }
            ILiquidityVault _liquidityVault = ILiquidityVault(_address);
            // Calculate total amount which is still due for payment by borrowers, and so active,
            // and add to totalActiveInvestments
            totalActiveInvestments += _liquidityVault.totalToBePaidValue()
                - _liquidityVault.totalRepaidValue();
        }
        // If there are no investments there is no need for insurance
        if (totalActiveInvestments == 0) {
            return (0, 0, convertedIssuanceToCollateralBalance);
        }
        // Calculate the insurance as a percentage of the investment by the risk factor
        necessaryCollateralForCoverage =
            FixedPointMathLib.fmul(riskFactor, totalActiveInvestments, BPS);
        // Check if contract has enough collateral if issuance token would be converted
        if (
            necessaryCollateralForCoverage
                > convertedIssuanceToCollateralBalance
        ) {
            // Calculate the amount of collateral asset needed to meet insurance and risk factor
            additionalCollateralRequired = necessaryCollateralForCoverage
                - convertedIssuanceToCollateralBalance;
            // Calculcate amount of issuance asset needed, which when converted to collateral will
            // equal additionalCollateralRequired
            uint issuanceAssetForCollateral = IBondingCurveBase_v1(
                address(fundingManager)
            ).calculatePurchaseReturn(additionalCollateralRequired);
            // Adjust additionalCollateralRequired to cover the sale fee, including a buffer for
            // rounding precision
            additionalCollateralRequired += _adjustCollateralForSaleFeeCost(
                issuanceAssetForCollateral, additionalCollateralRequired
            );
        }
    }

    /// @dev Merges an additional list of repayers with the contract's existing list and calculates
    ///     the total repayable amount from all repayers, up to a specified due amount.
    /// @param _totalRepaymentDue The total amount due that needs to be repaid.
    /// @param _additionalRepayers List of additional repayer addresses to be considered for repayment
    ///     calculations.
    /// @return totalRepayableAmount Total amount repayable by the combined list repayers, capped
    ///     at the `totalRepaymentDue`.
    /// @return repayerContributions List of tuples containing the addresses of repayers and the
    ///     amounts they can contribute towards the total repayment.
    function _calculateRepaymentCapacity(
        uint _totalRepaymentDue,
        IRepayer_v1[] calldata _additionalRepayers
    )
        internal
        returns (
            uint totalRepayableAmount,
            SharedStructs.AddressAmount[] memory repayerContributions
        )
    {
        // Merge repayer list from state with repayer list from function parameters
        IRepayer_v1[] memory _repayers =
            new IRepayer_v1[](repayers.length + _additionalRepayers.length);
        uint8 i = 0;
        while (i < _additionalRepayers.length) {
            _repayers[i] = _additionalRepayers[i];
            i++;
        }
        uint8 j = 0;
        while (j < repayers.length) {
            _repayers[i] = repayers[j];
            i++;
            j++;
        }

        // Loop through repayer list and add repayable amounts to total until the amount due is fullfilled
        SharedStructs.AddressAmount[] memory _repayerContributions =
            new SharedStructs.AddressAmount[](_repayers.length);
        // Loop through the merged list of repayers
        for (uint8 k = 0; k < _repayers.length; k++) {
            // Get repayable amount. If the repayer is address(this) then calculate
            // repayable amount by means of converting issuance token
            uint _repayableAmount = address(this) == address(_repayers[k])
                ? _issuanceToCollateralBalance()
                : _repayers[k].getRepayableAmount();
            // If total repayment due is meet, we add exact needed amount and exit
            if ((_repayableAmount + totalRepayableAmount) >= _totalRepaymentDue)
            {
                // Calculate amount left to reach totalRepaymentDue
                uint _diff = _totalRepaymentDue - totalRepayableAmount;
                // Add new AddressAmount struct to list, storing repayer address and amount needed to
                // reach totalRepaymentDue
                _repayerContributions[k] =
                    SharedStructs.AddressAmount(address(_repayers[k]), _diff);
                // Add amount needed to reach totalRepaymentDue to subtotal
                totalRepayableAmount += _diff;
                // Break out loop
                break;
            } else {
                // Add new AddressAmount struct to list, storing repayer address and repayable amount
                _repayerContributions[k] = SharedStructs.AddressAmount(
                    address(_repayers[k]), _repayableAmount
                );
                // Add repayable amount to subtotal of repayable amounts
                totalRepayableAmount += _repayableAmount;
            }
        }
        // Assign list with AddressAmount structs to return valule
        repayerContributions = _repayerContributions;
    }

    /// @dev Converts the contract's issuance asset balance to an equivalent collateral amount using the bonding curve.
    /// @return uint The equivalent collateral amount for the current issuance asset balance.
    function _issuanceToCollateralBalance() internal returns (uint) {
        // Get issuance asset balance
        uint _issuanceAssetBalance = issuanceAsset.balanceOf(address(this));
        // Calculate and return the equivalent collateral amount using the bonding curve.
        return IRedeemingBondingCurveBase_v1(address(fundingManager))
            .calculateSaleReturn(_issuanceAssetBalance);
    }

    /// @dev Burns issuance assets and transfers an equivalent amount of collateral to a specified address.
    /// Reverts on insufficient collateral.
    /// @param _to The recipient address of the collateral.
    /// @param _collateralAmount The amount of collateral to transfer.
    function _redeemIssuanceAndTransferCollateral(
        address _to,
        uint _collateralAmount
    ) internal {
        // Calculate collateral equivalent of issuance asset balance
        uint convertedIssuanceToCollateralBalance =
            _issuanceToCollateralBalance();
        // Ensure requested collateral amount does not exceed available balance
        if (_collateralAmount > convertedIssuanceToCollateralBalance) {
            revert NotEnoughFunds();
        }
        // Retrieve contract's issuance asset balance
        uint _issuanceAssetBalance = issuanceAsset.balanceOf(address(this));
        // Approve transfer of issuance assets to funding manager for burning
        issuanceAsset.approve(address(fundingManager), _issuanceAssetBalance);
        // Burn the issuance asset balance, converting it to collateral
        IRedeemingBondingCurveBase_v1(address(fundingManager)).sell(
            _issuanceAssetBalance, 0
        );
        // Transfer the specified amount of collateral to the recipient address
        collateralAsset.safeTransfer(_to, _collateralAmount);
    }

    /// @dev Calculates additional collateral needed to cover sale fee for minting issuance assets, including a precision buffer.
    /// @param _issuanceAssetAmount Amount of issuance asset for which collateral is being adjusted.
    /// @param _collateralAssetRequired Initial additional collateral required before sale fee adjustment.
    /// @return The total additional collateral required, accounting for the sale fee and precision buffer.
    function _adjustCollateralForSaleFeeCost(
        uint _issuanceAssetAmount,
        uint _collateralAssetRequired
    ) internal returns (uint) {
        // Calculate the sale fee percentage for the issuance asset amount.
        uint saleFeePercentage = FixedPointMathLib.fdiv(
            IRedeemingBondingCurveBase_v1(address(fundingManager))
                .calculateSaleReturn(_issuanceAssetAmount),
            _issuanceAssetAmount,
            FixedPointMathLib.WAD
        );
        // Calculate the sale fee in terms of collateral required.
        uint saleFee = FixedPointMathLib.fmul(
            _collateralAssetRequired, saleFeePercentage, FixedPointMathLib.WAD
        );
        // Calculate a buffer for rounding precision in fee calculation.
        uint _buffer = FixedPointMathLib.fmul(
            saleFee, saleFeePercentage, FixedPointMathLib.WAD
        );
        // Sum the sale fee and buffer to determine total additional collateral required.
        return saleFee + (_buffer * 2);
    }
}
