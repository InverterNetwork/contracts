// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {
    Initializable,
    IERC20MetadataUpgradeable,
    ERC4626Upgradeable
} from "@oz-up/token/ERC20/extensions/ERC4626Upgradeable.sol";

// External Libraries
import {Strings} from "@oz/utils/Strings.sol";

// Interfaces
import {IFundingVault} from "src/proposal/base/IFundingVault.sol";

/**
 * @title FundingVault
 *
 * @dev The FundingVault is an ERC-4626 vault managing the accounting for
 *      funder deposits.
 *
 *      Upon funding, the depositor receives newly minted ERC20 receipt tokens
 *      that represent their funding.
 *
 *      These receipt tokens can be burned to receive back the funding, in the
 *      appropriate share of funds still available.
 *
 * @author byterocket
 */
abstract contract FundingVault is IFundingVault, ERC4626Upgradeable {
    using Strings for uint;

    function __FundingVault_init(uint id, IERC20MetadataUpgradeable token)
        internal
        onlyInitializing
    {
        __ERC20_init(_tokenName(id), _tokenSymbol(id));
        __ERC4626_init(token);
    }

    function _tokenName(uint id) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Inverter Funding Token - Proposal #", id.toString()
            )
        );
    }

    function _tokenSymbol(uint id) internal pure returns (string memory) {
        return string(abi.encodePacked("IFT-", id.toString()));
    }
}
