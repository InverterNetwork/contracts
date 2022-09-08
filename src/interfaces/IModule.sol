// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IModule {
    function pause() external;
    function unpause() external;

    // @todo mp: Extend IModule Interface.
    // function identifier() external;
    // function version() external;
}
