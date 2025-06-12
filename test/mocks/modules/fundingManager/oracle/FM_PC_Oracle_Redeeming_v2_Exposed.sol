// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {FM_PC_Oracle_Redeeming_v2} from
    "src/modules/fundingManager/oracle/FM_PC_Oracle_Redeeming_v2.sol";

contract FM_PC_Oracle_Redeeming_v2_Exposed is FM_PC_Oracle_Redeeming_v2 {
    function exposed_setProjectTreasury(address projectTreasury_) public {
        _setProjectTreasury(projectTreasury_);
    }

    function exposed_deductFromOpenRedemptionAmount(uint amount_) public {
        _deductFromOpenRedemptionAmount(amount_);
    }

    function exposed_addToOpenRedemptionAmount(uint amount_) public {
        _addToOpenRedemptionAmount(amount_);
    }

    function exposed_setOracleAddress(address oracle_) public {
        _setOracleAddress(oracle_);
    }

    function exposed_setIssuanceToken(address issuanceToken_) public {
        _setIssuanceToken(issuanceToken_);
    }

    function exposed_handleIssuanceTokensAfterBuy(
        address recipient_,
        uint amount_
    ) public {
        _handleIssuanceTokensAfterBuy(recipient_, amount_);
    }

    function exposed_processCollateralTokensForBuyOperation(uint amount_)
        public
    {
        _processCollateralTokensForBuyOperation(amount_);
    }

    function exposed_setIsDirectOperationsOnly(bool isDirectional_) public {
        _setIsDirectOperationsOnly(isDirectional_);
    }

    function exposed_setMaxProjectBuyFee(uint fee_) public {
        _setMaxProjectBuyFee(fee_);
    }

    function exposed_setMaxProjectSellFee(uint fee_) public {
        _setMaxProjectSellFee(fee_);
    }

    function exposed_setBuyFee(uint fee_) public {
        _setBuyFee(fee_);
    }

    function exposed_setSellFee(uint fee_) public {
        _setSellFee(fee_);
    }

    function exposed_redeemTokensFormulaWrapper(uint amount_)
        public
        view
        returns (uint)
    {
        return _redeemTokensFormulaWrapper(amount_);
    }

    function exposed_issueTokensFormulaWrapper(uint amount_)
        public
        view
        returns (uint)
    {
        return _issueTokensFormulaWrapper(amount_);
    }

    function exposed_projectFeeCollected(uint amount_) public {
        _projectFeeCollected(amount_);
    }

    function exposed_createAndEmitOrder(
        address receiver_,
        uint depositAmount_,
        uint collateralRedeemAmount_,
        uint projectSellFeeAmount_,
        uint protocolSellFeeAmount_
    ) public {
        _createAndEmitOrder(
            receiver_,
            depositAmount_,
            collateralRedeemAmount_,
            projectSellFeeAmount_,
            protocolSellFeeAmount_
        );
    }

    function exposed_getFunctionFeesAndTreasuryAddresses(
        bytes4 functionSelector_
    )
        public
        view
        returns (
            address collateralTreasury_,
            address issuanceTreasury_,
            uint collateralFeePercentage_,
            uint issuanceFeePercentage_
        )
    {
        return _getFunctionFeesAndTreasuryAddresses(functionSelector_);
    }

    function exposed_sellOrder(
        address receiver_,
        uint sellAmount_,
        uint minAmountOut_
    )
        public
        returns (
            uint totalCollateralTokenMovedOut,
            uint projectCollateralFeeAmount
        )
    {
        return _sellOrder(receiver_, sellAmount_, minAmountOut_);
    }

    function exposed_ensureTokenBalance(address token_) public {
        _ensureTokenBalance(token_);
    }

    function exposed_handleCollateralTokensAfterSell(
        address recipient_,
        uint amount_
    ) public {
        _handleCollateralTokensAfterSell(recipient_, amount_);
    }
}
