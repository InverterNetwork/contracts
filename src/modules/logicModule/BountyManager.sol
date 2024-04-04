// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Libraries
import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";

// Internal Dependencies

import {
    ERC20PaymentClient,
    Module
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";
import {IBountyManager} from "src/modules/logicModule/IBountyManager.sol";

import {
    IERC20PaymentClient,
    IPaymentProcessor
} from "src/modules/logicModule/paymentClient/ERC20PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract BountyManager is IBountyManager, ERC20PaymentClient {
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC20PaymentClient)
        returns (bool)
    {
        return interfaceId == type(IBountyManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using EnumerableSet for EnumerableSet.UintSet;
    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

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

    modifier notLocked(uint bountyId) {
        if (_bountyRegistry[bountyId].locked) {
            revert Module__BountyManager__BountyLocked();
        }
        _;
    }

    modifier notClaimed(uint claimId) {
        if (_claimRegistry[claimId].claimed) {
            revert Module__BountyManager__AlreadyClaimed();
        }
        _;
    }

    function contributorsNotChanged(
        uint claimId,
        Contributor[] memory contributors
    ) internal view {
        Contributor[] memory claimContribs =
            _claimRegistry[claimId].contributors;

        uint length = contributors.length;
        for (uint i; i < length;) {
            if (
                contributors[i].addr != claimContribs[i].addr
                    || contributors[i].claimAmount != claimContribs[i].claimAmount
            ) revert Module__BountyManager__ContributorsChanged();
            unchecked {
                i++;
            }
        }
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    uint internal constant _SENTINEL = type(uint).max;

    bytes32 public constant BOUNTY_ISSUER_ROLE = "BOUNTY_ISSUER";
    bytes32 public constant CLAIMANT_ROLE = "CLAIMANT";
    bytes32 public constant VERIFIER_ROLE = "VERIFIER";

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
        onlyModuleRole(BOUNTY_ISSUER_ROLE)
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
        onlyModuleRole(BOUNTY_ISSUER_ROLE)
        validBountyId(bountyId)
        notLocked(bountyId)
    {
        _bountyRegistry[bountyId].details = details;

        emit BountyUpdated(bountyId, details);
    }

    /// @inheritdoc IBountyManager
    function lockBounty(uint bountyId)
        external
        onlyModuleRole(BOUNTY_ISSUER_ROLE)
        validBountyId(bountyId)
        notLocked(bountyId)
    {
        _bountyRegistry[bountyId].locked = true;

        emit BountyLocked(bountyId);
    }

    /// @inheritdoc IBountyManager
    function addClaim(
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        onlyModuleRole(CLAIMANT_ROLE)
        validBountyId(bountyId)
        notLocked(bountyId)
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
        Contributor[] calldata contributors
    )
        external
        validClaimId(claimId)
        notClaimed(claimId)
        notLocked(_claimRegistry[claimId].bountyId)
        onlyModuleRole(CLAIMANT_ROLE)
    {
        validContributorsForBounty(
            contributors, _bountyRegistry[_claimRegistry[claimId].bountyId]
        );
        Claim storage c = _claimRegistry[claimId];

        uint length = c.contributors.length;
        for (uint i; i < length;) {
            //remove ClaimId for each contributor address
            contributorAddressToClaimIds[c.contributors[i].addr].remove(claimId);
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
        notClaimed(claimId)
        notLocked(_claimRegistry[claimId].bountyId)
        onlyClaimContributor(claimId)
    {
        _claimRegistry[claimId].details = details;

        emit ClaimDetailsUpdated(claimId, details);
    }

    /// @inheritdoc IBountyManager
    function verifyClaim(uint claimId, Contributor[] calldata contributors)
        external
        onlyModuleRole(VERIFIER_ROLE)
        validClaimId(claimId)
        notClaimed(claimId)
        notLocked(_claimRegistry[claimId].bountyId)
    {
        contributorsNotChanged(claimId, contributors);

        Contributor[] memory contribs = _claimRegistry[claimId].contributors;

        uint length = contribs.length;

        //current contributor in loop
        Contributor memory contrib;

        //For each Contributor add payments according to the claimAmount specified
        for (uint i; i < length;) {
            contrib = contribs[i];

            _addPaymentOrder(
                PaymentOrder({
                    recipient: contrib.addr,
                    amount: contrib.claimAmount,
                    createdAt: block.timestamp,
                    cliff: 0,
                    end: block.timestamp // end Date is now
                })
            );
            unchecked {
                ++i;
            }
        }

        //when done process the Payments correctly
        __Module_orchestrator.paymentProcessor().processPayments(
            IERC20PaymentClient(address(this))
        );

        //Set completed to true
        _claimRegistry[claimId].claimed = true;

        emit ClaimVerified(claimId);
    }
}
