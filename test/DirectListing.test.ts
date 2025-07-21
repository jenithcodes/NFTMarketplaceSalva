import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SalvaNFTMarketplace, MyERC1155, ERC1155Factory } from "../typechain-types";

describe("Direct Listing Tests", function () {
    // Test constants
    const LISTING_FEE = ethers.parseEther("0.001");
    const TOKEN_PRICE = ethers.parseEther("0.1");
    const ROYALTY_BP = 500; // 5%
    const TOKEN_QUANTITY = 100;
    const TOKEN_URI = "test-token-metadata.json";

    async function deployContractsFixture() {
        const [deployer, seller, buyer, feeRecipient] = await ethers.getSigners();

        // Deploy SalvaNFTMarketplace
        const MarketplaceFactory = await ethers.getContractFactory("SalvaNFTMarketplace");
        const marketplace = await MarketplaceFactory.deploy(LISTING_FEE, feeRecipient.address);
        await marketplace.waitForDeployment();

        // Deploy a placeholder auction for the factory
        const AuctionFactory = await ethers.getContractFactory("Auction");
        const auction = await AuctionFactory.deploy(feeRecipient.address);
        await auction.waitForDeployment();

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

        // Create a collection (no need to pass marketplace address anymore)
        const collectionName = "Test Collection";
        const collectionSymbol = "TC";
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
            marketplace,
            auction,
            erc1155,
            factory,
            deployer,
            seller,
            buyer,
            feeRecipient,
            collectionAddress
        };
    }

    describe("createERC1155DirectListing", function () {
        it("Should create a direct listing with correct parameters", async function () {
            const { marketplace, erc1155, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct listing
            const tx = await marketplace.connect(seller).createERC1155DirectListing(
                collectionAddress,
                1, // This will be ignored, actual token ID will be returned
                TOKEN_QUANTITY,
                TOKEN_PRICE,
                ROYALTY_BP,
                TOKEN_URI,
                { value: LISTING_FEE }
            );

            const receipt = await tx.wait();

            // Extract listing ID and token ID from events
            let listingId: bigint | undefined;
            let actualTokenId: bigint | undefined;

            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = marketplace.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "ListingCreated") {
                            listingId = parsedLog.args[0];
                            actualTokenId = parsedLog.args[2];
                            break;
                        }
                    } catch (error) {
                        // Continue to next log
                    }
                }
            }

            expect(listingId).to.not.be.undefined;
            expect(actualTokenId).to.not.be.undefined;

            // Verify listing details
            const listing = await marketplace.getListing(listingId!);
            expect(listing[0]).to.equal(collectionAddress); // tokenAddress
            expect(listing[1]).to.equal(actualTokenId); // tokenId
            expect(listing[2]).to.equal(seller.address); // seller
            expect(listing[3]).to.equal(seller.address); // creator
            expect(listing[4]).to.equal(TOKEN_PRICE); // price
            expect(listing[5]).to.equal(TOKEN_QUANTITY); // quantity
            expect(listing[6]).to.equal(ROYALTY_BP); // royaltyBasisPoints
            expect(listing[7]).to.be.true; // active
            expect(listing[8]).to.equal(1); // tokenType (ERC1155)

            // Verify tokens are in marketplace
            const marketplaceBalance = await erc1155.balanceOf(await marketplace.getAddress(), actualTokenId!);
            expect(marketplaceBalance).to.equal(TOKEN_QUANTITY);

            // Verify seller has no tokens
            const sellerBalance = await erc1155.balanceOf(seller.address, actualTokenId!);
            expect(sellerBalance).to.equal(0);

            // Verify token URI
            const tokenURI = await erc1155.uri(actualTokenId!);
            expect(tokenURI).to.equal(TOKEN_URI);
        });

        it("Should revert with insufficient listing fee", async function () {
            const { marketplace, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                marketplace.connect(seller).createERC1155DirectListing(
                    collectionAddress,
                    1,
                    TOKEN_QUANTITY,
                    TOKEN_PRICE,
                    ROYALTY_BP,
                    TOKEN_URI,
                    { value: ethers.parseEther("0.0005") } // Half the required fee
                )
            ).to.be.revertedWithCustomError(marketplace, "InsufficientFunds");
        });

        it("Should revert with zero price", async function () {
            const { marketplace, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                marketplace.connect(seller).createERC1155DirectListing(
                    collectionAddress,
                    1,
                    TOKEN_QUANTITY,
                    0, // Zero price
                    ROYALTY_BP,
                    TOKEN_URI,
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidPrice");
        });

        it("Should revert with zero quantity", async function () {
            const { marketplace, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                marketplace.connect(seller).createERC1155DirectListing(
                    collectionAddress,
                    1,
                    0, // Zero quantity
                    TOKEN_PRICE,
                    ROYALTY_BP,
                    TOKEN_URI,
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidQuantity");
        });

        it("Should revert with excessive royalty", async function () {
            const { marketplace, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            await expect(
                marketplace.connect(seller).createERC1155DirectListing(
                    collectionAddress,
                    1,
                    TOKEN_QUANTITY,
                    TOKEN_PRICE,
                    6000, // 60% royalty (exceeds 50% limit)
                    TOKEN_URI,
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidRoyalty");
        });

        it("Should handle zero royalty correctly", async function () {
            const { marketplace, erc1155, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            const tx = await marketplace.connect(seller).createERC1155DirectListing(
                collectionAddress,
                1,
                TOKEN_QUANTITY,
                TOKEN_PRICE,
                0, // Zero royalty
                TOKEN_URI,
                { value: LISTING_FEE }
            );

            const receipt = await tx.wait();
            
            // Extract listing ID from events
            let listingId: bigint | undefined;
            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = marketplace.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "ListingCreated") {
                            listingId = parsedLog.args[0];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            const listing = await marketplace.getListing(listingId!);
            // Should use default royalty from contract (2.5% = 250 basis points)
            expect(listing[6]).to.equal(250); // Default royalty from MyERC1155
        });

        it("Should create multiple listings with different token IDs", async function () {
            const { marketplace, erc1155, seller, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create first listing
            const tx1 = await marketplace.connect(seller).createERC1155DirectListing(
                collectionAddress,
                1,
                50,
                TOKEN_PRICE,
                ROYALTY_BP,
                "first-token.json",
                { value: LISTING_FEE }
            );

            // Create second listing
            const tx2 = await marketplace.connect(seller).createERC1155DirectListing(
                collectionAddress,
                1,
                75,
                ethers.parseEther("0.2"),
                300, // 3% royalty
                "second-token.json",
                { value: LISTING_FEE }
            );

            const receipt1 = await tx1.wait();
            const receipt2 = await tx2.wait();

            // Both should succeed and have different token IDs
            expect(receipt1).to.not.be.null;
            expect(receipt2).to.not.be.null;

            // Verify different token IDs were created
            const finalNextTokenId = await erc1155.getNextTokenId();
            expect(finalNextTokenId).to.equal(2); // Should be 2 (started at 0, created 2 tokens, next will be 2)
        });

        it("Should allow buying from direct listing", async function () {
            const { marketplace, erc1155, seller, buyer, collectionAddress } = await loadFixture(deployContractsFixture);

            // Create direct listing
            const tx = await marketplace.connect(seller).createERC1155DirectListing(
                collectionAddress,
                1,
                TOKEN_QUANTITY,
                TOKEN_PRICE,
                ROYALTY_BP,
                TOKEN_URI,
                { value: LISTING_FEE }
            );

            const receipt = await tx.wait();

            // Extract listing ID and token ID
            let listingId: bigint | undefined;
            let actualTokenId: bigint | undefined;

            if (receipt && receipt.logs) {
                for (const log of receipt.logs) {
                    try {
                        const parsedLog = marketplace.interface.parseLog({
                            topics: log.topics,
                            data: log.data
                        });
                        if (parsedLog && parsedLog.name === "ListingCreated") {
                            listingId = parsedLog.args[0];
                            actualTokenId = parsedLog.args[2];
                            break;
                        }
                    } catch (error) {
                        // Continue
                    }
                }
            }

            // Buy 10 tokens
            const buyQuantity = 10;
            const totalPrice = TOKEN_PRICE * BigInt(buyQuantity);
            
            await marketplace.connect(buyer).buyItem(listingId!, buyQuantity, { value: totalPrice });

            // Verify buyer received tokens
            const buyerBalance = await erc1155.balanceOf(buyer.address, actualTokenId!);
            expect(buyerBalance).to.equal(buyQuantity);

            // Verify marketplace balance decreased
            const marketplaceBalance = await erc1155.balanceOf(await marketplace.getAddress(), actualTokenId!);
            expect(marketplaceBalance).to.equal(TOKEN_QUANTITY - buyQuantity);

            // Verify listing is still active with reduced quantity
            const listing = await marketplace.getListing(listingId!);
            expect(listing[5]).to.equal(TOKEN_QUANTITY - buyQuantity); // remaining quantity
            expect(listing[7]).to.be.true; // still active
        });
    });
}); 