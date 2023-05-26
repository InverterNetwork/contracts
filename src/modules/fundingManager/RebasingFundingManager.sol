// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {
    ElasticReceiptTokenUpgradeable,
    ElasticReceiptTokenBase
} from "src/modules/fundingManager/token/ElasticReceiptTokenUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IRebasingERC20} from
    "src/modules/fundingManager/token/IRebasingERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@oz/utils/Strings.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";

contract RebasingFundingManager is
    IFundingManager,
    IRebasingERC20,
    ContextUpgradeable,
    ElasticReceiptTokenUpgradeable,
    Module
{
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
    // Init Function

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory configdata
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata);

        address proposalTokenAddress = abi.decode(configdata, (address));

        string memory _id = proposal_.proposalId().toString();
        string memory _name =
            string(abi.encodePacked("Inverter Funding Token - Proposal #", _id));
        string memory _symbol = string(abi.encodePacked("IFT-", _id));
        // Initial upstream contracts.
        __ElasticReceiptToken_init(
            _name,
            _symbol,
            IERC20MetadataUpgradeable(proposalTokenAddress).decimals()
        );
    }

    function token() public view returns (IERC20) {
        return __Module_proposal.token();
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
    // OnlyProposal Mutating Functions

    function transferProposalToken(address to, uint amount)
        external
        onlyProposal
        validAddress(to)
    {
        _transferProposalToken(to, amount);
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

    function _transferProposalToken(address to, uint amount) internal {
        __Module_proposal.token().safeTransfer(to, amount);

        emit TransferProposalToken(to, amount);
    }
}
