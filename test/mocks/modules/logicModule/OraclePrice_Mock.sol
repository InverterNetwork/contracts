// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import "@lm/interfaces/IOraclePrice_v1.sol";
import "src/modules/base/Module_v1.sol";

contract OraclePrice_Mock is IOraclePrice_v1, Module_v1 {
    uint private _priceForIssuance;
    uint private _priceForRedemption;

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IOraclePrice_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /* configData */
    ) public override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        _priceForIssuance = 1e6; // Default price 1:1
        _priceForRedemption = 1e6; // Default price 1:1
    }

    function setIssuancePrice(uint price_) external {
        if (price_ == 0) revert OraclePrice__ZeroPrice();
        _priceForIssuance = price_;
    }

    function setRedemptionPrice(uint price_) external {
        if (price_ == 0) revert OraclePrice__ZeroPrice();
        _priceForRedemption = price_;
    }

    function getPriceForIssuance() external view returns (uint) {
        return _priceForIssuance;
    }

    function getPriceForRedemption() external view returns (uint) {
        return _priceForRedemption;
    }
}
