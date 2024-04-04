// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {
    ElasticReceiptTokenUpgradeable,
    ElasticReceiptTokenBase
} from
    "src/modules/fundingManager/rebasing/abstracts/ElasticReceiptTokenUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";
import {IRebasingERC20} from
    "src/modules/fundingManager/rebasing/interfaces/IRebasingERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

contract RebasingFundingManager is
    IFundingManager,
    ContextUpgradeable,
    ElasticReceiptTokenUpgradeable,
    Module
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ElasticReceiptTokenUpgradeable, Module)
        returns (bool)
    {
        return interfaceId == type(IFundingManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using Strings for uint;
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifier

    /// @dev Checks if the given Address is valid.
    modifier validAddress(address to) {
        if (to == address(0) || to == address(this)) {
            revert Module__FundingManager__InvalidAddress();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    uint internal constant DEPOSIT_CAP = 100_000_000e18;

    //--------------------------------------------------------------------------
    // Storage

    IERC20 private _token;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        address orchestratorTokenAddress = abi.decode(configData, (address));
        _token = IERC20(orchestratorTokenAddress);

        string memory _id = orchestrator_.orchestratorId().toString();
        string memory _name = string(
            abi.encodePacked("Inverter Funding Token - Orchestrator #", _id)
        );
        string memory _symbol = string(abi.encodePacked("IFT-", _id));
        // Initial upstream contracts.
        __ElasticReceiptToken_init(
            _name, _symbol, IERC20Metadata(orchestratorTokenAddress).decimals()
        );
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    /// @dev Returns the current token balance as supply target.
    function _supplyTarget()
        internal
        view
        override(ElasticReceiptTokenBase)
        returns (uint)
    {
        return token().balanceOf(address(this));
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    function deposit(uint amount) external {
        _deposit(_msgSender(), _msgSender(), amount);
    }

    function depositFor(address to, uint amount) external {
        _deposit(_msgSender(), to, amount);
    }

    function withdraw(uint amount) external {
        _withdraw(_msgSender(), _msgSender(), amount);
    }

    function withdrawTo(address to, uint amount) external {
        _withdraw(_msgSender(), to, amount);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
        validAddress(to)
    {
        _transferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // Internal Mutating Functions

    function _deposit(address from, address to, uint amount) internal {
        //Depositing from itself with its own balance would mint tokens without increasing underlying balance.
        if (from == address(this)) {
            revert Module__FundingManager__CannotSelfDeposit();
        }

        if ((amount + token().balanceOf(address(this))) > DEPOSIT_CAP) {
            revert Module__FundingManager__DepositCapReached();
        }

        _mint(to, amount);

        token().safeTransferFrom(from, address(this), amount);

        emit Deposit(from, to, amount);
    }

    function _withdraw(address from, address to, uint amount) internal {
        amount = _burn(from, amount);

        token().safeTransfer(to, amount);

        emit Withdrawal(from, to, amount);
    }

    function _transferOrchestratorToken(address to, uint amount) internal {
        token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }
}
