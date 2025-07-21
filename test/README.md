# Test Documentation

This directory contains comprehensive test suites for the NFT Marketplace smart contracts.

## Test Files

### DirectListing.test.ts

Tests for the `createERC1155DirectListing` functionality in the `SalvaNFTMarketplace` contract.

**Test Coverage:**
- ✅ Creates direct listings with correct parameters
- ✅ Validates listing fee requirements
- ✅ Handles price validation (rejects zero price)
- ✅ Handles quantity validation (rejects zero quantity)
- ✅ Validates royalty limits (rejects >50%)
- ✅ Handles zero royalty correctly (uses contract default)
- ✅ Creates multiple listings with unique token IDs
- ✅ Supports buying from direct listings

**Key Features Tested:**
- Token creation and automatic transfer to marketplace
- Event emission and parameter validation
- Integration with ERC1155Factory and MyERC1155
- Royalty handling and marketplace fees
- NFT ownership transfers during purchase

### DirectAuction.test.ts

Tests for the `createAuctionDirect` functionality in the `Auction` contract.

**Test Coverage:**
- ✅ Creates direct auctions with correct parameters
- ✅ Validates contract address (rejects zero address)
- ✅ Validates pricing (rejects zero starting price)
- ✅ Validates reserve price (must be >= starting price)
- ✅ Validates quantity (rejects zero amount)
- ✅ Supports bidding functionality
- ✅ Rejects bids below starting price
- ✅ Prevents seller from bidding on own auction
- ✅ Handles multiple bidders correctly
- ✅ Processes auction completion after time expires
- ✅ Returns tokens to seller if reserve not met
- ✅ Creates multiple auctions with unique token IDs

**Key Features Tested:**
- Token creation and automatic transfer to auction contract
- Bidding mechanics and validation
- Time-based auction expiration
- Reserve price handling
- Token transfer on auction completion
- Refund mechanisms for outbid participants

## Running Tests

```bash
# Run all tests
npx hardhat test

# Run specific test files
npx hardhat test test/DirectListing.test.ts
npx hardhat test test/DirectAuction.test.ts

# Run both direct functionality tests
npx hardhat test test/DirectListing.test.ts test/DirectAuction.test.ts
```

## Test Architecture

Both test suites use:
- **Hardhat Network Helpers**: For `loadFixture` and `time` manipulation
- **Chai Assertions**: For comprehensive test expectations
- **Fixture Pattern**: For consistent contract deployment and setup
- **Event Testing**: To verify correct event emission
- **Error Testing**: To ensure proper validation and error handling

## Contract Integration

The tests validate the integration between:
- `SalvaNFTMarketplace` ↔ `MyERC1155` (for listings)
- `Auction` ↔ `MyERC1155` (for auctions)
- `ERC1155Factory` ↔ `MyERC1155` (for collection creation)

## Key Test Patterns

1. **Fixture-based Setup**: Each test starts with fresh contract deployments
2. **Event Parsing**: Extracting token IDs and listing/auction IDs from transaction logs
3. **Balance Verification**: Checking token ownership transfers
4. **Time Manipulation**: Testing time-dependent auction functionality
5. **Multi-user Scenarios**: Testing interactions between different user roles

All tests pass successfully and provide comprehensive coverage of the direct token creation and marketplace listing/auction functionality. 