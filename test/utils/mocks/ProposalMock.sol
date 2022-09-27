// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IProposal} from "src/interfaces/IProposal.sol";

import {Types} from "src/common/Types.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

import {AuthorizerMock} from "./AuthorizerMock.sol";

contract ProposalMock is IProposal {

    IAuthorizer _authorizer;

    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    ) external returns (bytes memory) {
        return "";
    
    }

    function isActiveModule(address module) external returns (bool){
        return true;
    }

    function authorizer() external view returns (IAuthorizer){
        return _authorizer;
    }
}
