// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title NFTSwap
 * @dev Smart contract for swapping ERC1155 and ERC721 tokens
 */
contract NFTSwap is ERC1155Holder, ERC721Holder, ReentrancyGuard, Ownable {
    using ERC165Checker for address;

    // Custom errors
    error ZeroAddress();
    error InvalidTokensLength();
    error NotSwapCreator();
    error SwapNotActive();
    error AlreadyExecuted();
    error AlreadyCancelled();
    error TokenTransferFailed();
    error InsufficientTokensOffered();
    error NotApprovedForToken();
    error NotTokenOwner();
    error SwapExpired();
    error InvalidValue();
    error InvalidStatus();
    error RecipientRejected();

    // NFT token type enum
    enum TokenType {
        ERC721,
        ERC1155
    }

    // Swap status enum
    enum SwapStatus {
        Active,
        Executed,
        Cancelled,
        Expired
    }

    // Struct to represent a token in a swap
    struct SwapToken {
        address tokenAddress;
        TokenType tokenType;
        uint256 tokenId;
        uint256 amount; // Only relevant for ERC1155
    }

    // Main swap struct to hold swap data
    struct Swap {
        address creator;
        address recipient; // Optional: can be address(0) for public swaps
        SwapToken[] tokensOffered;
        SwapToken[] tokensRequested;
        uint256 createdAt;
        uint256 expiresAt;
        uint256 ethValue; // Optional: additional ETH included in the swap
        SwapStatus status;
    }

    // Swap counter
    uint256 private _swapIdCounter = 1;

    // Mapping from swap ID to swap data
    mapping(uint256 => Swap) private _swaps;

    // Platform fee percentage (in basis points: 100 = 1%)
    uint256 public feePercentage = 100;

    // Fee recipient address
    address public feeRecipient;

    // Events
    event SwapCreated(
        uint256 indexed swapId,
        address indexed creator,
        address indexed recipient,
        uint256 ethValue,
        uint256 expiresAt
    );

    event SwapExecuted(
        uint256 indexed swapId,
        address indexed executor,
        uint256 timestamp
    );

    event SwapCancelled(
        uint256 indexed swapId,
        address indexed canceller,
        uint256 timestamp
    );

    event SwapExpiredEvent(uint256 indexed swapId);

    event FeePercentageUpdated(uint256 newFeePercentage);

    event FeeRecipientUpdated(address newFeeRecipient);

    /**
     * @dev Constructor
     * @param _feeRecipient Address that will receive the fees
     */
    constructor(address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Create a new swap offer
     * @param recipient Target recipient (must be a valid address)
     * @param tokensOffered Array of tokens offered by the creator
     * @param tokensRequested Array of tokens requested by the creator
     * @param expirationTime Time when the swap expires (0 for no expiration)
     */
    function createSwap(
        address recipient,
        SwapToken[] calldata tokensOffered,
        SwapToken[] calldata tokensRequested,
        uint256 expirationTime
    ) external payable nonReentrant returns (uint256) {
        if (tokensOffered.length == 0) revert InsufficientTokensOffered();
        if (tokensRequested.length == 0) revert InvalidTokensLength();
        if (recipient == address(0)) revert ZeroAddress();

        // Create new swap
        uint256 swapId = _swapIdCounter++;
        uint256 expiresAt = expirationTime > 0 ? expirationTime : 0;

        // Initialize the swap first without arrays
        _swaps[swapId].creator = msg.sender;
        _swaps[swapId].recipient = recipient;
        _swaps[swapId].createdAt = block.timestamp;
        _swaps[swapId].expiresAt = expiresAt;
        _swaps[swapId].ethValue = msg.value;
        _swaps[swapId].status = SwapStatus.Active;
        
        // Process and add offered tokens directly to storage
        for (uint256 i = 0; i < tokensOffered.length; i++) {
            // Validate and transfer tokens from creator to this contract
            _verifyOwnershipAndTransfer(
                tokensOffered[i].tokenAddress,
                tokensOffered[i].tokenId,
                tokensOffered[i].amount,
                tokensOffered[i].tokenType,
                msg.sender,
                address(this)
            );
            
            // Add to storage directly
            _swaps[swapId].tokensOffered.push(tokensOffered[i]);
        }
        
        // Add requested tokens directly to storage
        for (uint256 i = 0; i < tokensRequested.length; i++) {
            _swaps[swapId].tokensRequested.push(tokensRequested[i]);
        }

        emit SwapCreated(swapId, msg.sender, recipient, msg.value, expiresAt);

        return swapId;
    }

    /**
     * @dev Execute a swap by providing the requested tokens
     * @param swapId ID of the swap to execute
     */
    function executeSwap(uint256 swapId) external payable nonReentrant {
        Swap storage swap = _swaps[swapId];

        // Validate swap status
        if (swap.status != SwapStatus.Active) revert SwapNotActive();
        if (swap.expiresAt > 0 && swap.expiresAt < block.timestamp) {
            swap.status = SwapStatus.Expired;
            emit SwapExpiredEvent(swapId);
            revert SwapExpired();
        }

        // Check recipient
        if (swap.recipient != msg.sender) revert InvalidStatus();

        // Check ETH value if required
        if (swap.ethValue > 0) {
            if (msg.value != swap.ethValue) revert InvalidValue();
        }

        // Process fee if ETH is included
        uint256 feeAmount = 0;
        if (swap.ethValue > 0) {
            feeAmount = (swap.ethValue * feePercentage) / 10000;
            if (feeAmount > 0) {
                (bool feeSuccess, ) = feeRecipient.call{value: feeAmount}("");
                if (!feeSuccess) revert TokenTransferFailed();
            }
        }

        // Transfer requested tokens from executor to creator
        for (uint256 i = 0; i < swap.tokensRequested.length; i++) {
            SwapToken storage requestedToken = swap.tokensRequested[i];

            _verifyOwnershipAndTransfer(
                requestedToken.tokenAddress,
                requestedToken.tokenId,
                requestedToken.amount,
                requestedToken.tokenType,
                msg.sender,
                swap.creator
            );
        }

        // Transfer offered tokens from contract to executor
        for (uint256 i = 0; i < swap.tokensOffered.length; i++) {
            SwapToken storage offeredToken = swap.tokensOffered[i];

            _transferToken(
                offeredToken.tokenAddress,
                offeredToken.tokenId,
                offeredToken.amount,
                offeredToken.tokenType,
                address(this),
                msg.sender
            );
        }

        // Send ETH to the swap creator minus fee
        if (swap.ethValue > 0) {
            (bool ethSuccess, ) = swap.creator.call{
                value: swap.ethValue - feeAmount
            }("");
            if (!ethSuccess) revert TokenTransferFailed();
        }

        // Update swap status
        swap.status = SwapStatus.Executed;

        emit SwapExecuted(swapId, msg.sender, block.timestamp);
    }

    /**
     * @dev Cancel a swap (only callable by the creator)
     * @param swapId ID of the swap to cancel
     */
    function cancelSwap(uint256 swapId) external nonReentrant {
        Swap storage swap = _swaps[swapId];

        if (swap.creator != msg.sender) revert NotSwapCreator();
        if (swap.status != SwapStatus.Active) revert SwapNotActive();

        // Return offered tokens to creator
        for (uint256 i = 0; i < swap.tokensOffered.length; i++) {
            SwapToken memory token = swap.tokensOffered[i];

            _transferToken(
                token.tokenAddress,
                token.tokenId,
                token.amount,
                token.tokenType,
                address(this),
                swap.creator
            );
        }

        // Return ETH if any
        if (swap.ethValue > 0) {
            (bool success, ) = swap.creator.call{value: swap.ethValue}("");
            if (!success) revert TokenTransferFailed();
        }

        // Update swap status
        swap.status = SwapStatus.Cancelled;

        emit SwapCancelled(swapId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get swap details
     * @param swapId ID of the swap
     */
    function getSwap(
        uint256 swapId
    )
        external
        view
        returns (
            address creator,
            address recipient,
            SwapToken[] memory tokensOffered,
            SwapToken[] memory tokensRequested,
            uint256 createdAt,
            uint256 expiresAt,
            uint256 ethValue,
            SwapStatus status
        )
    {
        Swap storage swap = _swaps[swapId];
        return (
            swap.creator,
            swap.recipient,
            swap.tokensOffered,
            swap.tokensRequested,
            swap.createdAt,
            swap.expiresAt,
            swap.ethValue,
            swap.status
        );
    }

    /**
     * @dev Set fee percentage (only owner)
     * @param _feePercentage The new fee percentage (in basis points)
     */
    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > 1000) revert InvalidValue(); // Max 10%
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
     * @dev Verify ownership and approval before transferring
     */
    function _verifyOwnershipAndTransfer(
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        TokenType tokenType,
        address from,
        address to
    ) internal {
        if (tokenType == TokenType.ERC721) {
            // Verify ERC721 ownership
            if (IERC721(tokenAddress).ownerOf(tokenId) != from)
                revert NotTokenOwner();

            // Verify approval
            if (
                !IERC721(tokenAddress).isApprovedForAll(from, address(this)) &&
                IERC721(tokenAddress).getApproved(tokenId) != address(this)
            ) {
                revert NotApprovedForToken();
            }

            // Transfer token
            IERC721(tokenAddress).safeTransferFrom(from, to, tokenId);
        } else {
            // Verify ERC1155 ownership (via balance check)
            if (IERC1155(tokenAddress).balanceOf(from, tokenId) < amount)
                revert NotTokenOwner();

            // Verify approval
            if (!IERC1155(tokenAddress).isApprovedForAll(from, address(this))) {
                revert NotApprovedForToken();
            }

            // Transfer tokens
            IERC1155(tokenAddress).safeTransferFrom(
                from,
                to,
                tokenId,
                amount,
                ""
            );
        }
    }

    /**
     * @dev Transfer tokens based on type (simplified version for internal transfers)
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

    /**
     * @dev Function to receive ETH when msg.data is empty
     */
    receive() external payable {}
}
