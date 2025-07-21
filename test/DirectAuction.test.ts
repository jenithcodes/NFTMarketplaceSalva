import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { Auction, MyERC1155, ERC1155Factory } from "../typechain-types";

describe("Direct Auction Tests", function () {
    // Test constants
    const STARTING_PRICE = ethers.parseEther("0.05");
    const RESERVE_PRICE = ethers.parseEther("0.1");
    const TOKEN_QUANTITY = 50;
    const TOKEN_URI = "test-auction-metadata.json";
    const AUCTION_DURATION = 7 * 24 * 60 * 60; // 7 days in seconds

    async function deployContractsFixture() {
        const [deployer, seller, bidder1, bidder2, feeRecipient] = await ethers.getSigners();

        // Deploy Auction contract
        const AuctionFactory = await ethers.getContractFactory("Auction");
        const auction = await AuctionFactory.deploy(feeRecipient.address);
        await auction.waitForDeployment();

        // Deploy a placeholder marketplace for the factory (can be zero address for testing)
        const MarketplaceFactory = await ethers.getContractFactory("SalvaNFTMarketplace");
        const marketplace = await MarketplaceFactory.deploy(ethers.parseEther("0.001"), feeRecipient.address);
        await marketplace.waitForDeployment();

        // Deploy MyERC1155 implementation
        const MyERC1155Factory = await ethers.getContractFactory("MyERC1155");
        const implementation = await MyERC1155Factory.deploy();
        await implementation.waitForDeployment();

        // Deploy ERC1155Factory with both marketplace and auction addresses
        const ERC1155FactoryContract = await ethers.getContractFactory("ERC1155Factory");
        const factory = await ERC1155FactoryContract.deploy(
            await implementation.getAddress(),
            await marketplace.getAddress(),
            await auction.getAddress()
        );
        await factory.waitForDeployment();

        // Create a collection (no need to pass marketplace/auction address anymore)
        const collectionName = "Test Auction Collection";
        const collectionSymbol = "TAC";
        const baseURI = "https://api.example.com/metadata/";
        const contractURI = "https://api.example.com/collection-metadata.json";

        await factory.createCollection(
            collectionName,
            collectionSymbol,
            baseURI,
            contractURI
        );

        const collectionsCount = await factory.collectionsCount();
        const collection = await factory.getCollection(collectionsCount - 1n);
        const collectionAddress = collection.contractAddress;

        const erc1155 = await ethers.getContractAt("MyERC1155", collectionAddress);

        return {
            auction,
            marketplace,
            erc1155,
            factory,
            deployer,
            seller,
            bidder1,
            bidder2,
            feeRecipient,
            collectionAddress
        };
    }

    describe("createAuctionDirect", function () {
        it("Should create a direct auction with correct parameters", async function () {
            const { auction, erc1155, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1, // TokenType.ERC1155
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID and token ID from events
            let auctionId: bigint | undefined;
            let actualTokenId: bigint | undefined;

            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            actualTokenId = parsedLog.args[2];
                            break;
                        }
                    } catch (error) {
                        // Continue to next log
                    }
                }
            }

            expect(auctionId).to.not.be.undefined;
            expect(actualTokenId).to.not.be.undefined;

            // Verify auction details
            const auctionDetails = await auction.getAuction(auctionId!);
            expect(auctionDetails.tokenId).to.equal(actualTokenId);
            expect(auctionDetails.amount).to.equal(TOKEN_QUANTITY);
            expect(auctionDetails.tokenAddress).to.equal(collectionAddress);
            expect(auctionDetails.tokenType).to.equal(1); // ERC1155
            expect(auctionDetails.seller).to.equal(seller.address);
            expect(auctionDetails.startingPrice).to.equal(STARTING_PRICE);
            expect(auctionDetails.reservePrice).to.equal(RESERVE_PRICE);
            expect(auctionDetails.highestBid).to.equal(0);
            expect(auctionDetails.highestBidder).to.equal(ethers.ZeroAddress);
            expect(auctionDetails.state).to.equal(0); // Active

            // Verify tokens are in auction contract
            const auctionBalance = await erc1155.balanceOf(await auction.getAddress(), actualTokenId!);
            expect(auctionBalance).to.equal(TOKEN_QUANTITY);

            // Verify seller has no tokens
            const sellerBalance = await erc1155.balanceOf(seller.address, actualTokenId!);
            expect(sellerBalance).to.equal(0);

            // Verify token URI
            const tokenURI = await erc1155.uri(actualTokenId!);
            expect(tokenURI).to.equal(TOKEN_URI);
        });

        it("Should revert with zero address", async function () {
            const { auction, seller } = await loadFixture(deployContractsFixture);

            await expect(
                auction.connect(seller).createAuctionDirect(
                    ethers.ZeroAddress, // Invalid address
                    TOKEN_QUANTITY,
                    1,
                    STARTING_PRICE,
                    RESERVE_PRICE,
                    TOKEN_URI
                )
            ).to.be.revertedWithCustomError(auction, "ZeroAddress");
        });

        it("Should revert with zero starting price", async function () {
            const { auction, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                auction.connect(seller).createAuctionDirect(
                    collectionAddress,
                    TOKEN_QUANTITY,
                    1,
                    0, // Zero starting price
                    RESERVE_PRICE,
                    TOKEN_URI
                )
            ).to.be.revertedWithCustomError(auction, "InvalidPrice");
        });

        it("Should revert with reserve price lower than starting price", async function () {
            const { auction, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                auction.connect(seller).createAuctionDirect(
                    collectionAddress,
                    TOKEN_QUANTITY,
                    1,
                    STARTING_PRICE,
                    ethers.parseEther("0.01"), // Reserve price lower than starting price
                    TOKEN_URI
                )
            ).to.be.revertedWithCustomError(auction, "ReservePriceTooLow");
        });

        it("Should revert with zero amount", async function () {
            const { auction, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                auction.connect(seller).createAuctionDirect(
                    collectionAddress,
                    0, // Zero amount
                    1,
                    STARTING_PRICE,
                    RESERVE_PRICE,
                    TOKEN_URI
                )
            ).to.be.revertedWithCustomError(auction, "ZeroAmount");
        });

        it("Should allow bidding on direct auction", async function () {
            const { auction, erc1155, seller, bidder1, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID
            let auctionId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Place a bid above starting price
            const bidAmount = ethers.parseEther("0.07");
            await expect(
                auction.connect(bidder1).placeBid(auctionId!, { value: bidAmount })
            ).to.emit(auction, "BidPlaced")
             .withArgs(auctionId, bidder1.address, bidAmount);

            // Verify auction updated
            const auctionDetails = await auction.getAuction(auctionId!);
            expect(auctionDetails.highestBid).to.equal(bidAmount);
            expect(auctionDetails.highestBidder).to.equal(bidder1.address);
        });

        it("Should reject bid below starting price", async function () {
            const { auction, seller, bidder1, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID
            let auctionId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Try to bid below starting price
            const bidAmount = ethers.parseEther("0.01");
            await expect(
                auction.connect(bidder1).placeBid(auctionId!, { value: bidAmount })
            ).to.be.revertedWithCustomError(auction, "BidBelowStartingPrice");
        });

        it("Should reject bid from seller", async function () {
            const { auction, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID
            let auctionId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Seller tries to bid on own auction
            const bidAmount = ethers.parseEther("0.07");
            await expect(
                auction.connect(seller).placeBid(auctionId!, { value: bidAmount })
            ).to.be.revertedWithCustomError(auction, "CannotBidOnOwnAuction");
        });

        it("Should handle multiple bidders correctly", async function () {
            const { auction, seller, bidder1, bidder2, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID
            let auctionId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // First bid
            const bid1 = ethers.parseEther("0.07");
            await auction.connect(bidder1).placeBid(auctionId!, { value: bid1 });

            // Second bid (must be higher)
            const bid2 = ethers.parseEther("0.08");
            await auction.connect(bidder2).placeBid(auctionId!, { value: bid2 });

            // Verify second bidder is highest
            const auctionDetails = await auction.getAuction(auctionId!);
            expect(auctionDetails.highestBid).to.equal(bid2);
            expect(auctionDetails.highestBidder).to.equal(bidder2.address);

            // Verify first bidder has pending returns
            const pendingReturns = await auction.getPendingReturns(bidder1.address);
            expect(pendingReturns).to.equal(bid1);
        });

        it("Should end auction successfully after time expires", async function () {
            const { auction, erc1155, seller, bidder1, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID and token ID
            let auctionId: bigint | undefined;
            let actualTokenId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            actualTokenId = parsedLog.args[2];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Place bid above reserve price
            const bidAmount = ethers.parseEther("0.15");
            await auction.connect(bidder1).placeBid(auctionId!, { value: bidAmount });

            // Fast forward time past auction end
            await time.increase(AUCTION_DURATION + 1);

            // End auction
            await expect(
                auction.endAuction(auctionId!)
            ).to.emit(auction, "AuctionComplete");

            // Verify auction ended
            const auctionDetails = await auction.getAuction(auctionId!);
            expect(auctionDetails.state).to.equal(1); // Ended

            // Verify tokens transferred to winner
            const bidderBalance = await erc1155.balanceOf(bidder1.address, actualTokenId!);
            expect(bidderBalance).to.equal(TOKEN_QUANTITY);

            // Verify auction contract has no tokens
            const auctionBalance = await erc1155.balanceOf(await auction.getAddress(), actualTokenId!);
            expect(auctionBalance).to.equal(0);
        });

        it("Should return tokens to seller if reserve not met", async function () {
            const { auction, erc1155, seller, bidder1, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct auction
            const tx = await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                TOKEN_QUANTITY,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                TOKEN_URI
            );

            const receipt = await tx.wait();

            // Extract auction ID and token ID
            let auctionId: bigint | undefined;
            let actualTokenId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = auction.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "AuctionCreated") {
                            auctionId = parsedLog.args[0];
                            actualTokenId = parsedLog.args[2];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Place bid below reserve price
            const bidAmount = ethers.parseEther("0.07"); // Below reserve of 0.1 ETH
            await auction.connect(bidder1).placeBid(auctionId!, { value: bidAmount });

            // Fast forward time past auction end
            await time.increase(AUCTION_DURATION + 1);

            // End auction
            await auction.endAuction(auctionId!);

            // Verify tokens returned to seller
            const sellerBalance = await erc1155.balanceOf(seller.address, actualTokenId!);
            expect(sellerBalance).to.equal(TOKEN_QUANTITY);

            // Verify bidder can withdraw their bid
            const pendingReturns = await auction.getPendingReturns(bidder1.address);
            expect(pendingReturns).to.equal(bidAmount);
        });

        it("Should create multiple auctions with different token IDs", async function () {
            const { auction, erc1155, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create first auction
            await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                25,
                1,
                STARTING_PRICE,
                RESERVE_PRICE,
                "first-auction.json"
            );

            // Create second auction
            await auction.connect(seller).createAuctionDirect(
                collectionAddress,
                30,
                1,
                ethers.parseEther("0.08"),
                ethers.parseEther("0.15"),
                "second-auction.json"
            );

            // Verify different token IDs were created
            const nextTokenId = await erc1155.getNextTokenId();
            expect(nextTokenId).to.equal(2); // Should be 2 (started at 0, created 2 tokens, next will be 2)
        });
    });
}); 