// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IInverterTransparentUpgradeableProxy_v1} from
    "src/proxies/interfaces/IInverterTransparentUpgradeableProxy_v1.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

// External Dependencies
import {ERC1967Proxy} from "@oz/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@oz/proxy/ERC1967/ERC1967Utils.sol";
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

/**
 * @title   Inverter TransparentUpgradeableProxy
 *
 * @notice  An alternative variant of the {TransparentUpgradeableProxy} of OpenZeppelin that
 *          allows for upgrading the linked implementation of the proxy to the implementation
 *          provided by a linked beacon.
 *
 * @dev     This contract is a fork of the {TransparentUpgradeableProxy} from openzeppelin.
 *          We adapted the callable functions of the admin account to only be able to upgrade the
 *          implementation to the newest implementation of the linked {InverterBeacon_v1}.
 *
 *          !!! IMPORTANT !!!
 *
 *          1.  If any account other than the admin calls the proxy, the call will be forwarded to
 *              the implementation, even if that call matches the
 *              {IInverterTransparentUpgradeableProxy_v1-upgradeToNewestVersion} function exposed by the
 *              proxy itself.
 *          2.  If the admin calls the proxy, it can call the `upgradeToNewestVersion` function but any
 *              other call won't be forwarded to the implementation. If the admin tries to call a function
 *              on the implementation it will fail with an error indicating the proxy admin cannot fallback
 *              to the target implementation.
 *
 *          These properties mean that the admin account can only be used for upgrading the proxy, so it's
 *          best if it's a dedicated account that is not used for anything else. This will avoid headaches
 *          due to sudden errors when trying to call a function from the proxy implementation. For this
 *          reason, the proxy deploys an instance of {ProxyAdmin} and allows upgrades only if they come
 *          through it. You should think of the `ProxyAdmin` instance as the administrative interface of the
 *          proxy, including the ability to change who can trigger upgrades by transferring ownership.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 *
 */
contract InverterTransparentUpgradeableProxy_v1 is ERC1967Proxy {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The provided beacon address doesnt support the interface {IInverterBeacon_v1}.
    error InverterTransparentUpgradeableProxy__InvalidBeacon();

    /// @notice	If the proxy caller is the current admin then it can only call the admin functions.
    error InverterTransparentUpgradeableProxy__ProxyDeniedAdminAccess();

    //--------------------------------------------------------------------------
    // State

    /// @dev	The address of the admin that can update the implementation address of this proxy.
    address internal immutable _admin;

    /// @dev	The address of the beacon that is used to fetch the implementation address.
    IInverterBeacon_v1 internal immutable _beacon;

    /// @dev	The version of the linked implementation, stored in an ERC-7201 namespace so it cannot
    ///         collide with the storage of the implementation the proxy delegates to.
    /// @custom:storage-location erc7201:inverter.storage.InverterTransparentUpgradeableProxy_v1
    struct VersionStorage {
        uint majorVersion;
        uint minorVersion;
        uint patchVersion;
    }

    /// @dev	keccak256(abi.encode(uint(keccak256("inverter.storage.InverterTransparentUpgradeableProxy_v1")) - 1))
    ///         & ~bytes32(uint(0xff))
    bytes32 private constant VERSION_STORAGE_LOCATION =
        0x7f64a4379a384334ad31a069fd0e3183465498d81cb6b14f5f286747a479a800;

    //--------------------------------------------------------------------------
    // Constructor

    constructor(
        IInverterBeacon_v1 beacon,
        address initialOwner,
        bytes memory _data
    ) ERC1967Proxy(beacon.getImplementationAddress(), _data) {
        if (
            !ERC165(address(beacon)).supportsInterface(
                type(IInverterBeacon_v1).interfaceId
            )
        ) {
            revert InverterTransparentUpgradeableProxy__InvalidBeacon();
        }

        _beacon = beacon;
        _admin = initialOwner;
        _setVersion();
        // Set the storage value and emit an event for ERC-1967 compatibility
        ERC1967Utils.changeAdmin(initialOwner);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @dev	This overrides the possible use of a "version" function in the modules that are called via the
    ///         Proxy Beacon structure.
    /// @notice Returns the version of the linked implementation.
    /// @return The major version.
    /// @return The minor version.
    /// @return The patch version.
    function version() external view returns (uint, uint, uint) {
        VersionStorage storage $ = _getVersionStorage();
        return ($.majorVersion, $.minorVersion, $.patchVersion);
    }

    /// @dev    Fallback function to delegate calls to the implementation contract
    ///         even if the call data is empty but msg.value > 0.
    receive() external payable virtual {
        _fallback();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev	Upgrades the implementation to the newest version listed in the beacon.
    function upgradeToNewestVersion() internal virtual {
        // Override implementation
        ERC1967Utils.upgradeToAndCall(_beacon.implementation(), bytes(""));
        // Override version
        _setVersion();
    }

    /// @dev	Stores the current version of the linked beacon.
    function _setVersion() internal {
        VersionStorage storage $ = _getVersionStorage();
        ($.majorVersion, $.minorVersion, $.patchVersion) = _beacon.version();
    }

    /// @dev	Returns the namespaced storage struct holding the version.
    function _getVersionStorage()
        private
        pure
        returns (VersionStorage storage $)
    {
        assembly {
            $.slot := VERSION_STORAGE_LOCATION
        }
    }

    /// @dev	If caller is the admin process the call internally, otherwise transparently fallback to the proxy behavior.
    function _fallback() internal virtual override {
        if (msg.sender == _admin) {
            if (
                msg.sig
                    == IInverterTransparentUpgradeableProxy_v1
                        .upgradeToNewestVersion
                        .selector
            ) {
                upgradeToNewestVersion();
            } else {
                revert
                    InverterTransparentUpgradeableProxy__ProxyDeniedAdminAccess();
            }
        } else {
            super._fallback();
        }
    }
}
