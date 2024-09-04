// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Interfaces/INFTMarketplace.sol";

contract Auction is Ownable {
    INFTMarketplace public nftMarketplace;

    struct AuctionItem {
        uint256 tokenId;
        address seller;
        uint256 startingPrice;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        bool active;
    }

    mapping(uint256 => AuctionItem) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids; // tokenId => bidder => amount

    uint256 public constant MIN_AUCTION_DURATION = 1 days;
    uint256 public constant MAX_AUCTION_DURATION = 7 days;

    event AuctionCreated(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 startingPrice,
        uint256 endTime
    );
    event BidPlaced(
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount
    );
    event AuctionEnded(
        uint256 indexed tokenId,
        address indexed winner,
        uint256 amount
    );
    event AuctionCancelled(uint256 indexed tokenId);

    constructor(address _nftMarketplace, address owner) Ownable(owner) {
        nftMarketplace = INFTMarketplace(_nftMarketplace);
    }

    function createAuction(
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration
    ) public {
        require(
            nftMarketplace.ownerOf(tokenId) == msg.sender,
            "Only the owner can create an auction"
        );
        require(!auctions[tokenId].active, "Auction already active");
        require(
            duration >= MIN_AUCTION_DURATION &&
                duration <= MAX_AUCTION_DURATION,
            "Invalid auction duration"
        );

        // Transfer the NFT to the auction contract
        nftMarketplace.transferFrom(msg.sender, address(this), tokenId);

        auctions[tokenId] = AuctionItem({
            tokenId: tokenId,
            seller: msg.sender,
            startingPrice: startingPrice,
            highestBid: 0,
            highestBidder: address(0),
            endTime: block.timestamp + duration,
            active: true
        });

        emit AuctionCreated(
            tokenId,
            msg.sender,
            startingPrice,
            block.timestamp + duration
        );
    }

    function placeBid(uint256 tokenId) public payable {
        AuctionItem storage auction = auctions[tokenId];
        require(auction.active, "Auction is not active");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(
            msg.value > auction.highestBid && msg.value > auction.startingPrice,
            "Bid too low"
        );

        // Refund the previous highest bidder
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        bids[tokenId][msg.sender] = msg.value;

        emit BidPlaced(tokenId, msg.sender, msg.value);
    }

    function endAuction(uint256 tokenId) public {
        AuctionItem storage auction = auctions[tokenId];
        require(auction.active, "Auction is not active");
        require(block.timestamp >= auction.endTime, "Auction has not ended");
        require(
            auction.seller == msg.sender || auction.highestBidder == msg.sender,
            "Only seller or highest bidder can end auction"
        );

        auction.active = false;

        if (auction.highestBidder != address(0)) {
            // Transfer NFT to the highest bidder
            nftMarketplace.transferFrom(
                address(this),
                auction.highestBidder,
                tokenId
            );
            // Transfer the highest bid to the seller
            payable(auction.seller).transfer(auction.highestBid);

            emit AuctionEnded(
                tokenId,
                auction.highestBidder,
                auction.highestBid
            );
        } else {
            // If no bids were placed, return the NFT to the seller
            nftMarketplace.transferFrom(address(this), auction.seller, tokenId);
            emit AuctionCancelled(tokenId);
        }
    }

    function cancelAuction(uint256 tokenId) public {
        AuctionItem storage auction = auctions[tokenId];
        require(auction.active, "Auction is not active");
        require(auction.seller == msg.sender, "Only seller can cancel auction");
        require(block.timestamp < auction.endTime, "Auction has ended");

        auction.active = false;

        // Refund the highest bidder
        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.highestBid);
        }

        // Return the NFT to the seller
        nftMarketplace.transferFrom(address(this), auction.seller, tokenId);

        emit AuctionCancelled(tokenId);
    }

    function withdrawFunds(uint256 tokenId) public {
        uint256 amount = bids[tokenId][msg.sender];
        require(amount > 0, "No funds to withdraw");

        bids[tokenId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
}
