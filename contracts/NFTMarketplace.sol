// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC721URIStorage, Ownable {
    uint private _tokenIds;

    struct MarketItem {
        uint256 tokenId;
        uint256 royaltyBasisPoints; // Royalty in basis points (1 basis point = 0.01%)
        address creator;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
    }

    mapping(uint256 => MarketItem) private idToMarketItem;
    uint256 public listingFee = 0.025 ether;
    uint256 public defaultRoyaltyBasisPoints = 500; // Default royalty 5% in basis points

    event MarketItemCreated(
        uint256 indexed tokenId,
        address indexed creator,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        uint256 royaltyBasisPoints
    );

    event MarketItemListed(
        uint256 indexed tokenId,
        uint256 price
    );

    event NFTSold(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 price,
        uint256 royaltyAmount
    );

    event ListingFeeUpdated(
        uint256 newListingFee
    );

    event DefaultRoyaltyBasisPointsUpdated(
        uint256 newRoyaltyBasisPoints
    );

    constructor(address owner) Ownable(owner) ERC721("NFTMarketplace", "NFTM") {}

    function createToken(
        string memory tokenURI,
        uint256 price,
        uint256 royaltyBasisPoints
    ) public payable returns (uint) {
        require(msg.value == listingFee, "Price must be equal to listing fee");
        require(royaltyBasisPoints <= 10000, "Royalty basis points must be between 0 and 10,000");

        _tokenIds = ++_tokenIds;
        uint256 newTokenId = _tokenIds;

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        createMarketItem(newTokenId, price, royaltyBasisPoints);

        return newTokenId;
    }

    function createMarketItem(
        uint256 tokenId,
        uint256 price,
        uint256 royaltyBasisPoints
    ) private {
        require(price > 0, "Price must be at least 1 wei");
        require(royaltyBasisPoints <= 10000, "Royalty basis points must be between 0 and 10,000");

        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            royaltyBasisPoints,
            msg.sender,
            payable(address(0)),
            payable(address(0)),
            price,
            false
        );

        _transfer(msg.sender, address(this), tokenId);
        emit MarketItemCreated(tokenId, msg.sender, msg.sender, address(0), price, false, royaltyBasisPoints);
    }

    function listNFT(uint256 tokenId, uint256 price) public payable {
        MarketItem storage item = idToMarketItem[tokenId];
        require(item.owner == msg.sender, "Only item owner can perform this operation");
        require(msg.value == listingFee, "Price must be equal to listing fee");

        item.sold = false;
        item.price = price;
        item.seller = payable(msg.sender);
        item.owner = payable(address(0));

        _transfer(msg.sender, address(this), tokenId);
        emit MarketItemListed(tokenId, price);
    }

    function buyNFT(uint256 tokenId) public payable {
        MarketItem storage item = idToMarketItem[tokenId];
        uint256 price = item.price;
        address payable seller = item.seller;
        address creator = item.creator;
        uint256 royaltyBasisPoints = item.royaltyBasisPoints;

        require(msg.value == price, "Please submit the asking price to complete the purchase");

        uint256 royaltyAmount = (price * royaltyBasisPoints) / 10000;
        uint256 sellerAmount = price - royaltyAmount;

        item.owner = payable(msg.sender);
        item.sold = true;
        item.seller = payable(address(0));

        _transfer(address(this), msg.sender, tokenId);

        payable(owner()).transfer(listingFee); // Transfer listing fee to the owner
        if (creator != address(0) && royaltyBasisPoints > 0) {
            payable(creator).transfer(royaltyAmount); // Transfer royalty to the creator
        }
        payable(seller).transfer(sellerAmount); // Transfer the remaining amount to the seller

        emit NFTSold(tokenId, msg.sender, price, royaltyAmount);
    }

    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint itemCount = _tokenIds;
        uint unsoldItemCount = itemCount - _fetchMyNFTsCount();
        uint currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint i = 1; i <= itemCount; i++) {
            if (idToMarketItem[i].owner == address(0)) {
                MarketItem storage currentItem = idToMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint totalItemCount = _tokenIds;
        uint itemCount = 0;
        uint currentIndex = 0;

        for (uint i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == msg.sender) {
                uint currentId = i;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    function _fetchMyNFTsCount() private view returns (uint) {
        uint totalItemCount = _tokenIds;
        uint itemCount = 0;
        for (uint i = 1; i <= totalItemCount; i++) {
            if (idToMarketItem[i].owner == msg.sender) {
                itemCount += 1;
            }
        }
        return itemCount;
    }

    function getNFTDetails(uint256 tokenId) public view returns (MarketItem memory) {
        return idToMarketItem[tokenId];
    }

    function updateListingFee(uint256 _listingFee) public onlyOwner {
        listingFee = _listingFee;
        emit ListingFeeUpdated(_listingFee);
    }

    function updateDefaultRoyaltyBasisPoints(uint256 _royaltyBasisPoints) public onlyOwner {
        require(_royaltyBasisPoints <= 10000, "Royalty basis points must be between 0 and 10,000");
        defaultRoyaltyBasisPoints = _royaltyBasisPoints;
        emit DefaultRoyaltyBasisPointsUpdated(_royaltyBasisPoints);
    }
}
