// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IFeeManager_v1} from "@ex/fees/interfaces/IFeeManager_v1.sol";

// External Dependencies
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@oz-up/access/Ownable2StepUpgradeable.sol";

/**
 * @title   Inverter Fee Manager Contract
 *
 * @notice  This contract manages the different fees possible on a protocol level.
 *          The different fees can be fetched publicly and be set by the owner of the contract.
 *
 *  @dev    Inherits from {ERC165Upgradeable} for interface detection, {Ownable2StepUpgradeable} for owner-based
 *          access control, and implements the {IFeeManager_v1} interface.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract FeeManager_v1 is
    ERC165Upgradeable,
    IFeeManager_v1,
    Ownable2StepUpgradeable
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165Upgradeable)
        returns (bool)
    {
        return interfaceId == type(IFeeManager_v1).interfaceId
            || ERC165Upgradeable.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev	Modififer to check if the given address is valid.
    modifier validAddress(address adr) {
        if (adr == address(0)) {
            revert FeeManager__InvalidAddress();
        }
        _;
    }

    /// @dev	Modififer to check if the given fee is valid.
    modifier validFee(uint fee) {
        if (fee > maxFee) {
            revert FeeManager__InvalidFee();
        }
        _;
    }

    /// @dev	Modififer to check if the given max fee is valid.
    modifier validMaxFee(uint max) {
        if (max > BPS) {
            revert FeeManager__InvalidMaxFee();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev	Base Points used for percentage calculation. This value represents 100%.
    uint public constant BPS = 10_000;
    /// @dev	The maximum fee percentage amount that can be set. Based on the BPS.
    uint public maxFee;
    /// @dev	The default protocol treasury address.
    address internal defaultProtocolTreasury;
    /// @dev	The workflow treasury addres. Orchestrator => treasury
    mapping(address => address) internal workflowTreasuries;
    /// @dev	The default issuance fee percentage amount that apply unless workflow
    ///         specific fees are set.
    uint internal defaultIssuanceFee;
    /// @dev	The default collateral fee percentage amount that apply unless workflow
    ///         specific fees are set.
    uint internal defaultCollateralFee;
    /// @dev    The workflow issuance fee. Orchestrator => hash(functionSelector + module address) => feeStruct.
    mapping(address => mapping(bytes32 => Fee)) internal workflowIssuanceFees;
    /// @dev    The workflow collateral fee. Orchestrator => hash(functionSelector + module address) => feeStruct.
    mapping(address => mapping(bytes32 => Fee)) internal workflowCollateralFees;
    /// @dev    Storage gap for future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Constructor

    constructor() {
        _disableInitializers();
    }

    //--------------------------------------------------------------------------
    // Initialization

    function init(
        address owner,
        address _defaultProtocolTreasury,
        uint _defaultCollateralFee,
        uint _defaultIssuanceFee
    )
        external
        initializer
        validAddress(owner)
        validAddress(_defaultProtocolTreasury)
    {
        __Ownable_init(owner);

        // initial max fee is 10%
        _setMaxFee(1000);

        if (_defaultCollateralFee > maxFee || _defaultIssuanceFee > maxFee) {
            revert FeeManager__InvalidFee();
        }

        _setDefaultProtocolTreasury(_defaultProtocolTreasury);
        _setDefaultCollateralFee(_defaultCollateralFee);
        _setDefaultIssuanceFee(_defaultIssuanceFee);
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    //---------------------------
    // Treasuries

    /// @inheritdoc IFeeManager_v1
    function getDefaultProtocolTreasury() public view returns (address) {
        return defaultProtocolTreasury;
    }

    /// @inheritdoc IFeeManager_v1
    function getWorkflowTreasuries(address workflow)
        public
        view
        returns (address)
    {
        address treasury = workflowTreasuries[workflow];
        if (treasury == address(0)) {
            return defaultProtocolTreasury;
        } else {
            return treasury;
        }
    }

    //---------------------------
    // Fees

    /// @inheritdoc IFeeManager_v1
    function getDefaultCollateralFee() external view returns (uint) {
        return defaultCollateralFee;
    }

    /// @inheritdoc IFeeManager_v1
    function getDefaultIssuanceFee() external view returns (uint) {
        return defaultIssuanceFee;
    }

    /// @inheritdoc IFeeManager_v1
    function getCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) public view returns (uint fee) {
        bytes32 moduleFunctionHash =
            _getModuleFunctionHash(module, functionSelector);

        // In case workflow fee is set return it
        if (workflowCollateralFees[workflow][moduleFunctionHash].set) {
            return workflowCollateralFees[workflow][moduleFunctionHash].value;
        }
        // otherwise return default fee
        else {
            return defaultCollateralFee;
        }
    }

    /// @inheritdoc IFeeManager_v1
    function getIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) public view returns (uint fee) {
        bytes32 moduleFunctionHash =
            _getModuleFunctionHash(module, functionSelector);

        // In case workflow fee is set return it
        if (workflowIssuanceFees[workflow][moduleFunctionHash].set) {
            return workflowIssuanceFees[workflow][moduleFunctionHash].value;
        }
        // otherwise return default fee
        else {
            return defaultIssuanceFee;
        }
    }

    /// @inheritdoc IFeeManager_v1
    function getCollateralWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury) {
        return (
            getCollateralWorkflowFee(workflow, module, functionSelector),
            getWorkflowTreasuries(workflow)
        );
    }

    /// @inheritdoc IFeeManager_v1
    function getIssuanceWorkflowFeeAndTreasury(
        address workflow,
        address module,
        bytes4 functionSelector
    ) external view returns (uint fee, address treasury) {
        return (
            getIssuanceWorkflowFee(workflow, module, functionSelector),
            getWorkflowTreasuries(workflow)
        );
    }

    //--------------------------------------------------------------------------
    // Setter Functions

    //---------------------------
    // MaxFee

    /// @inheritdoc IFeeManager_v1
    function setMaxFee(uint _maxFee) external onlyOwner validMaxFee(_maxFee) {
        _setMaxFee(_maxFee);
    }

    //---------------------------
    // Treasuries

    /// @inheritdoc IFeeManager_v1
    function setDefaultProtocolTreasury(address _defaultProtocolTreasury)
        external
        onlyOwner
        validAddress(_defaultProtocolTreasury)
    {
        defaultProtocolTreasury = _defaultProtocolTreasury;
        emit DefaultProtocolTreasurySet(_defaultProtocolTreasury);
    }

    /// @inheritdoc IFeeManager_v1
    function setWorkflowTreasury(address workflow, address treasury)
        external
        onlyOwner
        validAddress(treasury)
    {
        workflowTreasuries[workflow] = treasury;
        emit WorkflowTreasurySet(workflow, treasury);
    }

    //---------------------------
    // Fees

    /// @inheritdoc IFeeManager_v1
    function setDefaultCollateralFee(uint _defaultCollateralFee)
        external
        onlyOwner
    {
        _setDefaultCollateralFee(_defaultCollateralFee);
    }

    /// @inheritdoc IFeeManager_v1
    function setDefaultIssuanceFee(uint _defaultIssuanceFee)
        external
        onlyOwner
    {
        _setDefaultIssuanceFee(_defaultIssuanceFee);
    }

    /// @inheritdoc IFeeManager_v1
    function setCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyOwner validFee(fee) {
        bytes32 moduleFunctionHash =
            _getModuleFunctionHash(module, functionSelector);

        Fee storage f = workflowCollateralFees[workflow][moduleFunctionHash];
        f.set = set;
        f.value = fee;

        emit CollateralWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );
    }

    /// @inheritdoc IFeeManager_v1
    function setIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyOwner {
        _setIssuanceWorkflowFee(workflow, module, functionSelector, set, fee);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _getModuleFunctionHash(address module, bytes4 functionSelector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, functionSelector));
    }

    function _setDefaultProtocolTreasury(address _defaultProtocolTreasury)
        internal
        validAddress(_defaultProtocolTreasury)
    {
        defaultProtocolTreasury = _defaultProtocolTreasury;
        emit DefaultProtocolTreasurySet(_defaultProtocolTreasury);
    }

    function _setWorkflowTreasury(address workflow, address treasury)
        internal
        validAddress(treasury)
    {
        workflowTreasuries[workflow] = treasury;
        emit WorkflowTreasurySet(workflow, treasury);
    }

    function _setDefaultCollateralFee(uint _defaultCollateralFee)
        internal
        validFee(_defaultCollateralFee)
    {
        defaultCollateralFee = _defaultCollateralFee;
        emit DefaultCollateralFeeSet(_defaultCollateralFee);
    }

    function _setDefaultIssuanceFee(uint _defaultIssuanceFee)
        internal
        validFee(_defaultIssuanceFee)
    {
        defaultIssuanceFee = _defaultIssuanceFee;
        emit DefaultIssuanceFeeSet(_defaultIssuanceFee);
    }

    function _setIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) internal validFee(fee) {
        bytes32 moduleFunctionHash =
            _getModuleFunctionHash(module, functionSelector);

        Fee storage f = workflowIssuanceFees[workflow][moduleFunctionHash];
        f.set = set;
        f.value = fee;

        emit IssuanceWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );
    }

    function _setMaxFee(uint _maxFee) internal validMaxFee(_maxFee) {
        maxFee = _maxFee;
        emit MaxFeeSet(_maxFee);
    }
}
