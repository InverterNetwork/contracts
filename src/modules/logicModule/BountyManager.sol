// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

import {ERC20PaymentClient} from
    "src/modules/base/mixins/ERC20PaymentClient.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IRoleAuthorizer} from "src/modules/authorizer/IRoleAuthorizer.sol";
import {IBountyManager} from "src/modules/logicModule/IBountyManager.sol";

import {
    IERC20PaymentClient,
    IPaymentProcessor
} from "src/modules/base/mixins/ERC20PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

//@todo this has a direct dependency to the new RoleAuthorizer Module.
//At the current state of the project the IRoleAuthorizer isnt the standardized Interface to use,
//That means there is a possibility function calls will fail if the roleAuthorizer isnt implemented as the Authorizer
//This will be changed in the coming future,
//but till then the RoleAuthorizer has to be selected as the Authorizer Module of the orchestrator if the BountyManager is to be used

contract BountyManager is IBountyManager, Module, ERC20PaymentClient {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    //@todo Reminder that this will be moved into the Module Contract at a later point of time
    modifier onlyRole(uint8 roleId) {
        if (
            !IRoleAuthorizer(address(__Module_orchestrator.authorizer()))
                .isAuthorized(roleId, _msgSender())
        ) {
            revert Module__BountyManager__OnlyRole(roleId, address(this));
        }
        _;
    }

    modifier onlyClaimContributor(uint claimId) {
        address sender = _msgSender();
        Contributor[] memory contribs = _claimRegistry[claimId].contributors;
        uint length = contribs.length;
        uint i;
        for (i; i < length;) {
            if (contribs[i].addr == sender) {
                //sender was found in contrib list
                break;
            }

            unchecked {
                ++i;
            }
        }

        //If i is length or higher the sender wasnt found in the contib list
        if (i >= length) {
            revert Module__BountyManager__OnlyClaimContributor();
        }
        _;
    }

    modifier validPayoutAmounts(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount
    ) {
        if (
            minimumPayoutAmount == 0
                || maximumPayoutAmount < minimumPayoutAmount
        ) {
            revert Module__BountyManager__InvalidPayoutAmounts();
        }
        _;
    }

    modifier validBountyId(uint bountyId) {
        if (!isExistingBountyId(bountyId)) {
            revert Module__BountyManager__InvalidBountyId();
        }
        _;
    }

    modifier validClaimId(uint claimId) {
        if (!isExistingClaimId(claimId)) {
            revert Module__BountyManager__InvalidClaimId();
        }
        _;
    }

    function validContributorsForBounty(
        Contributor[] memory contributors,
        Bounty memory bounty
    ) internal view {
        //@update to be in correct range
        uint length = contributors.length;
        //length cant be zero
        if (length == 0) {
            revert Module__BountyManager__InvalidContributorsLength();
        }
        uint totalAmount;
        uint currentAmount;
        address contrib;
        address orchestratorAddress = address(__Module_orchestrator);
        for (uint i; i < length;) {
            currentAmount = contributors[i].claimAmount;

            //amount cant be zero
            if (currentAmount == 0) {
                revert Module__BountyManager__InvalidContributorAmount();
            }

            contrib = contributors[i].addr;
            if (
                contrib == address(0) || contrib == address(this)
                    || contrib == orchestratorAddress
            ) {
                revert Module__BountyManager__InvalidContributorAddress();
            }

            totalAmount += currentAmount;
            unchecked {
                ++i;
            }
        }

        if (
            totalAmount > bounty.maximumPayoutAmount
                || totalAmount < bounty.minimumPayoutAmount
        ) {
            revert Module__BountyManager__ClaimExceedsGivenPayoutAmounts();
        }
    }

    modifier claimBelongingToBounty(uint claimId, uint bountyId) {
        if (_claimRegistry[claimId].bountyId != bountyId) {
            revert Module__BountyManager__ClaimNotBelongingToBounty();
        }
        _;
    }

    modifier notClaimed(uint bountyId) {
        //Its not claimed if claimedBy is still 0
        if (_bountyRegistry[bountyId].claimedBy != 0) {
            revert Module__BountyManager__BountyAlreadyClaimedOrLocked();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Value for what the next id will be.
    uint private _nextId;

    /// @dev Registry mapping ids to Bounty structs.
    mapping(uint => Bounty) private _bountyRegistry;

    /// @dev List of Bounty id's.
    LinkedIdList.List _bountyList;

    /// @dev Registry mapping ids to Claim structs.
    mapping(uint => Claim) private _claimRegistry;

    /// @dev List of Claim id's.
    LinkedIdList.List _claimList;

    //@dev Connects contributor addresses to claim Ids
    mapping(address => EnumerableSet.UintSet) contributorAddressToClaimIds;
    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);
        //init empty list of bounties and claims
        _bountyList.init();
        _claimList.init();
    }

    function init2(IOrchestrator, bytes memory)
        external
        override(Module)
        initializer2
    {
        //Note: due to the authorizer still not being set during initialization,
        // this function has to be called after.
        IRoleAuthorizer(address(orchestrator().authorizer()))
            .toggleModuleSelfManagement();
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IBountyManager
    function getBountyInformation(uint bountyId)
        external
        view
        validBountyId(bountyId)
        returns (Bounty memory)
    {
        return _bountyRegistry[bountyId];
    }

    /// @inheritdoc IBountyManager
    function listBountyIds() external view returns (uint[] memory) {
        return _bountyList.listIds();
    }

    /// @inheritdoc IBountyManager
    function isExistingBountyId(uint bountyId) public view returns (bool) {
        return _bountyList.isExistingId(bountyId);
    }

    /// @inheritdoc IBountyManager
    function getClaimInformation(uint claimId)
        external
        view
        validClaimId(claimId)
        returns (Claim memory)
    {
        return _claimRegistry[claimId];
    }

    /// @inheritdoc IBountyManager
    function listClaimIds() external view returns (uint[] memory) {
        return _claimList.listIds();
    }

    /// @inheritdoc IBountyManager
    function isExistingClaimId(uint claimId) public view returns (bool) {
        return _claimList.isExistingId(claimId);
    }

    /// @inheritdoc IBountyManager
    function listClaimIdsForContributorAddress(address contributorAddrs)
        external
        view
        returns (uint[] memory)
    {
        return contributorAddressToClaimIds[contributorAddrs].values();
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IBountyManager
    function addBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    )
        external
        onlyRole(uint8(Roles.BountyAdmin))
        validPayoutAmounts(minimumPayoutAmount, maximumPayoutAmount)
        returns (uint id)
    {
        // Note ids start at 1.
        uint bountyId = ++_nextId;

        // Add Bounty id to the list.
        _bountyList.addId(bountyId);

        Bounty storage b = _bountyRegistry[bountyId];

        b.minimumPayoutAmount = minimumPayoutAmount;
        b.maximumPayoutAmount = maximumPayoutAmount;
        b.details = details;

        emit BountyAdded(
            bountyId, minimumPayoutAmount, maximumPayoutAmount, details
        );

        return bountyId;
    }

    /// @inheritdoc IBountyManager
    function updateBounty(uint bountyId, bytes calldata details)
        external
        onlyRole(uint8(Roles.BountyAdmin))
        validBountyId(bountyId)
    {
        _bountyRegistry[bountyId].details = details;

        emit BountyUpdated(bountyId, details);
    }

    /// @inheritdoc IBountyManager
    function lockBounty(uint bountyId)
        external
        onlyRole(uint8(Roles.BountyAdmin))
        validBountyId(bountyId)
        notClaimed(bountyId)
    {
        _bountyRegistry[bountyId].claimedBy = type(uint).max;

        emit BountyLocked(bountyId);
    }

    /// @inheritdoc IBountyManager
    function addClaim(
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        onlyRole(uint8(Roles.ClaimAdmin))
        validBountyId(bountyId)
        notClaimed(bountyId)
        returns (uint id)
    {
        validContributorsForBounty(contributors, _bountyRegistry[bountyId]);
        // Count up shared nextId by one
        uint claimId = ++_nextId;

        // Add Claim id to the list.
        _claimList.addId(claimId);

        Claim storage c = _claimRegistry[claimId];

        // Add Claim instance to registry.
        c.bountyId = bountyId;

        uint length = contributors.length;
        for (uint i; i < length;) {
            c.contributors.push(contributors[i]);
            //add ClaimId to each contributor address accordingly
            contributorAddressToClaimIds[contributors[i].addr].add(claimId);
            unchecked {
                ++i;
            }
        }

        c.details = details;

        emit ClaimAdded(claimId, bountyId, contributors, details);

        return claimId;
    }

    /// @inheritdoc IBountyManager
    function updateClaimContributors(
        uint claimId,
        uint bountyId,
        Contributor[] calldata contributors
    )
        external
        validClaimId(claimId)
        onlyClaimContributor(claimId)
        validBountyId(bountyId)
    {
        validContributorsForBounty(contributors, _bountyRegistry[bountyId]);
        Claim storage c = _claimRegistry[claimId];

        uint length = c.contributors.length;
        for (uint i; i < length;) {
            //remove ClaimId for each contributor address
            contributorAddressToClaimIds[c.contributors[i].addr].remove(claimId); //@note c.contributors[i].addr -> is there a more gas efficient alternative to this?
            unchecked {
                ++i;
            }
        }

        delete c.contributors;

        length = contributors.length;

        for (uint i; i < length;) {
            c.contributors.push(contributors[i]);
            //add ClaimId again to each contributor address
            contributorAddressToClaimIds[contributors[i].addr].add(claimId);
            unchecked {
                ++i;
            }
        }

        emit ClaimContributorsUpdated(claimId, contributors);
    }

    /// @inheritdoc IBountyManager
    function updateClaimDetails(uint claimId, bytes calldata details)
        external
        validClaimId(claimId)
        onlyClaimContributor(claimId)
    {
        _claimRegistry[claimId].details = details;

        emit ClaimDetailsUpdated(claimId, details);
    }

    /// @inheritdoc IBountyManager
    function verifyClaim(uint claimId, uint bountyId)
        external
        onlyRole(uint8(Roles.VerifyAdmin))
        validClaimId(claimId)
        validBountyId(bountyId)
        claimBelongingToBounty(claimId, bountyId)
        notClaimed(bountyId)
    {
        Contributor[] memory contribs = _claimRegistry[claimId].contributors;

        uint length = contribs.length;

        //total amount needed to verifyBounty
        uint totalAmount;

        //current contributor in loop
        Contributor memory contrib;

        //For each Contributor add payments according to the claimAmount specified
        for (uint i; i < length;) {
            contrib = contribs[i];
            totalAmount += contrib.claimAmount;

            _addPaymentOrder(
                PaymentOrder({
                    recipient: contrib.addr,
                    amount: contrib.claimAmount,
                    createdAt: block.timestamp,
                    dueTo: block.timestamp //dueTo Date is now
                })
            );
            unchecked {
                ++i;
            }
        }

        //ensure that this contract has enough tokens to fulfill all payments
        _ensureTokenBalance(totalAmount);

        //when done process the Payments correctly
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClient(address(this))
        );

        //Set completed to true
        _bountyRegistry[bountyId].claimedBy = claimId;

        emit ClaimVerified(claimId, bountyId);
    }

    //----------------------------------
    // Role Functions

    /// @inheritdoc IBountyManager
    function grantBountyAdminRole(address addr) external onlyAuthorized {
        //@todo Will be removed in the future and moved to the authorizer directly
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer())); //@todo Cast to IRoleAuthorizer wont be necessary as soon as the IAuthorizer Interface in Orchestrator is replaced by IRoleAuthorizer, this is the same for the other implementations
        roleAuthorizer.grantRoleFromModule(uint8(Roles.BountyAdmin), addr);
    }

    /// @inheritdoc IBountyManager
    function grantClaimAdminRole(address addr) external onlyAuthorized {
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer()));
        roleAuthorizer.grantRoleFromModule(uint8(Roles.ClaimAdmin), addr);
    }

    /// @inheritdoc IBountyManager
    function grantVerifyAdminRole(address addr) external onlyAuthorized {
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer()));
        roleAuthorizer.grantRoleFromModule(uint8(Roles.VerifyAdmin), addr);
    }

    /// @inheritdoc IBountyManager
    function revokeBountyAdminRole(address addr) external onlyAuthorized {
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer()));
        roleAuthorizer.revokeRoleFromModule(uint8(Roles.BountyAdmin), addr);
    }

    /// @inheritdoc IBountyManager
    function revokeClaimAdminRole(address addr) external onlyAuthorized {
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer()));
        roleAuthorizer.revokeRoleFromModule(uint8(Roles.ClaimAdmin), addr);
    }

    /// @inheritdoc IBountyManager
    function revokeVerifyAdminRole(address addr) external onlyAuthorized {
        IRoleAuthorizer roleAuthorizer =
            IRoleAuthorizer(address(__Module_orchestrator.authorizer()));
        roleAuthorizer.revokeRoleFromModule(uint8(Roles.VerifyAdmin), addr);
    }

    //--------------------------------------------------------------------------
    // {ERC20PaymentClient} Function Implementations

    function _ensureTokenBalance(uint amount)
        internal
        override(ERC20PaymentClient)
    {
        uint balance = __Module_orchestrator.token().balanceOf(address(this));

        if (balance < amount) {
            // Trigger callback from orchestrator to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = __Module_orchestrator.executeTxFromModule(
                address(__Module_orchestrator.fundingManager()),
                abi.encodeWithSignature(
                    "transferOrchestratorToken(address,uint256)",
                    address(this),
                    amount - balance
                )
            );

            if (!ok) {
                revert Module__ERC20PaymentClient__TokenTransferFailed();
            }
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(ERC20PaymentClient)
    {
        IERC20 token = __Module_orchestrator.token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        override(ERC20PaymentClient)
        returns (bool)
    {
        return __Module_orchestrator.paymentProcessor() == who;
    }
}
