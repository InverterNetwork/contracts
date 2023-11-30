// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {ERC2771ContextUpgradeable} from
    "@oz-up/metatx/ERC2771ContextUpgradeable.sol";

abstract contract TransactionSupport is ERC2771ContextUpgradeable {
    constructor(address _trustedForwarder)
        ERC2771ContextUpgradeable(_trustedForwarder)
    {}

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        return super._msgSender();
    }
}
