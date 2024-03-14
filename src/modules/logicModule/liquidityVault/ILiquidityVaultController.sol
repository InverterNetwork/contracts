// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ILiquidityVault} from "@liquidityVault/ILiquidityVault.sol";
import {IToposBondingCurveFundingManager} from
    "@bondingCurve/IToposBondingCurveFundingManager.sol";
import {IRepayer} from "@bondingCurve/IRepayer.sol";
import {LibLiquidityVaultStructs} from "@lib/LibLiquidityVaultStructs.sol";

interface ILiquidityVaultController {
    //--------------------------------------------------------------------------
    // Errors
    error AddressesListMismatch(address addr);
    error InputNotValid();
    error InsufficientAssets(uint needed);
    error InvalidAddress();
    error NotAuthorized(address caller);
    error NotEnoughFunds();

    //--------------------------------------------------------------------------
    // Events

    event LiquidityVaultAuthorized(address _address);
    event LiquidityVaultRevoked(address _address);
    event FundingManagerChanged(
        IToposBondingCurveFundingManager newFundingManager,
        IToposBondingCurveFundingManager oldFundingManager
    );
    event InsuranceRestored(
        uint insurance, uint mintedTPGs, uint burnedTPGs, uint actualTPGsToAsset
    );
    event InsuranceToleranceChanged(uint16 newValue, uint16 oldValue);
    event RepayersChanged();
    event RiskFactorChanged(uint16 newValue, uint16 oldValue);

    //--------------------------------------------------------------------------
    // Structs

    /// @notice struct of an AllowedLPI of LiquidityPoolInterface with properties to couple array and mapping
    struct AuthorizedLiquidityVault {
        uint listIndex;
        bool authorized;
    }

    //--------------------------------------------------------------------------
    // Functions

    /// @notice it calculates the amount of insurance (asset), given a risk factor and amount of the investments
    /// @return necessaryCollateralForCoverage  the needed insurance
    /// @return additionalCollateralRequired  the needed asset that the Liquidity Pool must have if it has to mint to restore the insurance
    /// @return convertedIssuanceToCollateralBalance the current value of TPGs in asset
    function calculateInsurance()
        external
        view
        returns (
            uint necessaryCollateralForCoverage,
            uint additionalCollateralRequired,
            uint convertedIssuanceToCollateralBalance
        );

    /// @notice Assesses the potential for repaying a specified amount using contributions from a
    /// list of repayers, and calculates any shortfall.
    /// @dev This function merges an internal list of repayers with the provided list of additional
    /// repayers, then computes each repayer's potential contribution towards the total repayment
    /// due. The function finally assesses if the total contributions can meet the repayment due,
    /// and if not, calculates the shortfall.
    /// @param _totalRepaymentDue The total amount due for repayment.
    /// @param _additionalRepayers The list of additional repayers to be considered for repayment
    /// contributions.
    /// @return repaymentDeficit The difference between the total repayment due and the sum of possible
    /// repayments from all considered repayers, indicating any shortfall.
    /// @return repayerContributions A list of tuples detailing each repayer's address alongside
    /// the amount they can contribute towards the repayment.
    function assessRepaymentPotential(
        uint _totalRepaymentDue,
        IRepayer[] calldata _additionalRepayers
    )
        external
        view
        returns (
            uint repaymentDeficit,
            LibLiquidityVaultStructs.AddressAmount[] memory repayerContributions
        );

    /// @notice Processes the repayment of an investment within a designated LiquidityVault
    /// @dev This function ensures that the total repayable amount from all repayers exactly matches
    /// the total repayment due, without allowing for partial or excess repayments. It iterates
    /// through each repayer's contribution, transferring the specified amounts to the investor.
    /// For the contract itself acting as a repayer, it redeems issuance tokens for collateral before
    /// transferring.
    /// @param _to The address of the investor receiving the repayment.
    /// @param _totalRepaymentDue The total amount that needs to be repaid to the investor.
    /// @param _additionalRepayers An array of external repayer addresses that are considered in
    /// addition to any internal repayers, to contribute towards the total repayment due.
    function processRepayment(
        address _to,
        uint _totalRepaymentDue,
        IRepayer[] calldata _additionalRepayers
    ) external;

    // Todo
    function authorizeLiquidityVault(ILiquidityVault _liquidityVault)
        external;

    // Todo
    function revokeLiquidityVault(ILiquidityVault _liquidityVault) external;

    // Todo
    function setFundingManager(
        IToposBondingCurveFundingManager _newFundingManager
    ) external;

    // todo
    function setRepayers(IRepayer[] calldata _repayers) external;

    // todo
    function setInsuranceTolerance(uint16 _newInsuranceTolerance) external;

    // todo
    function setRiskFactor(uint16 _newRiskFactor) external;

    /// @notice This function is used to restore the insurance coverage by either redeeming excess
    /// issuance assets for collateral or purchasing additional issuance assets using available
    /// collateral, depending on the current insurance coverage level.
    /// @dev Function restricted to accounts with the role LIQUIDITY_VAULT_CONTROLLER_MANAGER_ROLE.
    /// It assesses the risk-based collateral requirements and adjusts the insurance coverage
    /// accordingly. The function handles both scenarios: when there is an excess of issuance
    ///assets and when there is a shortage.
    /// @custom:modifier onlyModuleRole Ensures that only accounts with the specified role can
    /// execute this function.
    function restoreInsurance() external;
}
