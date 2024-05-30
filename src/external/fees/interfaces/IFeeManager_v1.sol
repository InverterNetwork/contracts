// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IFeeManager_v1 {
    //--------------------------------------------------------------------------
    // Structs

    // When 'set' is true, the value is taken,
    // otherwise it reverts to the default value.
    // We need some indication here on whether
    // the value is set or not, to differentiate
    // between an uninitialized 0 and a real 0 fee.
    struct Fee {
        bool set;
        uint value;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice The given address is invalid
    error FeeManager__InvalidAddress();

    /// @notice The given fee is invalid
    error FeeManager__InvalidFee();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when the default protocol treasury is set
    /// @param defaultProtocolTreasury The address of the default protocol treasury
    event DefaultProtocolTreasurySet(address defaultProtocolTreasury);

    /// @notice Event emitted when the workflow treasury is set
    /// @param workflow The address of the workflow
    /// @param treasury The address of the treasury
    event WorkflowTreasurySet(address workflow, address treasury);

    /// @notice Event emitted when the default collateral fee is set
    /// @param fee The collateral fee amount in relation to the BPS
    event DefaultCollateralFeeSet(uint fee);

    /// @notice Event emitted when the default issuance fee is set
    /// @param fee The issuance fee amount in relation to the BPS
    event DefaultIssuanceFeeSet(uint fee);

    /// @notice Event emitted when the collateral workflow fee is set
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @param set Boolean that determines if the fee is actually used or not
    /// @param fee The collateral fee in relation to the BPS
    event CollateralWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    );

    /// @notice Event emitted when the issuance workflow fee is set
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @param set Boolean that determines if the fee is actually used or not
    /// @param fee The issuance fee in relation to the BPS
    event IssuanceWorkflowFeeSet(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    );

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @dev This function returns the Base Points used for percentage calculation
    /// @dev returns The Base Points used for percentage calculation. This value represents 100%
    function BPS() external returns (uint);

    //---------------------------
    // Treasuries

    /// @notice Returns the default treasury for all workflows
    /// @return The address of the treasury
    function getDefaultProtocolTreasury() external view returns (address);

    /// @notice Returns the treasury assigned to the given workflow
    /// @param workflow The address of the workflow
    /// @return The address of the treasury
    function getWorkflowTreasuries(address workflow)
        external
        view
        returns (address);

    //---------------------------
    // Fees

    /// @notice Returns the default collateral fee for all workflows
    /// @return The collateral fee amount in relation to the BPS
    function getDefaultCollateralFee() external view returns (uint);

    /// @notice Returns the default issuance fee for all workflows
    /// @return The issuance fee amount in relation to the BPS
    function getDefaultIssuanceFee() external view returns (uint);

    /// @notice Returns the collateral fee for a specific workflow module function
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @return fee The collateral fee amount in relation to the BPS
    function getCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee);

    /// @notice Returns the issuance fee for a specific workflow module function
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @return fee The issuance fee amount in relation to the BPS
    function getIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee);

    /// @notice Returns the collateral fee for a specific workflow module function and the according treasury address of the workflow
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @return fee The collateral fee amount in relation to the BPS
    /// @return treasury The address of the treasury
    function getCollateralWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury);

    /// @notice Returns the issuance fee for a specific workflow module function and the according treasury address of the workflow
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @return fee The issuance fee amount in relation to the BPS
    /// @return treasury The address of the treasury
    function getIssuanceWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury);

    //--------------------------------------------------------------------------
    // Setter Functions

    //---------------------------
    // Treasuries

    /// @notice Sets the default protocol treasury address
    /// @dev This function can only be called by the owner
    /// @dev The given treasury address can not be address(0)
    /// @param _defaultProtocolTreasury The address of the default protocol treasury
    function setDefaultProtocolTreasury(address _defaultProtocolTreasury)
        external;

    /// @notice Sets the protocol treasury address for a specific workflow
    /// @dev This function can only be called by the owner
    /// @dev The given treasury address can not be address(0)
    /// @param workflow The address of the workflow
    /// @param treasury The address of the protocol treasury for that specific workflow
    function setWorkflowTreasury(address workflow, address treasury) external;

    //---------------------------
    // Fees

    /// @notice Sets the default collateral fee of the protocol
    /// @dev This function can only be called by the owner
    /// @dev The given fee needs to be less than the BPS
    /// @param _defaultCollateralFee The default collateral fee of the protocol in relation to the BPS
    function setDefaultCollateralFee(uint _defaultCollateralFee) external;

    /// @notice Sets the default issuance fee of the protocol
    /// @dev This function can only be called by the owner
    /// @dev The given fee needs to be less than the BPS
    /// @param _defaultIssuanceFee The default issuance fee of the protocol in relation to the BPS
    function setDefaultIssuanceFee(uint _defaultIssuanceFee) external;

    /// @notice Sets the collateral fee for a specific workflow module function
    /// @dev This function can only be called by the owner
    /// @dev The given fee needs to be less than the BPS
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @param set Boolean that determines if the fee is actually used or not
    /// @param fee The collateral fee in relation to the BPS
    function setCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;

    /// @notice Sets the issuance fee for a specific workflow module function
    /// @dev This function can only be called by the owner
    /// @dev The given fee needs to be less than the BPS
    /// @param workflow The address of the workflow that contains the module function
    /// @param module The address of the module that contains the function
    /// @param functionSelector The function selector of the target function
    /// @param set Boolean that determines if the fee is actually used or not
    /// @param fee The issuance fee in relation to the BPS
    function setIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external;
}
