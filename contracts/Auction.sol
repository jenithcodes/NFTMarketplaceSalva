// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ERC1155Auction
 * @dev Smart contract for auctioning both ERC1155 and ERC721 tokens
 */
contract Auction is ERC1155Holder, ERC721Holder, ReentrancyGuard, Ownable {
    using ERC165Checker for address;

    // Custom errors
    error ZeroAddress();
    error InvalidPrice();
    error ReservePriceTooLow();
    error InvalidERC721Amount();
    error NotTokenOwner();
    error ContractNotApproved();
    error ZeroAmount();
    error InsufficientBalance();
    error ActiveAuctionExists();
    error AuctionNotActive();
    error AuctionEnded();
    error CannotBidOnOwnAuction();
    error BidBelowStartingPrice();
    error BidTooLow(uint256 bid, uint256 minRequired);
    error AuctionStillActive();
    error TransferFailed();
    error NoPendingReturns();
    error FeeExceedsMax();
    error BidIncrementZero();

    // Token type enums
    enum TokenType {
        ERC721,
        ERC1155
    }

    // Auction state enum
    enum AuctionState {
        Active,
        Ended,
        Cancelled
    }

    // Struct to hold auction data
    struct AuctionItem {
        uint256 tokenId;
        uint256 amount; // Only relevant for ERC1155
        address tokenAddress;
        TokenType tokenType;
        address seller;
        uint256 startingPrice;
        uint256 reservePrice;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        AuctionState state;
    }

    // Auction counter
    uint256 private _auctionIdCounter = 1;

    // Mapping from auction ID to auction item
    mapping(uint256 => AuctionItem) private _auctions;

    // Mapping from token address + token ID to auction ID
    // tokenAddress => tokenId => amount => auctionId
    mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
        private _tokenToAuction;

    // Mapping of address to their pending returns (after being outbid)
    mapping(address => uint256) private _pendingReturns;

    // Auction fee percentage (in basis points: 250 = 2.5%)
    uint256 public feePercentage = 250;

    // Fee recipient address
    address public feeRecipient;

    // Auction duration (7 days by default)
    uint256 public constant AUCTION_DURATION = 7 days;

    // Minimum bid increment (in basis points: 500 = 5%)
    uint256 public bidIncrementPercentage = 500;

    // Events
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 amount,
        TokenType tokenType,
        address seller,
        uint256 startingPrice,
        uint256 reservePrice,
        uint256 endTime
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );

    event AuctionComplete(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid,
        uint256 fee,
        uint256 royalty
    );

    event AuctionCancelled(uint256 indexed auctionId);

    event FeePercentageUpdated(uint256 newFeePercentage);

    event FeeRecipientUpdated(address newFeeRecipient);

    event BidIncrementUpdated(uint256 newBidIncrementPercentage);

    /**
     * @dev Constructor
     * @param _feeRecipient Address that will receive the fees
     */
    constructor(address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Create a new auction
     * @param tokenAddress The address of the token contract
     * @param tokenId The ID of the token
     * @param amount The amount of tokens (for ERC1155, use 1 for ERC721)
     * @param tokenType The type of token (0 for ERC721, 1 for ERC1155)
     * @param startingPrice The starting price of the auction
     * @param reservePrice The reserve price (minimum price to sell)
     */
    function createAuction(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        TokenType tokenType,
        uint256 startingPrice,
        uint256 reservePrice
    ) external nonReentrant {
        if (tokenAddress == address(0)) revert ZeroAddress();
        if (startingPrice == 0) revert InvalidPrice();
        if (reservePrice < startingPrice) revert ReservePriceTooLow();

        // For ERC721, amount should always be 1
        if (tokenType == TokenType.ERC721) {
            if (amount != 1) revert InvalidERC721Amount();

            // Check if sender owns the token
            if (IERC721(tokenAddress).ownerOf(tokenId) != msg.sender)
                revert NotTokenOwner();

            // Check if contract is approved to transfer the token
            if (
                !IERC721(tokenAddress).isApprovedForAll(
                    msg.sender,
                    address(this)
                ) && IERC721(tokenAddress).getApproved(tokenId) != address(this)
            ) {
                revert ContractNotApproved();
            }

            // Transfer the token to this contract
            IERC721(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        } else {
            // ERC1155
            if (amount == 0) revert ZeroAmount();

            // Check if sender has enough balance
            if (IERC1155(tokenAddress).balanceOf(msg.sender, tokenId) < amount)
                revert InsufficientBalance();

            // Check if contract is approved to transfer the tokens
            if (
                !IERC1155(tokenAddress).isApprovedForAll(
                    msg.sender,
                    address(this)
                )
            ) revert ContractNotApproved();

            // Transfer the tokens to this contract
            IERC1155(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId,
                amount,
                ""
            );
        }

        // Ensure no active auction exists for this token
        if (
            _tokenToAuction[tokenAddress][tokenId][amount] != 0 &&
            _auctions[_tokenToAuction[tokenAddress][tokenId][amount]].state ==
            AuctionState.Active
        ) {
            revert ActiveAuctionExists();
        }

        // Create new auction
        uint256 auctionId = _auctionIdCounter++;
        uint256 endTime = block.timestamp + AUCTION_DURATION;

        _auctions[auctionId] = AuctionItem({
            tokenId: tokenId,
            amount: amount,
            tokenAddress: tokenAddress,
            tokenType: tokenType,
            seller: msg.sender,
            startingPrice: startingPrice,
            reservePrice: reservePrice,
            highestBid: 0,
            highestBidder: address(0),
            endTime: endTime,
            state: AuctionState.Active
        });

        // Update token to auction mapping
        _tokenToAuction[tokenAddress][tokenId][amount] = auctionId;

        emit AuctionCreated(
            auctionId,
            tokenAddress,
            tokenId,
            amount,
            tokenType,
            msg.sender,
            startingPrice,
            reservePrice,
            endTime
        );
    }

    /**
     * @dev Place a bid on an auction
     * @param auctionId The ID of the auction
     */
    function placeBid(uint256 auctionId) external payable nonReentrant {
        AuctionItem storage auction = _auctions[auctionId];

        if (auction.state != AuctionState.Active) revert AuctionNotActive();
        if (block.timestamp >= auction.endTime) revert AuctionEnded();
        if (msg.sender == auction.seller) revert CannotBidOnOwnAuction();

        // If no previous bid, must be at least starting price
        if (auction.highestBid == 0) {
            if (msg.value < auction.startingPrice)
                revert BidBelowStartingPrice();
        } else {
            // Must outbid highest bidder by at least the increment percentage
            uint256 minBidIncrement = (auction.highestBid *
                bidIncrementPercentage) / 10000;
            uint256 minRequired = auction.highestBid + minBidIncrement;

            if (msg.value < minRequired)
                revert BidTooLow(msg.value, minRequired);
        }

        // Store the previous highest bidder to refund them
        address previousBidder = auction.highestBidder;
        uint256 previousBid = auction.highestBid;

        // Update auction with new highest bid
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;

        // Refund the previous highest bidder
        if (previousBidder != address(0)) {
            _pendingReturns[previousBidder] += previousBid;
        }

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /**
     * @dev End an auction after its end time
     * @param auctionId The ID of the auction
     */
    function endAuction(uint256 auctionId) external nonReentrant {
        AuctionItem storage auction = _auctions[auctionId];

        if (auction.state != AuctionState.Active) revert AuctionNotActive();
        if (block.timestamp < auction.endTime && msg.sender != auction.seller)
            revert AuctionStillActive();

        auction.state = AuctionState.Ended;

        // If there were no bids or reserve price not met, return the token to the seller
        if (
            auction.highestBidder == address(0) ||
            auction.highestBid < auction.reservePrice
        ) {
            _transferToken(
                auction.tokenAddress,
                auction.tokenId,
                auction.amount,
                auction.tokenType,
                address(this),
                auction.seller
            );

            // If there was a bidder but reserve not met, refund the highest bidder
            if (auction.highestBidder != address(0)) {
                _pendingReturns[auction.highestBidder] += auction.highestBid;
            }

            emit AuctionComplete(auctionId, address(0), 0, 0, 0);
            return;
        }

        // Calculate fee and royalty
        uint256 saleAmount = auction.highestBid;
        uint256 fee = (saleAmount * feePercentage) / 10000;
        uint256 royalty = 0;
        address royaltyRecipient = address(0);

        // Check for royalty support (ERC2981)
        if (
            auction.tokenAddress.supportsInterface(type(IERC2981).interfaceId)
        ) {
            (royaltyRecipient, royalty) = IERC2981(auction.tokenAddress)
                .royaltyInfo(auction.tokenId, saleAmount);

            // If there's a valid royalty, pay it out
            if (royaltyRecipient != address(0) && royalty > 0) {
                // Ensure the royalty is not more than the sale amount
                if (royalty > saleAmount - fee) {
                    royalty = saleAmount - fee;
                }

                // Transfer royalty to recipient
                if (royalty > 0) {
                    (bool royaltySuccess, ) = royaltyRecipient.call{
                        value: royalty
                    }("");
                    if (!royaltySuccess) revert TransferFailed();
                }
            }
        }

        // Transfer platform fee
        if (fee > 0) {
            (bool feeSuccess, ) = feeRecipient.call{value: fee}("");
            if (!feeSuccess) revert TransferFailed();
        }

        // Calculate seller amount (minus fee and royalty)
        uint256 sellerAmount = saleAmount - fee - royalty;

        // Transfer remaining funds to seller
        (bool sellerSuccess, ) = auction.seller.call{value: sellerAmount}("");
        if (!sellerSuccess) revert TransferFailed();

        // Transfer token to highest bidder
        _transferToken(
            auction.tokenAddress,
            auction.tokenId,
            auction.amount,
            auction.tokenType,
            address(this),
            auction.highestBidder
        );

        emit AuctionComplete(
            auctionId,
            auction.highestBidder,
            saleAmount,
            fee,
            royalty
        );
    }

    /**
     * @dev Cancel an auction (only callable by seller if no bids)
     * @param auctionId The ID of the auction
     */
    function cancelAuction(uint256 auctionId) external nonReentrant {
        AuctionItem storage auction = _auctions[auctionId];

        if (auction.state != AuctionState.Active) revert AuctionNotActive();
        if (msg.sender != auction.seller) revert NotTokenOwner();
        if (auction.highestBidder != address(0)) revert ActiveAuctionExists();

        auction.state = AuctionState.Cancelled;

        // Return the token to the seller
        _transferToken(
            auction.tokenAddress,
            auction.tokenId,
            auction.amount,
            auction.tokenType,
            address(this),
            auction.seller
        );

        emit AuctionCancelled(auctionId);
    }

    /**
     * @dev Withdraw pending returns (after being outbid)
     */
    function withdrawPendingReturns() external nonReentrant {
        uint256 amount = _pendingReturns[msg.sender];
        if (amount == 0) revert NoPendingReturns();

        // Zero out pending returns before sending to prevent reentrancy attacks
        _pendingReturns[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Get an auction by ID
     * @param auctionId The ID of the auction
     */
    function getAuction(
        uint256 auctionId
    ) external view returns (AuctionItem memory) {
        return _auctions[auctionId];
    }

    /**
     * @dev Get pending returns for an address
     * @param bidder The address to check
     */
    function getPendingReturns(address bidder) external view returns (uint256) {
        return _pendingReturns[bidder];
    }

    /**
     * @dev Set fee percentage (only owner)
     * @param _feePercentage The new fee percentage (in basis points)
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > 1000) revert FeeExceedsMax();
        feePercentage = _feePercentage;
        emit FeePercentageUpdated(_feePercentage);
    }

    /**
     * @dev Set fee recipient (only owner)
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @dev Set bid increment percentage (only owner)
     * @param _bidIncrementPercentage The new bid increment percentage (in basis points)
     */
    function setBidIncrementPercentage(
        uint256 _bidIncrementPercentage
    ) external onlyOwner {
        if (_bidIncrementPercentage == 0) revert BidIncrementZero();
        bidIncrementPercentage = _bidIncrementPercentage;
        emit BidIncrementUpdated(_bidIncrementPercentage);
    }

    /**
     * @dev Check if an interface is supported
     * @param interfaceId The interface ID to check
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Holder) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC1155).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal function to transfer tokens based on their type
     */
    function _transferToken(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        TokenType tokenType,
        address from,
        address to
    ) internal {
        if (tokenType == TokenType.ERC721) {
            IERC721(tokenAddress).safeTransferFrom(from, to, tokenId);
        } else {
            IERC1155(tokenAddress).safeTransferFrom(
                from,
                to,
                tokenId,
                amount,
                ""
            );
        }
    }
}
