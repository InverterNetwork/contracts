// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// External Dependencies
import "@oz/token/ERC721/ERC721.sol";
import "@oz/token/ERC721/extensions/ERC721URIStorage.sol";
import "@oz/access/Ownable.sol";

contract ERC721Mock is ERC721URIStorage, Ownable {
    uint private _nextTokenId;
    string public baseURI;

    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
        Ownable(msg.sender)
    {}

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

    function mint(address to) public onlyOwner returns (uint) {
        uint tokenId = _nextTokenId;
        _safeMint(to, tokenId);
        _nextTokenId++;

        return tokenId;
    }

    function setTokenURI(uint tokenId, string memory tokenURI)
        public
        onlyOwner
    {
        _setTokenURI(tokenId, tokenURI);
    }
}

// Mock contracts for testing hooks
contract MockHookContract {
    bool public hookExecuted;

    function executeHook() external {
        hookExecuted = true;
    }
}

contract MockFailingHookContract {
    function executeHook() external pure {
        revert("Hook execution failed");
    }
}
