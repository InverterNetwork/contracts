// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Clones} from "@oz/proxy/Clones.sol";

import {IModule_v1} from "src/modules/base/IModule_v1.sol";

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

import {OrchestratorV1Mock} from
    "test/utils/mocks/orchestrator/OrchestratorV1Mock.sol";

import {ElasticReceiptTokenBaseV1Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ElasticReceiptTokenBaseV1Mock.sol";

import {ERC20Mock} from
    "test/modules/fundingManager/rebasing/utils/mocks/ERC20Mock.sol";

/**
 * @dev Root contract for ElasticReceiptTokenBase_v1 Test Contracts.
 *
 *      Provides the setUp function, access to common test utils and internal
 *      constants from the ElasticReceiptTokenBase_v1.
 */
abstract contract ElasticReceiptTokenBaseV1Test is Test {
    // SuT
    ElasticReceiptTokenBaseV1Mock ert;

    // Mocks
    OrchestratorV1Mock _erb_orchestrator;
    ERC20Mock underlier;
    TransactionForwarder_v1 _forwarder;

    // Constants
    string internal constant NAME = "elastic receipt Token";
    string internal constant SYMBOL = "ERT";
    uint internal constant DECIMALS = 9;

    // Constants copied from SuT.
    uint internal constant MAX_UINT = type(uint).max;
    uint internal constant MAX_SUPPLY = 1_000_000_000_000_000_000e18;
    uint internal constant TOTAL_BITS = MAX_UINT - (MAX_UINT % MAX_SUPPLY);
    uint internal constant BITS_PER_UNDERLYING = TOTAL_BITS / MAX_SUPPLY;

    // Module Constants
    uint constant ERB_MAJOR_VERSION = 1;
    uint constant ERB_MINOR_VERSION = 0;
    uint constant ERB_PATCH_VERSION = 0;
    string constant ERB_URL =
        "https://github.com/organization/module/ElasticReceiptTokenBase";
    string constant ERB_TITLE = "Module";

    IModule_v1.Metadata _ERB_METADATA = IModule_v1.Metadata(
        ERB_MAJOR_VERSION,
        ERB_MINOR_VERSION,
        ERB_PATCH_VERSION,
        ERB_URL,
        ERB_TITLE
    );

    bytes _erb_configData;

    function setUp() public {
        underlier = new ERC20Mock("Test ERC20", "TEST");
        _forwarder = new TransactionForwarder_v1();

        address impl = address(new OrchestratorV1Mock(address(_forwarder)));
        _erb_orchestrator = OrchestratorV1Mock(Clones.clone(impl));

        impl = address(new ElasticReceiptTokenBaseV1Mock());
        ert = ElasticReceiptTokenBaseV1Mock(Clones.clone(impl));

        _erb_configData = abi.encode(NAME, SYMBOL, uint8(DECIMALS));
        ert.init(_erb_orchestrator, _ERB_METADATA, _erb_configData);
        ert.setUnderlier(address(underlier));
    }

    modifier assumeTestAmount(uint amount) {
        vm.assume(amount != 0 && amount <= MAX_SUPPLY);
        _;
    }

    modifier assumeTestAddress(address who) {
        vm.assume(who != address(0));
        vm.assume(who != address(ert));
        _;
    }

    function mintToUser(address user, uint erts) public {
        underlier.mint(user, erts);

        vm.startPrank(user);
        {
            underlier.approve(address(ert), type(uint).max);
            ert.mint(erts);
        }
        vm.stopPrank();
    }

    function underflows(uint a, uint b) public pure returns (bool) {
        unchecked {
            uint x = a - b;
            return x > a;
        }
    }
}
