// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC721
 * @dev Simple ERC721 mock for testing
 */
contract MockERC721 is ERC721, Ownable {
    // Token counter
    uint256 private _tokenIdCounter;
    
    // Token URI mapping
    mapping(uint256 => string) private _tokenURIs;
    
    // Royalty info mapping
    mapping(uint256 => RoyaltyInfo) private _royalties;
    
    struct RoyaltyInfo {
        address receiver;
        uint96 royaltyFraction;
    }

    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {}

    function mint(address to, string memory uri) public returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _mint(to, tokenId);
        _tokenURIs[tokenId] = uri;
        
        return tokenId;
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public {
        _royalties[tokenId] = RoyaltyInfo(receiver, feeNumerator);
    }
    
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }
    
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256) {
        RoyaltyInfo memory royalty = _royalties[tokenId];
        
        if (royalty.receiver == address(0)) {
            return (address(0), 0);
        }
        
        return (royalty.receiver, (salePrice * royalty.royaltyFraction) / 10000);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        // 0x2a55205a is the interfaceId for ERC2981
        return interfaceId == 0x2a55205a || super.supportsInterface(interfaceId);
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
} 