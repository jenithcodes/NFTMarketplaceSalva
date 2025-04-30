// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./utils/Counters.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BearerBondNFT
 * @dev ERC1155 NFT representing bearer bonds with interest redemption
 */
contract BearerBondNFT is ERC1155, AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Custom errors
    error InvalidPrice();
    error InvalidQuantity();
    error InvalidInterestRate();
    error BatchNotActive();
    error InsufficientAvailableSupply();
    error NotRedeemable();
    error AlreadyRedeemed();
    error NotBondOwner();
    error TransferFailed();
    error RedemptionPeriodNotReached();
    error InvalidBatchId();
    error ZeroAddress();

    // Bond batch structure
    struct BondBatch {
        uint256 batchId;
        uint256 price; // Price in wei
        uint256 totalQuantity; // Total bonds in this batch
        uint256 availableQuantity; // Remaining available bonds
        uint256 interestRate; // Interest rate in basis points (1% = 100)
        uint256 releaseTime; // Timestamp when this batch was released
        bool active; // If batch is currently active for sale
    }

    // Bond token tracking
    struct BondToken {
        uint256 purchaseTime; // When this token was originally purchased
        uint256 lastRedemptionTime; // Last time interest was redeemed (0 if never redeemed)
        address originalPurchaser; // The original purchaser of the token
    }

    // SALC token
    IERC20 public salcToken;

    // Batch ID counter
    Counters.Counter private _batchIdCounter;

    // Mapping from batch ID to bond batch data
    mapping(uint256 => BondBatch) public bondBatches;

    // Mapping from batch ID => token ID => bond token details
    mapping(uint256 => mapping(uint256 => BondToken)) private _bondTokens;

    // Mapping from batch ID => token ID => holder address => purchase time
    // This helps to track when a holder first acquired the token for UI purposes
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        private _holderAcquisitionTime;

    // Admin wallet that receives payment for bonds
    address public treasury;

    // Redemption period (30 days in seconds)
    uint256 public redemptionPeriod = 30 days;

    // Events
    event BatchCreated(
        uint256 indexed batchId,
        uint256 price,
        uint256 quantity,
        uint256 interestRate
    );
    event BatchUpdated(
        uint256 indexed batchId,
        uint256 price,
        uint256 interestRate
    );
    event BondPurchased(
        uint256 indexed batchId,
        address indexed buyer,
        uint256 tokenId,
        uint256 quantity
    );
    event InterestRedeemed(
        uint256 indexed batchId,
        address indexed redeemer,
        uint256 tokenId,
        uint256 interestAmount
    );
    event SalcTokenUpdated(address indexed newSalcToken);
    event TreasuryUpdated(address indexed newTreasury);
    event RedemptionPeriodUpdated(uint256 newPeriod);

    /**
     * @dev Constructor
     * @param uri_ Base URI for the bond metadata
     * @param salcTokenAddress Address of the SALC token contract (can be address(0) and set later)
     */
    constructor(string memory uri_, address salcTokenAddress) ERC1155(uri_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        // Set treasury to deployer initially
        treasury = msg.sender;

        // Only set SALC token if address is provided
        if (salcTokenAddress != address(0)) {
            salcToken = IERC20(salcTokenAddress);
        }
    }

    /**
     * @dev Create a new batch of bonds
     * @param price Price per bond in wei
     * @param quantity Total quantity of bonds in this batch
     * @param interestRate Interest rate in basis points (1% = 100)
     */
    function createBatch(
        uint256 price,
        uint256 quantity,
        uint256 interestRate
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        if (price == 0) revert InvalidPrice();
        if (quantity == 0) revert InvalidQuantity();
        if (interestRate == 0) revert InvalidInterestRate();

        uint256 batchId = _batchIdCounter.current();
        _batchIdCounter.increment();

        bondBatches[batchId] = BondBatch({
            batchId: batchId,
            price: price,
            totalQuantity: quantity,
            availableQuantity: quantity,
            interestRate: interestRate,
            releaseTime: block.timestamp,
            active: true
        });

        emit BatchCreated(batchId, price, quantity, interestRate);
        return batchId;
    }

    /**
     * @dev Update batch price and interest rate
     * @param batchId ID of the batch to update
     * @param price New price per bond
     * @param interestRate New interest rate
     */
    function updateBatch(
        uint256 batchId,
        uint256 price,
        uint256 interestRate
    ) external onlyRole(ADMIN_ROLE) {
        if (!bondBatches[batchId].active) revert BatchNotActive();
        if (price == 0) revert InvalidPrice();
        if (interestRate == 0) revert InvalidInterestRate();

        bondBatches[batchId].price = price;
        bondBatches[batchId].interestRate = interestRate;

        emit BatchUpdated(batchId, price, interestRate);
    }

    /**
     * @dev Activate or deactivate a batch
     * @param batchId ID of the batch
     * @param active New active status
     */
    function setBatchActive(
        uint256 batchId,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        if (batchId >= _batchIdCounter.current()) revert InvalidBatchId();
        bondBatches[batchId].active = active;
    }

    /**
     * @dev Purchase bonds from a batch
     * @param batchId ID of the batch to purchase from
     * @param quantity Number of bonds to purchase
     */
    function purchaseBonds(
        uint256 batchId,
        uint256 quantity
    ) external payable nonReentrant {
        BondBatch storage batch = bondBatches[batchId];

        if (!batch.active) revert BatchNotActive();
        if (quantity == 0) revert InvalidQuantity();
        if (batch.availableQuantity < quantity)
            revert InsufficientAvailableSupply();

        uint256 totalPrice = batch.price * quantity;
        if (msg.value != totalPrice) revert InvalidPrice();

        // Update available quantity
        batch.availableQuantity -= quantity;

        // Generate unique token ID for this purchase (can be different from batchId if needed)
        // Here we'll use the batch ID as the token ID for simplicity
        uint256 tokenId = batchId;

        // Record token details if first purchase of this token type
        if (_bondTokens[batchId][tokenId].purchaseTime == 0) {
            _bondTokens[batchId][tokenId] = BondToken({
                purchaseTime: block.timestamp,
                lastRedemptionTime: 0,
                originalPurchaser: msg.sender
            });
        }

        // Record acquisition time for this holder
        _holderAcquisitionTime[batchId][tokenId][msg.sender] = block.timestamp;

        // Mint the bonds to the buyer
        _mint(msg.sender, tokenId, quantity, "");

        // Forward funds to treasury
        (bool success, ) = treasury.call{value: msg.value}("");
        if (!success) revert TransferFailed();

        emit BondPurchased(batchId, msg.sender, tokenId, quantity);
    }

    /**
     * @dev Redeem interest for holding bonds for the redemption period
     * @param batchId Batch ID of the bonds
     * @param tokenId Token ID of the bonds
     */
    function redeemInterest(
        uint256 batchId,
        uint256 tokenId
    ) external nonReentrant {
        // Ensure SALC token is set
        if (address(salcToken) == address(0)) revert ZeroAddress();

        BondBatch storage batch = bondBatches[batchId];
        BondToken storage token = _bondTokens[batchId][tokenId];

        // Check ownership
        uint256 balance = balanceOf(msg.sender, tokenId);
        if (balance == 0) revert NotBondOwner();

        // Calculate reference time for eligibility (either token's last redemption or this holder's acquisition time)
        uint256 referenceTime = token.lastRedemptionTime > 0
            ? token.lastRedemptionTime
            : token.purchaseTime;

        // Get this holder's acquisition time, if available
        uint256 acquisitionTime = _holderAcquisitionTime[batchId][tokenId][
            msg.sender
        ];

        // If holder acquired it after the last redemption, use acquisition time as reference
        if (acquisitionTime > referenceTime) {
            referenceTime = acquisitionTime;
        }

        // Check if the redemption period has passed since reference time
        if (block.timestamp < referenceTime + redemptionPeriod) {
            revert RedemptionPeriodNotReached();
        }

        // Calculate number of full periods that can be redeemed
        uint256 periodsSinceLastRedemption = (block.timestamp - referenceTime) /
            redemptionPeriod;

        // Calculate interest amount for the periods
        // Interest = bond value * interest rate * periods * balance
        uint256 interestAmount = (batch.price *
            batch.interestRate *
            periodsSinceLastRedemption *
            balance) / 10000;

        // Update last redemption time
        token.lastRedemptionTime =
            referenceTime +
            (periodsSinceLastRedemption * redemptionPeriod);

        // Transfer the interest tokens
        bool success = salcToken.transfer(msg.sender, interestAmount);
        if (!success) revert TransferFailed();

        emit InterestRedeemed(batchId, msg.sender, tokenId, interestAmount);
    }

    /**
     * @dev Set the SALC token address
     * @param newSalcToken Address of the SALC token contract
     */
    function setSalcToken(address newSalcToken) external onlyRole(ADMIN_ROLE) {
        if (newSalcToken == address(0)) revert ZeroAddress();
        salcToken = IERC20(newSalcToken);
        emit SalcTokenUpdated(newSalcToken);
    }

    /**
     * @dev Set the treasury address that receives bond payments
     * @param newTreasury Address of the new treasury
     */
    function setTreasury(address newTreasury) external onlyRole(ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @dev Set the redemption period
     * @param newPeriod New redemption period in seconds
     */
    function setRedemptionPeriod(
        uint256 newPeriod
    ) external onlyRole(ADMIN_ROLE) {
        if (newPeriod == 0) revert InvalidQuantity();
        redemptionPeriod = newPeriod;
        emit RedemptionPeriodUpdated(newPeriod);
    }

    /**
     * @dev Check if a bond can be redeemed
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     * @param account Account to check
     */
    function canRedeem(
        uint256 batchId,
        uint256 tokenId,
        address account
    ) public view returns (bool) {
        if (address(salcToken) == address(0)) return false;

        // Check if holder owns any tokens
        if (balanceOf(account, tokenId) == 0) return false;

        BondToken storage token = _bondTokens[batchId][tokenId];

        // Reference time is either token's last redemption or holder's acquisition time
        uint256 referenceTime = token.lastRedemptionTime > 0
            ? token.lastRedemptionTime
            : token.purchaseTime;

        // Get holder's acquisition time, if available
        uint256 acquisitionTime = _holderAcquisitionTime[batchId][tokenId][
            account
        ];

        // If holder acquired it after the last redemption, use acquisition time
        if (acquisitionTime > referenceTime) {
            referenceTime = acquisitionTime;
        }

        // Must own tokens and redemption period passed since reference time
        return block.timestamp >= referenceTime + redemptionPeriod;
    }

    /**
     * @dev Get redemption countdown in seconds (how long until eligible)
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     * @param account Account to check
     */
    function getRedemptionCountdown(
        uint256 batchId,
        uint256 tokenId,
        address account
    ) external view returns (uint256) {
        // Check if holder owns any tokens
        if (balanceOf(account, tokenId) == 0) return 0;

        BondToken storage token = _bondTokens[batchId][tokenId];

        // Reference time is either token's last redemption or holder's acquisition time
        uint256 referenceTime = token.lastRedemptionTime > 0
            ? token.lastRedemptionTime
            : token.purchaseTime;

        // Get holder's acquisition time, if available
        uint256 acquisitionTime = _holderAcquisitionTime[batchId][tokenId][
            account
        ];

        // If holder acquired it after the last redemption, use acquisition time
        if (acquisitionTime > referenceTime) {
            referenceTime = acquisitionTime;
        }

        uint256 nextRedemptionTime = referenceTime + redemptionPeriod;

        if (block.timestamp >= nextRedemptionTime) {
            return 0; // Already eligible
        }

        return nextRedemptionTime - block.timestamp;
    }

    /**
     * @dev Get bond last redemption time (0 if never redeemed)
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     */
    function getLastRedemptionTime(
        uint256 batchId,
        uint256 tokenId
    ) external view returns (uint256) {
        return _bondTokens[batchId][tokenId].lastRedemptionTime;
    }

    /**
     * @dev Get acquisition time for a specific holder
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     * @param account Account to check
     */
    function getAcquisitionTime(
        uint256 batchId,
        uint256 tokenId,
        address account
    ) external view returns (uint256) {
        return _holderAcquisitionTime[batchId][tokenId][account];
    }

    /**
     * @dev Check if interest has been redeemed at least once
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     */
    function hasRedeemedBefore(
        uint256 batchId,
        uint256 tokenId
    ) external view returns (bool) {
        return _bondTokens[batchId][tokenId].lastRedemptionTime > 0;
    }

    /**
     * @dev Calculate unclaimed interest for holding a bond
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     * @param account Account to check
     */
    function calculateUnclaimedInterest(
        uint256 batchId,
        uint256 tokenId,
        address account
    ) external view returns (uint256) {
        uint256 balance = balanceOf(account, tokenId);
        if (balance == 0) return 0;

        BondBatch storage batch = bondBatches[batchId];
        BondToken storage token = _bondTokens[batchId][tokenId];

        // Reference time is either token's last redemption or holder's acquisition time
        uint256 referenceTime = token.lastRedemptionTime > 0
            ? token.lastRedemptionTime
            : token.purchaseTime;

        // Get holder's acquisition time, if available
        uint256 acquisitionTime = _holderAcquisitionTime[batchId][tokenId][
            account
        ];

        // If holder acquired it after the last redemption, use acquisition time
        if (acquisitionTime > referenceTime) {
            referenceTime = acquisitionTime;
        }

        // If not enough time has passed for redemption
        if (block.timestamp < referenceTime + redemptionPeriod) {
            return 0;
        }

        // Calculate number of full periods that can be redeemed
        uint256 periodsSinceLastRedemption = (block.timestamp - referenceTime) /
            redemptionPeriod;

        // Calculate interest amount
        return
            (batch.price *
                batch.interestRate *
                periodsSinceLastRedemption *
                balance) / 10000;
    }

    /**
     * @dev Get available bond quantity in batch
     * @param batchId Batch ID
     */
    function getAvailableBonds(
        uint256 batchId
    ) external view returns (uint256) {
        return bondBatches[batchId].availableQuantity;
    }

    /**
     * @dev Calculate current interest for holding a bond
     * @param batchId Batch ID of the bond
     * @param tokenId Token ID of the bond
     * @param account Account to check
     */
    function calculateInterest(
        uint256 batchId,
        uint256 tokenId,
        address account
    ) external view returns (uint256) {
        BondBatch storage batch = bondBatches[batchId];
        uint256 balance = balanceOf(account, tokenId);

        if (balance == 0) return 0;

        return (batch.price * batch.interestRate * balance) / 10000;
    }

    /**
     * @dev Withdraw any ETH sent directly to the contract (if any)
     */
    function withdrawETH() external onlyRole(ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = treasury.call{value: balance}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @dev Withdraw any ERC20 tokens sent directly to the contract (including SALC)
     * @param tokenAddress The address of the token to withdraw
     */
    function withdrawERC20(address tokenAddress) external onlyRole(ADMIN_ROLE) {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            bool success = token.transfer(treasury, balance);
            if (!success) revert TransferFailed();
        }
    }

    // Required override for AccessControl + ERC1155
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Allow contract to receive ETH
    receive() external payable {}

    /**
     * @dev Hook that is called before any token transfer
     */
    function _beforeTokenTransfer(
        address /* operator */,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory /* amounts */,
        bytes memory /* data */
    ) internal {
        // Skip minting (from == address(0)) and burning (to == address(0))
        if (from == address(0) || to == address(0)) {
            return;
        }

        // Record acquisition time for each token being transferred
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            // For ERC1155, we need to find the corresponding batch ID
            // In our simplified case, tokenId == batchId
            uint256 batchId = id;

            // Only update if token exists
            if (_bondTokens[batchId][id].purchaseTime > 0) {
                _holderAcquisitionTime[batchId][id][to] = block.timestamp;
            }
        }
    }
}
