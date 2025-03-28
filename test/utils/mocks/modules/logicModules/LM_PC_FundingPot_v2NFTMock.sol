// // SPDX-License-Identifier: LGPL-3.0-only
// pragma solidity 0.8.23;

// // External Dependencies
// import "@oz/token/ERC721/ERC721.sol";
// import "@oz/token/ERC721/extensions/ERC721URIStorage.sol";
// import "@oz/access/Ownable.sol";
// import "@oz/utils/Counters.sol";

// contract MockNFT is ERC721URIStorage, Ownable {
//     using Counters for Counters.Counter;

//     Counters.Counter private _tokenIds;

//     string public baseURI;

//     constructor(string memory name, string memory symbol)
//         ERC721(name, symbol)
//         Ownable(msg.sender)
//     {}

//     function _baseURI() internal view override returns (string memory) {
//         return baseURI;
//     }

//     function setBaseURI(string memory newBaseURI) public onlyOwner {
//         baseURI = newBaseURI;
//     }

//     function mint(address to) public onlyOwner returns (uint) {
//         uint newTokenId = _tokenIds.current();
//         _safeMint(to, newTokenId);
//         _tokenIds.increment();

//         return newTokenId;
//     }

//     function setTokenURI(uint tokenId, string memory tokenURI)
//         public
//         onlyOwner
//     {
//         _setTokenURI(tokenId, tokenURI);
//     }
// }
