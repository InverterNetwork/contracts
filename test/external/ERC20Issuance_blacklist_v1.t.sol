// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Internal
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Tests and Mocks
import {Test} from "forge-std/Test.sol";
import {ERC20Issuance_Blacklist_v1_Exposed} from
    "test/external/ERC20Issuance_blacklist_v1_exposed.sol";

// System under testing
import {
    ERC20Issuance_Blacklist_v1,
    IERC20Issuance_Blacklist_v1
} from "@ex/token/ERC20Issuance_Blacklist_v1.sol";

/**
 * @title   ERC20Issuance_Blacklist_v1_Test
 * @dev     Test contract for ERC20Issuance_Blacklist_v1
 * @author  Zealynx Security
 */
contract ERC20Issuance_Blacklist_v1_Test is Test {
    // ================================================================================
    // Constants
    uint constant BATCH_LIMIT = 200;
    uint constant MAX_SUPPLY = type(uint).max - 1;
    uint8 constant DECIMALS = 18;
    string constant NAME = "Exposed Blacklist Token";
    string constant SYMBOL = "EBLT";

    // ================================================================================
    // State
    ERC20Issuance_Blacklist_v1_Exposed token;

    // ================================================================================
    // Setup
    function setUp() public {
        // Setup token
        token = new ERC20Issuance_Blacklist_v1_Exposed(
            NAME, SYMBOL, DECIMALS, MAX_SUPPLY, address(this), address(this)
        );
    }

    // ================================================================================
    // Test Init
    function testInit() public {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.cap(), MAX_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.owner(), address(this));
        assertEq(token.allowedMinters(address(this)), true);
        assertEq(token.isBlacklistManager(address(this)), true);
    }

    // ================================================================================
    // Test External (public + external)

    // --------------------------------------------------------------------------------
    // Feature: Authorization for Blacklist Modification
    // Scenario: Verifying caller authorization for modifying the blacklist

    /* Test: Function isBlacklisted()
        ├── Given the address is blacklisted
        │   └── When the function isBlacklisted() is called
        │       └── Then the function returns true
        └── Given the address is not blacklisted
            └── When the function isBlacklisted() is called
                └── Then the function returns false
    */
    function testIsBlacklisted_worksGivenAddressIsBlacklisted(
        address toBeBlacklisted_
    ) public {
        vm.assume(toBeBlacklisted_ != address(0));
        // setup
        _blacklistAddress(toBeBlacklisted_);

        // assertion
        assertTrue(
            token.isBlacklisted(toBeBlacklisted_),
            "Address should be blacklisted"
        );
    }

    function testIsBlacklisted_worksGivenAddressIsNotBlacklisted() public {
        // setup
        address notBlacklisted = makeAddr("notBlacklisted");

        // assertion
        assertFalse(
            token.isBlacklisted(notBlacklisted),
            "Address should not be blacklisted"
        );
    }

    /*  Test: Function isBlacklistManager()
        ├── Given the caller is the blacklist manager
        │   └── When the function isBlacklistManager() is called
        │       └── Then the function should return true
        └── Given the caller is not the blacklist manager
            └── When the function isBlacklistManager() is called
                └── Then the function should return false
    */
    function testIsBlacklistManager_worksGivenAddressIsBlacklistManager(
        address _toBeBlacklistManager
    ) public {
        vm.assume(_toBeBlacklistManager != address(0));
        // setup
        token.setBlacklistManager(_toBeBlacklistManager, true);

        // test
        assertTrue(
            token.isBlacklistManager(_toBeBlacklistManager),
            "Address should be blacklist manager"
        );
    }

    function testIsBlacklistManager_worksGivenAddressIsNotBlacklistManager()
        public
    {
        // setup
        address notBlacklistManager = makeAddr("notBlacklistManager");

        // Assertion
        assertFalse(
            token.isBlacklistManager(notBlacklistManager),
            "Address should not be blacklist manager"
        );
    }

    // --------------------------------------------------------------------------------
    // Feature: Individual Blacklist Address
    // Scenario: Handling addition or removal of an address from the blacklist

    /*  Test: Function addToBlacklist()
        ├── Given the caller is not the blacklist manager
        │   └── When the function addToBlacklist() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller is a blacklist manager
            ├── And the address to blacklist is the zero address
            │   └── When the function addToBlacklist() is called
            │       └── Then the function should revert
            └── And the address to blacklist is not the zero address
                ├── And the address is not blacklisted
                │   └── When the function addToBlacklist() is called
                │       └── Then it should emit an event
                │           └── And it should add the address to the blacklist
                └── And the address is blacklisted
                    └── When the function addToBlacklist() is called
                        └── Then no event should be emitted
                            └── And the address should remain blacklisted (idempotent)

    */
    function testAddToBlacklist_worksGivenModifierInPlace(address unauthorized_)
        public
    {
        // setup
        vm.assume(unauthorized_ != address(0));
        vm.assume(unauthorized_ != address(this));

        // test modifier in place
        vm.prank(unauthorized_);
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_NotBlacklistManager
                .selector
        );
        token.addToBlacklist(unauthorized_);
    }

    function testAddToBlacklist_revertGivenAddressIsZeroAddress() public {
        // setup
        address zeroAddress = address(0);

        // test
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_ZeroAddress
                .selector
        );
        token.addToBlacklist(zeroAddress);
    }

    function testAddToBlacklist_worksGivenAddressIsNotBlacklisted(address user_)
        public
    {
        // setup
        vm.assume(user_ != address(0));

        // test
        vm.expectEmit(true, true, false, false);
        emit IERC20Issuance_Blacklist_v1.AddedToBlacklist(user_, address(this));
        token.addToBlacklist(user_);

        // assertion
        assertTrue(token.isBlacklisted(user_), "User should be blacklisted");
    }

    function testAddToBlacklist_revertGivenAddressAlreadyBlacklisted(
        address user_
    ) public {
        // setup
        vm.assume(user_ != address(0));
        // record logs
        _blacklistAddress(user_);
        // start recording logs
        vm.recordLogs();
        // assertion for pre condition
        assertTrue(token.isBlacklisted(user_), "User should be blacklisted");

        // test
        token.addToBlacklist(user_);

        // assertion
        assertTrue(token.isBlacklisted(user_), "User should be blacklisted");
        assertEq(vm.getRecordedLogs().length, 0, "There should be 0 log entry");
    }

    /*  Test: Function removeFromBlacklist()
        ├── Given the caller is not the blacklist manager
        │   └── When the function removeFromBlacklist() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller is a blacklist manager
            ├── And the address is blacklisted
            │   └── When the function removeFromBlacklist() is called
            │       └── Then it should emit an event
            │           └── And it should remove the address from the blacklist
            └── And the address is not blacklisted
                └── When the function removeFromBlacklist() is called
                    └── Then no event should be emitted
                        └── And the address should remain non-blacklisted (idempotent)
    */

    function testRemoveFromBlacklist_worksGivenModifierInPlace(
        address unauthorized_
    ) public {
        // setup
        vm.assume(unauthorized_ != address(this));

        // test modifier in place
        vm.prank(unauthorized_);
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_NotBlacklistManager
                .selector
        );
        token.removeFromBlacklist(unauthorized_);
    }

    function testRemoveFromBlacklist_worksGivenAddressIsBlacklisted(
        address user_
    ) public {
        // Setup
        vm.assume(user_ != address(0));
        token.addToBlacklist(user_);

        // Test
        vm.expectEmit(true, true, false, false);
        emit IERC20Issuance_Blacklist_v1.RemovedFromBlacklist(
            user_, address(this)
        );
        token.removeFromBlacklist(user_);

        // Assertion
        assertFalse(
            token.isBlacklisted(user_), "User should not be blacklisted"
        );
    }

    function testRemoveFromBlacklist_worksGivenAddressIsNotBlacklisted(
        address user_
    ) public {
        // setup
        vm.assume(user_ != address(0));
        // start recording logs
        vm.recordLogs();
        // assertion for pre condition
        assertFalse(
            token.isBlacklisted(user_), "User should not be blacklisted"
        );

        // test
        token.removeFromBlacklist(user_);

        // assertion
        assertFalse(
            token.isBlacklisted(user_), "User should not be blacklisted"
        );
        assertEq(vm.getRecordedLogs().length, 0, "There should be 0 log entry");
    }

    // --------------------------------------------------------------------------------
    // Feature: Batch Blacklist Address Management
    // Scenario: Handling batch addition or removal of addresses from the blacklist

    /*  Test: Function addToBlacklistBatched()
        ├── Given the caller is not the blacklist manager
        │   └── When the function addToBlacklistBatched() is called
        │       └── Then the function should revert (Modifier in place test)
        ├── Given number of addresses is greater than BATCH_LIMIT
        │   └── When addToBlacklistBatched() is called
        │       └── Then it should revert
        └── Given number of addresses is less than or equal to BATCH_LIMIT
        ├── And all addresses are not blacklisted
        │   └── When addToBlacklistBatched() is called
        │       └── Then it should emit an event for each address
        │           └── And it should add each address to the blacklist
        └── And the list contains not blacklisted and blacklisted addresses
            └── Then it should add the addresses that are not blacklisted
                └── And it should skip the addresses that are already blacklisted (idempotent)
    */

    function testAddToBlacklistBatched_worksGivenModifierInPlace(
        address unauthorized_
    ) public {
        // setup
        vm.assume(unauthorized_ != address(this));
        address[] memory addresses = _generateAddresses(BATCH_LIMIT);

        // test modifier in place
        vm.prank(unauthorized_);
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_NotBlacklistManager
                .selector
        );
        token.addToBlacklistBatched(addresses);
    }

    function testAddToBlacklistBatched_revertGivenBatchSizeExceedsLimit()
        public
    {
        // Setup
        address[] memory addresses = _generateAddresses(BATCH_LIMIT + 1);

        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BatchLimitExceeded
                    .selector,
                BATCH_LIMIT + 1,
                BATCH_LIMIT
            )
        );
        token.addToBlacklistBatched(addresses);
    }

    function testAddToBlacklistBatched_worksGivenAllAddressesAreNotBlacklisted(
        uint numberOfAddresses_
    ) public {
        // Setup
        numberOfAddresses_ = bound(numberOfAddresses_, 2, BATCH_LIMIT);
        address[] memory addresses = _generateAddresses(numberOfAddresses_);

        // test
        token.addToBlacklistBatched(addresses);

        // assertion
        for (uint i; i < addresses.length; ++i) {
            assertTrue(
                token.isBlacklisted(addresses[i]),
                "Address should be blacklisted"
            );
        }
    }

    function testAddToBlacklistBatched_worksGivenSomeAddressesAlreadyBlacklisted(
        uint numberOfAddresses_
    ) public {
        // Setup
        numberOfAddresses_ = bound(numberOfAddresses_, 2, BATCH_LIMIT);
        address[] memory addresses = _generateAddresses(numberOfAddresses_);
        // Get number of addresses to blacklist, given no address is blacklisted yet
        uint numberOfBlacklistedAddresses = numberOfAddresses_ / 2;
        // Blacklist subset of addresses
        addresses =
            _blacklistNumberOfAddresses(numberOfBlacklistedAddresses, addresses);
        // Assert pre condition
        for (uint i; i < numberOfBlacklistedAddresses; ++i) {
            assertTrue(
                token.isBlacklisted(addresses[i]),
                "Address should be blacklisted"
            );
        }

        // Test
        token.addToBlacklistBatched(addresses);

        // assertion
        for (uint i; i < addresses.length; ++i) {
            assertTrue(
                token.isBlacklisted(addresses[i]),
                "Address should be blacklisted"
            );
        }
    }

    /*  Test: Function removeFromBlacklistBatched()
        ├── Given the caller is not the blacklist manager
        │   └── When the function removeFromBlacklistBatched() is called
        │       └── Then the function should revert (Modifier in place test)
        ├── Given number of addresses is greater than BATCH_LIMIT
        │   └── When removeFromBlacklistBatched() is called
        │       └── Then it should revert
        └── Given number of addresses is less than or equal to BATCH_LIMIT
        ├── And all addresses are blacklisted
        │   └── When removeFromBlacklistBatched() is called
        │       └── Then it should emit an event for each address
        │           └── And it should remove each address from the blacklist
        └── And the list contains not blacklisted and blacklisted addresses
            ├── Then it should remove the addresses that are blacklisted
                └── And it should skip the addresses that are already non-blacklisted (idempotent)
    */
    function testRemoveFromBlacklistBatched_worksGivenModifierInPlace(
        address unauthorized_
    ) public {
        // setup
        vm.assume(unauthorized_ != address(this));
        address[] memory addresses = _generateAddresses(BATCH_LIMIT);

        // test modifier in place
        vm.prank(unauthorized_);
        vm.expectRevert(
            IERC20Issuance_Blacklist_v1
                .ERC20Issuance_Blacklist_NotBlacklistManager
                .selector
        );
        token.removeFromBlacklistBatched(addresses);
    }

    function testRemoveFromBlacklistBatched_revertGivenBatchSizeExceedsLimit()
        public
    {
        // Setup
        address[] memory addresses = _generateAddresses(BATCH_LIMIT + 1);

        // Test
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BatchLimitExceeded
                    .selector,
                BATCH_LIMIT + 1,
                BATCH_LIMIT
            )
        );
        token.removeFromBlacklistBatched(addresses);
    }

    function testRemoveFromBlacklistBatched_worksGivenAllAddressesAreBlacklisted(
        uint numberOfAddresses_
    ) public {
        // Setup
        numberOfAddresses_ = bound(numberOfAddresses_, 2, BATCH_LIMIT);
        address[] memory addresses = _generateAddresses(numberOfAddresses_);
        token.addToBlacklistBatched(addresses);
        // Assert pre condition
        for (uint i; i < addresses.length; ++i) {
            assertTrue(
                token.isBlacklisted(addresses[i]),
                "Address should be blacklisted"
            );
        }
        // test
        token.removeFromBlacklistBatched(addresses);

        // assertion
        for (uint i; i < addresses.length; ++i) {
            assertFalse(
                token.isBlacklisted(addresses[i]),
                "Address should not be blacklisted"
            );
        }
    }

    function testRemoveFromBlacklistBatched_worksGivenSomeAddressesNotBlacklisted(
        uint numberOfAddresses_
    ) public {
        // Setup
        numberOfAddresses_ = bound(numberOfAddresses_, 2, BATCH_LIMIT);
        address[] memory addresses = _generateAddresses(numberOfAddresses_);
        // Get number of addresses to blacklist, given no address is blacklisted yet
        uint numberOfBlacklistedAddresses = numberOfAddresses_ / 2;
        // Blacklist subset of addresses
        addresses =
            _blacklistNumberOfAddresses(numberOfBlacklistedAddresses, addresses);
        // Assert pre condition
        uint i = numberOfBlacklistedAddresses; // start from the first non-blacklisted address
        for (i; i < numberOfAddresses_; ++i) {
            assertFalse(
                token.isBlacklisted(addresses[i]),
                "Address should be not be blacklisted"
            );
            ++i;
        }

        // Test
        token.removeFromBlacklistBatched(addresses);

        // assertion
        for (uint j; j < addresses.length; ++j) {
            assertFalse(
                token.isBlacklisted(addresses[j]),
                "Address should be not be blacklisted"
            );
        }
    }

    /*  Test: Function setBlacklistManager()
        ├── Given the caller is not the owner
        │   └── When the function setBlacklistManager() is called
        │       └── Then the function should revert (Modifier in place test)
        └── Given the caller is the owner
            └── When the function setBlacklistManager() is called
                └── Then it should update the blacklist manager status (conditions tested in internal function)
                    └── And it should emit an event
       
    */
    function testSetBlacklistManager_worksGivenModifierInPlace(
        address unauthorized_
    ) public {
        // setup
        vm.assume(unauthorized_ != address(this));
        vm.prank(unauthorized_);
        vm.expectRevert(
            abi.encodeWithSelector(
                OZErrors.Ownable__UnauthorizedAccount, unauthorized_
            )
        );
        token.setBlacklistManager(unauthorized_, true);
    }

    function testSetBlacklistManager_worksGivenDirectsToInternalFunction(
        address newManager_,
        bool allowed_
    ) public {
        // setup
        vm.assume(newManager_ != address(0));
        // set blacklist manager if we want to revoke the rights
        if (false) {
            token.setBlacklistManager(newManager_, allowed_);
        }

        // Test
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_Blacklist_v1.BlacklistManagerUpdated(
            newManager_, allowed_, address(this)
        );
        token.setBlacklistManager(newManager_, allowed_);

        // Assertion
        assertEq(token.isBlacklistManager(newManager_), allowed_);
    }

    // ================================================================================
    // Test Internal

    // --------------------------------------------------------------------------------
    // Feature: Authorization for Blacklist Modification
    // Scenario: Restricting setting blacklist manager to token owner

    /*  Test: Function _setBlacklistManager()
        ├── Given the new blacklist manager is the zero address
        │   └── When the function _setBlacklistManager() is called
        │       └── Then it should revert
        └── Given the address is not the zero address
            ├── And the address should be approved as a blacklist manager
            │   └── And the address is not yet approved as a blacklist manager
            │       └── When the function setBlacklistManager() is called
            │           └── Then it should set the new blacklist manager address
            │               └── And it should emit an event
            ├── And the address should be approved as a blacklist manager
            │   └── But the address is already approved as a blacklist manager
            │       └── When the function setBlacklistManager() is called
            │           └── Then the address should remain approved as a blacklist manager
            │               └── And it should emit an event
            ├── And the address should be revoked as a blacklist manager
            │   └── And the address is approved as a blacklist manager
            │       └── When the function setBlacklistManager() is called
            │           └── Then the address should be revoked as a blacklist manager
            │               └── And it should emit an event
            └── And the address should be revoked as a blacklist manager
                └── But the address is not approved as a blacklist manager
                    └── When the function setBlacklistManager() is called
                        └── Then the address should remain revoked as a blacklist manager
                            └── And it should emit an event
    */

    function testInternalSetBlacklistManager_revertGivenAddressIsZero()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_ZeroAddress
                    .selector
            )
        );
        token.setBlacklistManager(address(0), true);
    }

    function testInternalSetBlacklistManager_worksGivenAddressNotYetApproved(
        address newManager_
    ) public {
        // Setup
        vm.assume(newManager_ != address(0));
        // Grant the rights
        bool allowed_ = true;

        // Test
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_Blacklist_v1.BlacklistManagerUpdated(
            newManager_, allowed_, address(this)
        );
        token.setBlacklistManager(newManager_, allowed_);

        // Assertion
        assertTrue(
            token.isBlacklistManager(newManager_),
            "Address should be approved as a blacklist manager"
        );
    }

    function testInternalSetBlacklistManager_worksGivenAddressIsAlreadyApproved(
        address newManager_
    ) public {
        // Setup
        vm.assume(newManager_ != address(0));
        // Grant the rights
        bool allowed_ = true;
        token.setBlacklistManager(newManager_, true);
        // Test
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_Blacklist_v1.BlacklistManagerUpdated(
            newManager_, allowed_, address(this)
        );
        token.setBlacklistManager(newManager_, allowed_);

        // Assertion
        assertTrue(
            token.isBlacklistManager(newManager_),
            "Address should be approved as a blacklist manager"
        );
    }

    function testInternalSetBlacklistManager_worksGivenAddressNotYetRevoked(
        address newManager_
    ) public {
        // Setup
        vm.assume(newManager_ != address(0));
        // Revoke the rights
        bool allowed_ = false;
        token.setBlacklistManager(newManager_, true);

        // Test
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_Blacklist_v1.BlacklistManagerUpdated(
            newManager_, allowed_, address(this)
        );
        token.setBlacklistManager(newManager_, allowed_);

        // Assertion
        assertFalse(
            token.isBlacklistManager(newManager_),
            "Address should not be approved as a blacklist manager"
        );
    }

    function testInternalSetBlacklistManager_worksGivenAddressIsAlreadyRevoked(
        address newManager_
    ) public {
        // Setup
        vm.assume(newManager_ != address(0));
        bool allowed_ = false;

        // Test
        vm.expectEmit(true, true, true, true);
        emit IERC20Issuance_Blacklist_v1.BlacklistManagerUpdated(
            newManager_, allowed_, address(this)
        );
        token.setBlacklistManager(newManager_, allowed_);

        // Assertion
        assertFalse(
            token.isBlacklistManager(newManager_),
            "Address should not be approved as a blacklist manager"
        );
    }

    // --------------------------------------------------------------------------------
    // Feature: Blacklist-Restricted Actions
    // Scenario: Restricting USP actions based on blacklist status

    /*  Test: Function _update()
        ├── Given the `from` address is blacklisted
        │   └── And the `to` address is not blacklisted
        │       └── When the function _update() is called
        │           └── Then it should revert
        ├── Given the `from` address is blacklisted
        │   └── And the `to` address is blacklisted
        │       └── When the function _update() is called
        │           └── Then it should revert
        ├── Given the `from` address is not blacklisted
        │   └── And the `to` address is blacklisted
        │       └── When the function _update() is called
        │           └── Then it should revert
        └── Given the `from` address is not blacklisted
            └── And the `to` address is not blacklisted
                └── When the function _update() is called
                    └── Then it should transfer the tokens
    */

    function testInternalUpdate_revertGivenFromAddressIsBlacklistedAndToAddressIsNotBlacklisted(
        address from_,
        address to_,
        uint amount_
    ) public {
        // setup
        vm.assume(from_ != address(0) && to_ != address(0));
        vm.assume(from_ != to_);
        amount_ = bound(amount_, 1, uint(type(uint).max - 1));
        _fundAddress(from_, amount_);
        _blacklistAddress(from_);

        // pre-condition
        assertTrue(
            token.isBlacklisted(from_), "from_ address should be blacklisted"
        );
        assertFalse(
            token.isBlacklisted(to_), "to_ address should not be blacklisted"
        );

        // test
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BlacklistedAddress
                    .selector,
                from_
            )
        );
        token.exposed_update(from_, to_, amount_);
    }

    function testInternalUpdate_revertGivenFromAndToAddressIsBlacklisted(
        address from_,
        address to_,
        uint amount_
    ) public {
        // setup
        vm.assume(from_ != address(0) && to_ != address(0));
        vm.assume(from_ != to_);
        amount_ = bound(amount_, 1, uint(type(uint).max - 1));
        _fundAddress(from_, amount_);
        _blacklistAddress(from_);
        _blacklistAddress(to_);
        // pre-condition
        assertTrue(
            token.isBlacklisted(from_), "from_ address should be blacklisted"
        );
        assertTrue(
            token.isBlacklisted(to_), "to_ address should be blacklisted"
        );

        // test
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BlacklistedAddress
                    .selector,
                from_
            )
        );
        token.exposed_update(from_, to_, amount_);
    }

    function testInternalUpdate_revertGivenFromAddressIsNotBlacklistedAndToAddressIsBlacklisted(
        address from_,
        address to_,
        uint amount_
    ) public {
        // setup
        vm.assume(from_ != address(0) && to_ != address(0));
        vm.assume(from_ != to_);
        amount_ = bound(amount_, 1, uint(type(uint).max - 1));
        _fundAddress(from_, amount_);
        _blacklistAddress(to_);

        // pre-condition
        assertFalse(
            token.isBlacklisted(from_),
            "from_ address should not be blacklisted"
        );
        assertTrue(
            token.isBlacklisted(to_), "to_ address should be blacklisted"
        );

        // test
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Issuance_Blacklist_v1
                    .ERC20Issuance_Blacklist_BlacklistedAddress
                    .selector,
                to_
            )
        );
        token.exposed_update(from_, to_, amount_);
    }

    function testInternalUpdate_revertGivenFromAndToAddressAreNotBlacklisted(
        address from_,
        address to_,
        uint amount_
    ) public {
        // setup
        vm.assume(from_ != address(0) && to_ != address(0));
        vm.assume(from_ != to_);
        amount_ = bound(amount_, 1, uint(type(uint).max - 1));
        _fundAddress(from_, amount_);

        // pre-condition
        assertFalse(
            token.isBlacklisted(from_),
            "from_ address should not be blacklisted"
        );
        assertFalse(
            token.isBlacklisted(to_), "to_ address should not be blacklisted"
        );
        assertEq(token.balanceOf(to_), 0, "to_ has no balance");

        // test
        token.exposed_update(from_, to_, amount_);

        // assertion
        assertEq(token.balanceOf(to_), amount_, "to_ has correct balance");
    }

    /*  Test: Function _isBlacklistManager()
        ├── Given the address is a blacklist manager
        │   └── When the function _isBlacklistManager() is called
        │       └── Then it should return true
        └── Given the address is not a blacklist manager
            └── When the function _isBlacklistManager() is called
                └── Then it should return false
    */

    function testInternalIsBlacklistManager_worksGivenAddressIsBlacklistManager(
        address _user
    ) public {
        // setup
        vm.assume(_user != address(0));
        // set blacklist manager
        token.setBlacklistManager(_user, true);

        // Assert
        assertTrue(
            token.isBlacklistManager(_user),
            "Address should be a blacklist manager"
        );
    }

    function testInternalIsBlacklistManager_worksGivenAddressNotBlacklistManager(
        address _user
    ) public {
        // setup
        vm.assume(_user != address(0));
        // set blacklist manager
        token.setBlacklistManager(_user, false);

        // Assert
        assertFalse(
            token.isBlacklistManager(_user),
            "Address should not be a blacklist manager"
        );
    }

    // ================================================================================
    // Helper Functions

    function _blacklistNumberOfAddresses(
        uint numberOfAddresses_,
        address[] memory addresses_
    ) internal returns (address[] memory) {
        for (uint i; i < numberOfAddresses_; ++i) {
            _blacklistAddress(addresses_[i]);
        }
        return addresses_;
    }

    function _blacklistAddress(address toBeBlacklisted_) internal {
        token.addToBlacklist(toBeBlacklisted_);
    }

    function _fundAddress(address toBeFunded_, uint amount_) internal {
        token.mint(toBeFunded_, amount_);
    }

    function _generateAddresses(uint count_)
        internal
        returns (address[] memory)
    {
        address[] memory addresses = new address[](count_);
        for (uint i; i < count_; ++i) {
            addresses[i] = makeAddr(string.concat("user", vm.toString(i)));
        }
        return addresses;
    }
}
