// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title SalvaNFT Marketplace
 * @dev A gas-optimized marketplace for trading ERC721 and ERC1155 tokens
 * with ERC2981 royalty standard support
 */
contract SalvaNFTMarketplace is
    ERC721Holder,
    ERC1155Holder,
    ReentrancyGuard,
    Ownable
{
    using ERC165Checker for address;

    // Custom errors for gas optimization
    error InvalidPrice();
    error InsufficientFunds();
    error InvalidQuantity();
    error InvalidRoyalty();
    error NotOwner();
    error ItemSold();
    error ItemNotFound();
    error UnsupportedToken();
    error TransferFailed();
    error InvalidInterface();

    // Token Type using smaller uint to save gas
    enum TokenType {
        ERC721,
        ERC1155
    }

    // Optimized for storage packing (saves ~20k gas per listing)
    struct Listing {
        // Slot 1
        address tokenAddress;
        address payable seller;
        // Slot 2
        uint96 price; // Price per token - 96 bits is enough for very high values
        uint96 royaltyAmount; // Stored as absolute amount to save recalculation gas
        uint32 quantity; // Max quantity is 4.29 billion, more than enough
        uint16 royaltyBasisPoints; // Max 10000 (100%)
        uint8 tokenType; // 0 for ERC721, 1 for ERC1155
        bool active;
        // Slot 3
        uint256 tokenId;
        // Slot 4
        address creator; // Creator/royalty recipient
    }

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    // State variables
    uint256 public listingFee;
    uint256 private _listingIdCounter;
    address public feeRecipient;
    bool public respectERC2981; // Flag to determine if ERC2981 should be respected

    // Mappings for efficient lookups
    mapping(uint256 => Listing) private _listings;
    mapping(address => mapping(uint256 => uint256[])) private _tokenListings; // token -> tokenId -> listingIds
    mapping(address => uint256[]) private _sellerListings;

    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        address seller,
        uint256 price,
        uint256 quantity,
        uint8 tokenType
    );

    event ListingCancelled(uint256 indexed listingId);

    event ListingSold(
        uint256 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price,
        uint256 quantity
    );

    event RoyaltyPaid(
        uint256 indexed listingId,
        address indexed recipient,
        uint256 amount,
        bool fromERC2981
    );

    event ListingFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newRecipient);
    event ERC2981RespectUpdated(bool respect);

    constructor(
        uint256 initialFee,
        address initialOwner
    ) Ownable(initialOwner) {
        listingFee = initialFee;
        feeRecipient = initialOwner;
        _listingIdCounter = 1; // Start at 1 so 0 can be used to check existence
        respectERC2981 = true; // Default to respecting ERC2981
    }

    /**
     * @dev Creates a listing for an ERC721 token
     * @param tokenAddress Address of the ERC721 contract
     * @param tokenId Token ID
     * @param price Price in wei
     * @param royaltyBasisPoints Royalty percentage in basis points (100 = 1%)
     */
    function createERC721Listing(
        address tokenAddress,
        uint256 tokenId,
        uint96 price,
        uint16 royaltyBasisPoints
    ) external payable nonReentrant returns (uint256) {
        // Validate parameters
        if (price == 0) revert InvalidPrice();
        if (msg.value != listingFee) revert InsufficientFunds();
        if (royaltyBasisPoints > 5000) revert InvalidRoyalty(); // Max 50%
        if (!tokenAddress.supportsInterface(INTERFACE_ID_ERC721))
            revert InvalidInterface();

        // Transfer NFT to marketplace
        IERC721(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        // Get royalty information from ERC2981 if supported
        (address creator, uint16 adjustedRoyaltyBasisPoints) = _getRoyaltyInfo(
            tokenAddress,
            tokenId,
            price,
            royaltyBasisPoints
        );

        // Create listing
        return
            _createListing(
                tokenAddress,
                tokenId,
                price,
                1, // Quantity is always 1 for ERC721
                adjustedRoyaltyBasisPoints,
                TokenType.ERC721,
                creator
            );
    }

    /**
     * @dev Creates a listing for ERC1155 tokens
     * @param tokenAddress Address of the ERC1155 contract
     * @param tokenId Token ID
     * @param quantity Number of tokens to list
     * @param price Price per token in wei
     * @param royaltyBasisPoints Royalty percentage in basis points (100 = 1%)
     */
    function createERC1155Listing(
        address tokenAddress,
        uint256 tokenId,
        uint32 quantity,
        uint96 price,
        uint16 royaltyBasisPoints
    ) external payable nonReentrant returns (uint256) {
        // Validate parameters
        if (price == 0) revert InvalidPrice();
        if (msg.value != listingFee) revert InsufficientFunds();
        if (quantity == 0) revert InvalidQuantity();
        if (royaltyBasisPoints > 5000) revert InvalidRoyalty(); // Max 50%
        if (!tokenAddress.supportsInterface(INTERFACE_ID_ERC1155))
            revert InvalidInterface();

        // Transfer tokens to marketplace
        IERC1155(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            quantity,
            ""
        );

        // Get royalty information from ERC2981 if supported
        (address creator, uint16 adjustedRoyaltyBasisPoints) = _getRoyaltyInfo(
            tokenAddress,
            tokenId,
            price,
            royaltyBasisPoints
        );

        // Create listing
        return
            _createListing(
                tokenAddress,
                tokenId,
                price,
                quantity,
                adjustedRoyaltyBasisPoints,
                TokenType.ERC1155,
                creator
            );
    }

    /**
     * @dev Gets royalty info from ERC2981 if supported and enabled
     * @return creator Address of the royalty recipient
     * @return adjustedRoyaltyBasisPoints The royalty basis points to use
     */
    function _getRoyaltyInfo(
        address tokenAddress,
        uint256 tokenId,
        uint96 price,
        uint16 fallbackRoyaltyBasisPoints
    )
        internal
        view
        returns (address creator, uint16 adjustedRoyaltyBasisPoints)
    {
        creator = msg.sender; // Default to listing creator
        adjustedRoyaltyBasisPoints = fallbackRoyaltyBasisPoints;

        // Check if token supports ERC2981 and we should respect it
        if (
            respectERC2981 &&
            tokenAddress.supportsInterface(INTERFACE_ID_ERC2981)
        ) {
            try IERC2981(tokenAddress).royaltyInfo(tokenId, price) returns (
                address receiver,
                uint256 royaltyAmount
            ) {
                if (receiver != address(0)) {
                    // Calculate basis points from royalty amount
                    uint16 calculatedBasisPoints = uint16(
                        (royaltyAmount * BASIS_POINTS) / price
                    );

                    // Only use ERC2981 royalty if it's valid (not exceeding 50%)
                    if (calculatedBasisPoints <= 5000) {
                        creator = receiver;
                        adjustedRoyaltyBasisPoints = calculatedBasisPoints;
                    }
                }
            } catch {
                // Fallback to provided royalty if ERC2981 call fails
            }
        }

        return (creator, adjustedRoyaltyBasisPoints);
    }

    /**
     * @dev Internal function to create a listing
     */
    function _createListing(
        address tokenAddress,
        uint256 tokenId,
        uint96 price,
        uint32 quantity,
        uint16 royaltyBasisPoints,
        TokenType tokenType,
        address creator
    ) private returns (uint256) {
        uint256 listingId = _listingIdCounter++;
        uint96 royaltyAmount = uint96(
            (uint256(price) * royaltyBasisPoints) / BASIS_POINTS
        );

        // Create listing with packed storage
        _listings[listingId] = Listing({
            tokenAddress: tokenAddress,
            seller: payable(msg.sender),
            price: price,
            royaltyAmount: royaltyAmount,
            quantity: quantity,
            royaltyBasisPoints: royaltyBasisPoints,
            tokenType: uint8(tokenType),
            active: true,
            tokenId: tokenId,
            creator: creator
        });

        // Add to lookup mappings for efficient queries
        _tokenListings[tokenAddress][tokenId].push(listingId);
        _sellerListings[msg.sender].push(listingId);

        // Emit event
        emit ListingCreated(
            listingId,
            tokenAddress,
            tokenId,
            msg.sender,
            price,
            quantity,
            uint8(tokenType)
        );

        return listingId;
    }

    /**
     * @dev Buy tokens from a listing
     * @param listingId ID of the listing
     * @param quantity Number of tokens to buy (must be 1 for ERC721)
     */
    function buyItem(
        uint256 listingId,
        uint32 quantity
    ) external payable nonReentrant {
        // Load listing from storage (only once to save gas)
        Listing storage listing = _listings[listingId];

        // Validate listing and purchase
        if (!listing.active) revert ItemSold();
        if (quantity == 0 || quantity > listing.quantity)
            revert InvalidQuantity();

        // Calculate total price
        uint256 totalPrice = uint256(listing.price) * quantity;
        if (msg.value < totalPrice) revert InsufficientFunds();

        // Update listing
        if (quantity == listing.quantity) {
            listing.active = false;
        }
        listing.quantity -= quantity;

        // Transfer tokens to buyer
        if (listing.tokenType == uint8(TokenType.ERC721)) {
            // For ERC721, quantity must be 1
            if (quantity != 1) revert InvalidQuantity();
            IERC721(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
        } else {
            // For ERC1155
            IERC1155(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                quantity,
                ""
            );
        }

        // Distribute marketplace fee
        if (feeRecipient != address(0)) {
            (bool feeSuccess, ) = payable(feeRecipient).call{value: listingFee}(
                ""
            );
            if (!feeSuccess) revert TransferFailed();
        }

        // Emit sale event
        emit ListingSold(
            listingId,
            listing.tokenAddress,
            listing.tokenId,
            listing.seller,
            msg.sender,
            totalPrice,
            quantity
        );

        // Get fresh royalty info if we respect ERC2981 (allowing for royalty changes since listing)
        uint256 royaltyAmount;
        address royaltyRecipient;
        bool usedERC2981 = false;

        if (
            respectERC2981 &&
            listing.tokenAddress.supportsInterface(INTERFACE_ID_ERC2981)
        ) {
            try
                IERC2981(listing.tokenAddress).royaltyInfo(
                    listing.tokenId,
                    totalPrice
                )
            returns (address receiver, uint256 amount) {
                if (
                    receiver != address(0) &&
                    amount > 0 &&
                    amount <= totalPrice / 2
                ) {
                    royaltyRecipient = receiver;
                    royaltyAmount = amount;
                    usedERC2981 = true;
                }
            } catch {
                // Fall back to stored royalty info
                royaltyAmount = uint256(listing.royaltyAmount) * quantity;
                royaltyRecipient = listing.creator;
            }
        } else {
            // Use stored royalty info
            royaltyAmount = uint256(listing.royaltyAmount) * quantity;
            royaltyRecipient = listing.creator;
        }

        // Calculate seller amount
        uint256 sellerAmount = totalPrice - royaltyAmount;

        // Transfer funds to seller
        (bool sellerSuccess, ) = listing.seller.call{value: sellerAmount}("");
        if (!sellerSuccess) revert TransferFailed();

        // Transfer royalties if applicable
        if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
            (bool royaltySuccess, ) = payable(royaltyRecipient).call{
                value: royaltyAmount
            }("");
            if (royaltySuccess) {
                emit RoyaltyPaid(
                    listingId,
                    royaltyRecipient,
                    royaltyAmount,
                    usedERC2981
                );
            } else {
                // If royalty payment fails, send to seller instead
                (bool fallbackSuccess, ) = listing.seller.call{
                    value: royaltyAmount
                }("");
                if (!fallbackSuccess) revert TransferFailed();
            }
        }

        // Return excess payment if any
        uint256 excess = msg.value - totalPrice;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}(
                ""
            );
            if (!refundSuccess) revert TransferFailed();
        }
    }

    /**
     * @dev Cancel a listing
     * @param listingId ID of the listing
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = _listings[listingId];

        if (!listing.active) revert ItemSold();
        if (listing.seller != msg.sender) revert NotOwner();

        // Update listing state first
        listing.active = false;

        // Return tokens to seller
        if (listing.tokenType == uint8(TokenType.ERC721)) {
            IERC721(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
        } else {
            IERC1155(listing.tokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId,
                listing.quantity,
                ""
            );
        }

        emit ListingCancelled(listingId);
    }

    /**
     * @dev Update the listing fee
     * @param newFee New listing fee
     */
    function updateListingFee(uint256 newFee) external onlyOwner {
        listingFee = newFee;
        emit ListingFeeUpdated(newFee);
    }

    /**
     * @dev Update the fee recipient
     * @param newRecipient New fee recipient
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    /**
     * @dev Set whether to respect ERC2981 royalty standard
     * @param respect Whether to respect ERC2981
     */
    function setRespectERC2981(bool respect) external onlyOwner {
        respectERC2981 = respect;
        emit ERC2981RespectUpdated(respect);
    }

    /**
     * @dev Get a listing by ID
     * @param listingId ID of the listing
     */
    function getListing(
        uint256 listingId
    )
        external
        view
        returns (
            address tokenAddress,
            uint256 tokenId,
            address seller,
            address creator,
            uint96 price,
            uint32 quantity,
            uint16 royaltyBasisPoints,
            bool active,
            uint8 tokenType
        )
    {
        Listing memory listing = _listings[listingId];
        if (listing.seller == address(0)) revert ItemNotFound();

        return (
            listing.tokenAddress,
            listing.tokenId,
            listing.seller,
            listing.creator,
            listing.price,
            listing.quantity,
            listing.royaltyBasisPoints,
            listing.active,
            listing.tokenType
        );
    }

    /**
     * @dev Get all active listings
     * @param cursor Pagination cursor, 0 for first page
     * @param size Number of items per page
     * @return listingIds Array of listing IDs
     * @return nextCursor Next pagination cursor
     */
    function getActiveListings(
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory listingIds, uint256 nextCursor) {
        uint256 counter = 0;
        uint256 length = size;
        uint256 currentId = cursor == 0 ? 1 : cursor;

        // First pass: count valid listings to allocate array efficiently
        for (
            uint256 i = currentId;
            i < _listingIdCounter && counter < length;
            i++
        ) {
            if (_listings[i].active) {
                counter++;
            }
        }

        // Allocate exact size to save gas
        listingIds = new uint256[](counter);

        // Second pass: fill the array
        counter = 0;
        for (
            uint256 i = currentId;
            i < _listingIdCounter && counter < length;
            i++
        ) {
            if (_listings[i].active) {
                listingIds[counter] = i;
                counter++;
                nextCursor = i + 1;
            }
        }

        // If we've reached the end, set nextCursor to 0
        if (nextCursor >= _listingIdCounter) {
            nextCursor = 0;
        }

        return (listingIds, nextCursor);
    }

    /**
     * @dev Get all listings by a seller
     * @param seller Seller address
     */
    function getListingsBySeller(
        address seller
    ) external view returns (uint256[] memory) {
        return _sellerListings[seller];
    }

    /**
     * @dev Get all listings for a token
     * @param tokenAddress Token contract address
     * @param tokenId Token ID
     */
    function getListingsByToken(
        address tokenAddress,
        uint256 tokenId
    ) external view returns (uint256[] memory) {
        return _tokenListings[tokenAddress][tokenId];
    }

    /**
     * @dev Get current royalty information for a token, respecting ERC2981 if applicable
     * @param tokenAddress Token contract address
     * @param tokenId Token ID
     * @param price Price to calculate royalty from
     */
    function getRoyaltyInfo(
        address tokenAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        view
        returns (address recipient, uint256 amount, bool isFromERC2981)
    {
        isFromERC2981 = false;

        // Check for ERC2981 support
        if (
            respectERC2981 &&
            tokenAddress.supportsInterface(INTERFACE_ID_ERC2981)
        ) {
            try IERC2981(tokenAddress).royaltyInfo(tokenId, price) returns (
                address receiver,
                uint256 royaltyAmount
            ) {
                if (
                    receiver != address(0) &&
                    royaltyAmount > 0 &&
                    royaltyAmount <= price / 2
                ) {
                    return (receiver, royaltyAmount, true);
                }
            } catch {
                // Fall through to default handling
            }
        }

        // Find existing listing for this token
        uint256[] memory listings = _tokenListings[tokenAddress][tokenId];
        for (uint256 i = 0; i < listings.length; i++) {
            Listing memory listing = _listings[listings[i]];
            if (listing.active) {
                // Calculate royalty based on the listing's settings
                uint256 royaltyAmount = (price * listing.royaltyBasisPoints) /
                    BASIS_POINTS;
                return (listing.creator, royaltyAmount, false);
            }
        }

        // Default to zero royalty if no active listing found
        return (address(0), 0, false);
    }

    /**
     * @dev IERC165 support
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
