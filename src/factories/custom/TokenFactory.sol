// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Implementations
import {ERC20Issuance_v1} from "src/external/token/ERC20Issuance_v1.sol";
import {MintWrapper} from "src/external/token/MintWrapper.sol";

// External Dependencies
import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";

/**
 * @title   ERC20Issuance Token Factory
 * 
 * @notice  Used to deploy an ERC20Issuance_v1 token with configurable parameters
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to
 *                          our Security Policy at security.inverter.network or
 *                          email us directly!
 *
 * @author  Inverter Network
 */
contract ERC20Issuance_Factory_v1 is ERC2771Context {

    event TokenDeployed(
        address indexed token,
        string name,
        string symbol,
        uint8 decimals,
        uint maxSupply,
        address owner
    );

    constructor(address _trustedForwarder) ERC2771Context(_trustedForwarder) {}

    /**
     * @notice Deploys a new ERC20Issuance_v1 token
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param decimals The number of decimals for the token
     * @param maxSupply The maximum supply of the token
     * @param owner The address that will own the token contract
     * @return token The address of the deployed token
     */
    function deployToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint maxSupply,
        address owner
    ) external returns (ERC20Issuance_v1 token, MintWrapper mintWrapper) {
        token = new ERC20Issuance_v1(
            name,
            symbol,
            decimals,
            maxSupply,
            address(this)
        );

        // deploy mint wrapper
     mintWrapper = new MintWrapper(
            token,
            address(this) // assigns owner role to itself initially to manage minting rights temporarily
        );

        // set mint wrapper as minter
        token.setMinter(address(mintWrapper), true);
        token.transferOwnership(owner);
        mintWrapper.setMinter(owner, true);
        mintWrapper.transferOwnership(owner);
    }
}
