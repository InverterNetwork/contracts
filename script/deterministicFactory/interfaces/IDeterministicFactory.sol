// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IDeterministicFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice The caller is not allowed to use the factory.
    error DeterministicFactory__NotAllowed();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when the allowed deployer is changed.
    event DeterministicFactory__AllowedDeployerChanged(
        address indexed newAllowedDeployer
    );

    /// @notice Emitted when a new deployment took place.
    event DeterministicFactory__NewDeployment(
        bytes32 indexed salt, address indexed deployment
    );

    //--------------------------------------------------------------------------
    // Public Functions

    function setAllowedDeployer(address _allowedDeployer) external;

    /// @notice Function to deploy an arbitrary contract with a salt
    ///         via Create2, resulting in a deterministic deployment
    ///         address.
    /// @param salt The salt to use for the deployment.
    /// @param code The contract code to deploy.
    /// @return deploymentAddress The address of the deployed contract.
    function deployWithCreate2(bytes32 salt, bytes calldata code)
        external
        returns (address deploymentAddress);

    /// @notice Returns the address of a contract that would be deployed
    ///         via create2 with the given inputs.
    /// @param salt The salt to use for the deployment.
    /// @param codeHash The keccak256 hash of the contract code.
    /// @return deploymentAddress The address of the contract if deployed.
    function computeCreate2Address(bytes32 salt, bytes32 codeHash)
        external
        view
        returns (address deploymentAddress);

    /// @notice Helper function to get the keccak256 hash of a given code.
    /// @param code The code to hash.
    /// @return codeHash The keccak256 hash of the code.
    function getCodeHash(bytes memory code)
        external
        pure
        returns (bytes32 codeHash);
}
