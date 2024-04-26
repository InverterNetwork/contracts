// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IFeeManager} from "src/external/fees/IFeeManager.sol";

// External Dependencies
import {ERC165} from "@oz/utils/introspection/ERC165.sol";

import {Ownable2StepUpgradeable} from
    "@oz-up/access/Ownable2StepUpgradeable.sol";

contract FeeManager is ERC165, IFeeManager, Ownable2StepUpgradeable {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165)
        returns (bool)
    {
        return interfaceId == type(IFeeManager).interfaceId
            || ERC165.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------
    // Modifier

    modifier validAddress(address adr) {
        if (adr == address(0)) {
            revert FeeManager__InvalidAddress();
        }
        _;
    }

    modifier validFee(uint fee) {
        if (fee > BPS) {
            revert FeeManager__InvalidFee();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Base Points used for percentage calculation. This value represents 100%
    uint public constant BPS = 10_000;

    address internal defaultProtocolTreasury;

    //Orchestrator => treasury
    mapping(address => address) internal workflowTreasuries;

    // default fees that apply unless workflow
    // specific fees are set
    uint internal defaultIssuanceFee;
    uint internal defaultCollateralFee;

    //orchestrator => hash(functionSelector + module address) => feeStruct
    mapping(address => mapping(bytes32 => Fee)) internal workflowIssuanceFees;
    mapping(address => mapping(bytes32 => Fee)) internal workflowCollateralFees;

    //--------------------------------------------------------------------------
    // Initialization

    function init( //@note instead constructor?
        address owner,
        address _defaultProtocolTreasury,
        uint _defaultCollateralFee,
        uint _defaultIssuanceFee
    )
        external
        initializer
        validAddress(owner)
        validAddress(_defaultProtocolTreasury)
        validFee(_defaultCollateralFee)
        validFee(_defaultIssuanceFee)
    {
        __Ownable_init(owner); //@note instead constructor -> not upgradeable?

        defaultProtocolTreasury = _defaultProtocolTreasury;
        defaultCollateralFee = _defaultCollateralFee;
        defaultIssuanceFee = _defaultIssuanceFee;
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    //---------------------------
    // Treasuries

    /// @inheritdoc IFeeManager
    function getDefaultProtocolTreasury() public view returns (address) {
        return defaultProtocolTreasury;
    }

    /// @inheritdoc IFeeManager
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

    /// @inheritdoc IFeeManager
    function getDefaultCollateralFee() external view returns (uint) {
        return defaultCollateralFee;
    }

    /// @inheritdoc IFeeManager
    function getDefaultIssuanceFee() external view returns (uint) {
        return defaultIssuanceFee;
    }

    /// @inheritdoc IFeeManager
    function getCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) public view returns (uint fee) {
        bytes32 moduleFunctionHash =
            getModuleFunctionHash(module, functionSelector);

        //In case workflow fee is set return it
        if (workflowCollateralFees[workflow][moduleFunctionHash].set) {
            return workflowCollateralFees[workflow][moduleFunctionHash].value;
        } //otherwise return default fee
        else {
            return defaultCollateralFee;
        }
    }

    /// @inheritdoc IFeeManager
    function getIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector
    ) public view returns (uint fee) {
        bytes32 moduleFunctionHash =
            getModuleFunctionHash(module, functionSelector);

        //In case workflow fee is set return it
        if (workflowIssuanceFees[workflow][moduleFunctionHash].set) {
            return workflowIssuanceFees[workflow][moduleFunctionHash].value;
        } //otherwise return default fee
        else {
            return defaultIssuanceFee;
        }
    }

    /// @inheritdoc IFeeManager
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

    /// @inheritdoc IFeeManager
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
    // Treasuries

    /// @inheritdoc IFeeManager
    function setDefaultProtocolTreasury(address _defaultProtocolTreasury)
        external
        onlyOwner
        validAddress(_defaultProtocolTreasury)
    {
        defaultProtocolTreasury = _defaultProtocolTreasury;
        emit DefaultProtocolTreasurySet(_defaultProtocolTreasury);
    }

    /// @inheritdoc IFeeManager
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

    /// @inheritdoc IFeeManager
    function setDefaultCollateralFee(uint _defaultCollateralFee)
        external
        onlyOwner
        validFee(_defaultCollateralFee)
    {
        defaultCollateralFee = _defaultCollateralFee;
        emit DefaultCollateralFeeSet(_defaultCollateralFee);
    }

    /// @inheritdoc IFeeManager
    function setDefaultIssuanceFee(uint _defaultIssuanceFee)
        external
        onlyOwner
        validFee(_defaultIssuanceFee)
    {
        defaultIssuanceFee = _defaultIssuanceFee;
        emit DefaultIssuanceFeeSet(_defaultIssuanceFee);
    }

    /// @inheritdoc IFeeManager
    function setCollateralWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyOwner validFee(fee) {
        bytes32 moduleFunctionHash =
            getModuleFunctionHash(module, functionSelector);

        Fee storage f = workflowCollateralFees[workflow][moduleFunctionHash];
        f.set = set;
        f.value = fee;

        emit CollateralWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );
    }

    /// @inheritdoc IFeeManager
    function setIssuanceWorkflowFee(
        address workflow,
        address module,
        bytes4 functionSelector,
        bool set,
        uint fee
    ) external onlyOwner validFee(fee) {
        bytes32 moduleFunctionHash =
            getModuleFunctionHash(module, functionSelector);

        Fee storage f = workflowIssuanceFees[workflow][moduleFunctionHash];
        f.set = set;
        f.value = fee;

        emit IssuanceWorkflowFeeSet(
            workflow, module, functionSelector, set, fee
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function getModuleFunctionHash(address module, bytes4 functionSelector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(module, functionSelector));
    }
}
