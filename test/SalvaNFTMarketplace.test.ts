import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Contract } from "ethers";

describe("SalvaNFTMarketplace", function () {
    // Constants 
    const LISTING_FEE = ethers.parseEther("0.01");  // 0.01 ETH listing fee
    const TOKEN_PRICE = ethers.parseEther("0.5");   // 0.5 ETH token price
    const ROYALTY_BP = 500;                        // 5% royalty (500 basis points)

    // Test fixture
    async function deployMarketplaceFixture() {
        // Get signers
        const [owner, seller, buyer, royaltyRecipient] = await ethers.getSigners();

        // Deploy the marketplace
        const SalvaNFTMarketplace = await ethers.getContractFactory("SalvaNFTMarketplace");
        const marketplace = await SalvaNFTMarketplace.deploy(LISTING_FEE, owner.address);

        // Deploy test ERC1155 contract
        const MyERC1155 = await ethers.getContractFactory("MyERC1155");
        const erc1155 = await MyERC1155.deploy();

        await erc1155.initialize(
            "https://example.com/metadata/",
            "Test Collection",
            "TEST",
            seller.address
        );

        // Create tokens (using the updated methods)
        await erc1155.connect(seller).createToken(100, "https://example.com/token/1");

        // Add back the ERC1155 royalty setting
        // Setup royalties
        await erc1155.connect(seller).setTokenRoyalty(1, royaltyRecipient.address, ROYALTY_BP);

        // Deploy test ERC721 contract with updated constructor
        const MockERC721 = await ethers.getContractFactory("MockERC721");
        const erc721 = (await MockERC721.deploy("Test ERC721", "TEST721")) as any;
        
        // Mint directly to seller instead of transferring ownership
        await erc721.mint(seller.address, "https://example.com/token/721/1");
        await erc721.mint(seller.address, "https://example.com/token/721/2");
        // Set up royalties for both tokens
        await erc721.setTokenRoyalty(0, royaltyRecipient.address, ROYALTY_BP);
        await erc721.setTokenRoyalty(1, royaltyRecipient.address, ROYALTY_BP);

        // Approve the marketplace to transfer tokens
        await erc1155.connect(seller).setApprovalForAll(marketplace.target, true);
        await erc721.connect(seller).setApprovalForAll(marketplace.target, true);

        return {
            marketplace,
            erc1155,
            erc721,
            owner,
            seller,
            buyer,
            royaltyRecipient
        };
    }

    describe("Marketplace Deployment", function () {
        it("Should deploy with correct parameters", async function () {
            const { marketplace, owner } = await loadFixture(deployMarketplaceFixture);

            expect(await marketplace.listingFee()).to.equal(LISTING_FEE);
            expect(await marketplace.feeRecipient()).to.equal(owner.address);
            expect(await marketplace.respectERC2981()).to.be.true;
            expect(await marketplace.owner()).to.equal(owner.address);
        });
    });

    describe("ERC1155 Listings", function () {
        it("Should create ERC1155 listing with correct parameters", async function () {
            const { marketplace, erc1155, seller } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await expect(
                marketplace.connect(seller).createERC1155Listing(
                    erc1155.target,
                    1, // token ID
                    10, // quantity
                    TOKEN_PRICE, // price per token
                    ROYALTY_BP, // royalty basis points
                    { value: LISTING_FEE }
                )
            ).to.emit(marketplace, "ListingCreated")
                .withArgs(
                    1, // listing ID
                    erc1155.target,
                    1, // token ID
                    seller.address,
                    TOKEN_PRICE,
                    10, // quantity
                    1 // tokenType = ERC1155
                );

            // Check token was transferred to marketplace
            expect(await erc1155.balanceOf(marketplace.target, 1)).to.equal(10);
        });

        it("Should revert when listing fee is insufficient", async function () {
            const { marketplace, erc1155, seller } = await loadFixture(deployMarketplaceFixture);

            await expect(
                marketplace.connect(seller).createERC1155Listing(
                    erc1155.target,
                    1, // token ID
                    10, // quantity
                    TOKEN_PRICE, // price per token 
                    ROYALTY_BP, // royalty basis points
                    { value: ethers.parseEther("0.005") } // Half of required fee
                )
            ).to.be.revertedWithCustomError(marketplace, "InsufficientFunds");
        });

        it("Should revert with invalid parameters", async function () {
            const { marketplace, erc1155, seller } = await loadFixture(deployMarketplaceFixture);

            // Zero price
            await expect(
                marketplace.connect(seller).createERC1155Listing(
                    erc1155.target,
                    1,
                    10,
                    0, // zero price
                    ROYALTY_BP,
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidPrice");

            // Zero quantity
            await expect(
                marketplace.connect(seller).createERC1155Listing(
                    erc1155.target,
                    1,
                    0, // zero quantity
                    TOKEN_PRICE,
                    ROYALTY_BP,
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidQuantity");

            // Excessive royalty (over 50%)
            await expect(
                marketplace.connect(seller).createERC1155Listing(
                    erc1155.target,
                    1,
                    10,
                    TOKEN_PRICE,
                    5100, // 51% royalty
                    { value: LISTING_FEE }
                )
            ).to.be.revertedWithCustomError(marketplace, "InvalidRoyalty");
        });
    });

    describe("ERC721 Listings", function () {
        it("Should create ERC721 listing with correct parameters", async function () {
            const { marketplace, erc721, seller } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await expect(
                marketplace.connect(seller).createERC721Listing(
                    erc721.target,
                    0, // token ID (changed to 0 based on mintWithoutRoyalty)
                    TOKEN_PRICE, // price
                    ROYALTY_BP, // royalty basis points
                    { value: LISTING_FEE }
                )
            ).to.emit(marketplace, "ListingCreated")
                .withArgs(
                    1, // listing ID
                    erc721.target,
                    0, // token ID
                    seller.address,
                    TOKEN_PRICE,
                    1, // quantity always 1 for ERC721
                    0 // tokenType = ERC721
                );

            // Check token was transferred to marketplace
            expect(await erc721.ownerOf(0)).to.equal(marketplace.target);
        });

        it("Should respect ERC2981 royalty information", async function () {
            const { marketplace, erc721, seller, buyer, royaltyRecipient } = await loadFixture(deployMarketplaceFixture);

            // Create a new token
            await erc721.mint(seller.address, "https://example.com/token/royalty");
            await erc721.setTokenRoyalty(1, royaltyRecipient.address, ROYALTY_BP);

            // Create listing (using token ID = 1 since we already minted one token)
            await marketplace.connect(seller).createERC721Listing(
                erc721.target,
                1, // token ID 1 (our second token with royalty)
                TOKEN_PRICE,
                200, // Custom royalty (2%) - should be overridden by ERC2981
                { value: LISTING_FEE }
            );

            // Calculate expected royalty
            const royaltyAmount = (TOKEN_PRICE * BigInt(ROYALTY_BP)) / 10000n;

            // Buy the token and verify the royalty is paid correctly
            await expect(
                marketplace.connect(buyer).buyItem(1, 1, { value: TOKEN_PRICE })
            ).to.emit(marketplace, "RoyaltyPaid")
                .withArgs(1, royaltyRecipient.address, royaltyAmount, true);
        });
    });

    describe("Buying Items", function () {
        it("Should allow buying an ERC1155 token", async function () {
            const { marketplace, erc1155, seller, buyer } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await marketplace.connect(seller).createERC1155Listing(
                erc1155.target,
                1, // token ID
                10, // quantity
                TOKEN_PRICE, // price per token
                ROYALTY_BP, // royalty basis points
                { value: LISTING_FEE }
            );

            // Buy 5 tokens (partial purchase)
            const buyQuantity = 5;
            const totalPrice = TOKEN_PRICE * BigInt(buyQuantity);

            await expect(
                marketplace.connect(buyer).buyItem(1, buyQuantity, { value: totalPrice })
            ).to.emit(marketplace, "ListingSold")
                .withArgs(
                    1, // listing ID
                    erc1155.target,
                    1, // token ID
                    seller.address,
                    buyer.address,
                    totalPrice,
                    buyQuantity
                );

            // Check tokens transferred to buyer
            expect(await erc1155.balanceOf(buyer.address, 1)).to.equal(buyQuantity);
        });

        it("Should allow buying an ERC721 token", async function () {
            const { marketplace, erc721, seller, buyer } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await marketplace.connect(seller).createERC721Listing(
                erc721.target,
                0, // token ID
                TOKEN_PRICE, // price
                ROYALTY_BP, // royalty basis points
                { value: LISTING_FEE }
            );

            // Buy the token
            await expect(
                marketplace.connect(buyer).buyItem(1, 1, { value: TOKEN_PRICE })
            ).to.emit(marketplace, "ListingSold")
                .withArgs(
                    1, // listing ID
                    erc721.target,
                    0, // token ID
                    seller.address,
                    buyer.address,
                    TOKEN_PRICE,
                    1
                );

            // Check token transferred to buyer
            expect(await erc721.ownerOf(0)).to.equal(buyer.address);
        });

        it("Should distribute funds correctly with royalties", async function () {
            const { marketplace, erc721, seller, buyer, royaltyRecipient } = await loadFixture(deployMarketplaceFixture);

            // Create listing with the token ID 0 which was already minted in the fixture
            await marketplace.connect(seller).createERC721Listing(
                erc721.target,
                0, // Use the token already minted in the fixture
                TOKEN_PRICE, // price
                ROYALTY_BP, // royalty basis points
                { value: LISTING_FEE }
            );

            // Calculate expected royalty
            const royaltyAmount = (TOKEN_PRICE * BigInt(ROYALTY_BP)) / 10000n;
            const sellerAmount = TOKEN_PRICE - royaltyAmount;

            // Check balances change correctly
            await expect(
                marketplace.connect(buyer).buyItem(1, 1, { value: TOKEN_PRICE })
            ).to.changeEtherBalances(
                [seller, royaltyRecipient, buyer],
                [sellerAmount, royaltyAmount, -TOKEN_PRICE]
            );

            // Check royalty event emitted (using a separate listing for this test)
            await erc721.connect(seller).mint(seller.address, "https://example.com/token/2");
            await erc721.connect(seller).setTokenRoyalty(1, royaltyRecipient.address, ROYALTY_BP);
            
            await marketplace.connect(seller).createERC721Listing(
                erc721.target,
                1,
                TOKEN_PRICE,
                ROYALTY_BP,
                { value: LISTING_FEE }
            );

            await expect(
                marketplace.connect(buyer).buyItem(2, 1, { value: TOKEN_PRICE })
            ).to.emit(marketplace, "RoyaltyPaid")
                .withArgs(
                    2, // listing ID
                    royaltyRecipient.address,
                    royaltyAmount,
                    true // from ERC2981
                );
        });

        it("Should revert when trying to buy more than available", async function () {
            const { marketplace, erc1155, seller, buyer } = await loadFixture(deployMarketplaceFixture);

            // Create listing with 10 tokens
            await marketplace.connect(seller).createERC1155Listing(
                erc1155.target,
                1,
                10,
                TOKEN_PRICE,
                ROYALTY_BP,
                { value: LISTING_FEE }
            );

            // Try to buy 15 tokens
            await expect(
                marketplace.connect(buyer).buyItem(1, 15, { value: TOKEN_PRICE * 15n })
            ).to.be.revertedWithCustomError(marketplace, "InvalidQuantity");
        });

        it("Should revert when payment is insufficient", async function () {
            const { marketplace, erc1155, seller, buyer } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await marketplace.connect(seller).createERC1155Listing(
                erc1155.target,
                1,
                10,
                TOKEN_PRICE,
                ROYALTY_BP,
                { value: LISTING_FEE }
            );

            // Try to buy with insufficient payment
            await expect(
                marketplace.connect(buyer).buyItem(1, 5, { value: TOKEN_PRICE * 4n })
            ).to.be.revertedWithCustomError(marketplace, "InsufficientFunds");
        });
    });

    describe("Canceling Listings", function () {
        it("Should allow seller to cancel ERC1155 listing", async function () {
            const { marketplace, erc1155, seller } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await marketplace.connect(seller).createERC1155Listing(
                erc1155.target,
                1,
                10,
                TOKEN_PRICE,
                ROYALTY_BP,
                { value: LISTING_FEE }
            );

            // Cancel listing
            await expect(
                marketplace.connect(seller).cancelListing(1)
            ).to.emit(marketplace, "ListingCancelled")
                .withArgs(1);

            // Check tokens returned to seller
            expect(await erc1155.balanceOf(seller.address, 1)).to.equal(100);
        });

        it("Should revert when non-seller tries to cancel", async function () {
            const { marketplace, erc1155, seller, buyer } = await loadFixture(deployMarketplaceFixture);

            // Create listing
            await marketplace.connect(seller).createERC1155Listing(
                erc1155.target,
                1,
                10,
                TOKEN_PRICE,
                ROYALTY_BP,
                { value: LISTING_FEE }
            );

            // Try to cancel as non-seller
            await expect(
                marketplace.connect(buyer).cancelListing(1)
            ).to.be.revertedWithCustomError(marketplace, "NotOwner");
        });
    });

    describe("Admin Functions", function () {
        it("Should allow owner to update listing fee", async function () {
            const { marketplace, owner } = await loadFixture(deployMarketplaceFixture);

            const newFee = ethers.parseEther("0.02");

            await expect(
                marketplace.connect(owner).updateListingFee(newFee)
            ).to.emit(marketplace, "ListingFeeUpdated")
                .withArgs(newFee);

            expect(await marketplace.listingFee()).to.equal(newFee);
        });

        it("Should allow owner to update fee recipient", async function () {
            const { marketplace, owner, royaltyRecipient } = await loadFixture(deployMarketplaceFixture);

            await expect(
                marketplace.connect(owner).updateFeeRecipient(royaltyRecipient.address)
            ).to.emit(marketplace, "FeeRecipientUpdated")
                .withArgs(royaltyRecipient.address);

            expect(await marketplace.feeRecipient()).to.equal(royaltyRecipient.address);
        });

        it("Should allow owner to toggle ERC2981 respect", async function () {
            const { marketplace, owner } = await loadFixture(deployMarketplaceFixture);

            await expect(
                marketplace.connect(owner).setRespectERC2981(false)
            ).to.emit(marketplace, "ERC2981RespectUpdated")
                .withArgs(false);

            expect(await marketplace.respectERC2981()).to.be.false;
        });

        it("Should revert when non-owner calls admin functions", async function () {
            const { marketplace, seller } = await loadFixture(deployMarketplaceFixture);

            await expect(
                marketplace.connect(seller).updateListingFee(ethers.parseEther("0.02"))
            ).to.be.revertedWithCustomError(marketplace, "OwnableUnauthorizedAccount");

            await expect(
                marketplace.connect(seller).updateFeeRecipient(seller.address)
            ).to.be.revertedWithCustomError(marketplace, "OwnableUnauthorizedAccount");

            await expect(
                marketplace.connect(seller).setRespectERC2981(false)
            ).to.be.revertedWithCustomError(marketplace, "OwnableUnauthorizedAccount");
        });
    });

    describe("Factory and MockERC721 Integration", function() {
        it.only("Should support ERC1155 created by the factory", async function() {
            // Use clean accounts for this test to avoid interaction with other tests
            const [deployer, creator, user] = await ethers.getSigners();
            
            // Deploy the implementation
            const MyERC1155 = await ethers.getContractFactory("MyERC1155");
            const implementation = await MyERC1155.deploy();
            
            // Deploy the factory
            const ERC1155Factory = await ethers.getContractFactory("ERC1155Factory");
            const factory = await ERC1155Factory.deploy(implementation.target);
            
            // Deploy marketplace
            const SalvaNFTMarketplace = await ethers.getContractFactory("SalvaNFTMarketplace");
            const marketplace = await SalvaNFTMarketplace.deploy(LISTING_FEE, deployer.address);
            
            // Create a collection - creator will be the owner
            await factory.connect(creator).createCollection(
                "Factory Collection",
                "FACTORY",
                "https://factory.com/metadata/"
            );
            
            // Get the collection address
            const collections = await factory.getCollectionsByCreator(creator.address);
            const collectionAddress = collections[0].contractAddress;
            console.log("collectionAddress", collectionAddress);
            console.log("collections", collections);
            // Get the collection contract
            const collection = (await ethers.getContractAt("MyERC1155", collectionAddress)) as any;
            
            // Create a token with the collection owner
            const tokenId = await collection.connect(creator).createToken(100, "https://factory.com/token/1");
            // console.log("tokenId", tokenId);
            // Check token ownership
            expect(await collection.balanceOf(creator.address, 1)).to.equal(100);
            
            // // Approve marketplace
            // await collection.connect(creator).setApprovalForAll(marketplace.target, true);
            
            // // List token
            // await marketplace.connect(creator).createERC1155Listing(
            //     collectionAddress,
            //     1, // Token ID starts at 1 for MyERC1155
            //     10, // Quantity
            //     TOKEN_PRICE,
            //     300, // 3% royalty
            //     { value: LISTING_FEE }
            // );
            
            // // Buy token
            // await marketplace.connect(user).buyItem(1, 5, { value: TOKEN_PRICE * 5n });
            
            // // Verify buyer received tokens
            // expect(await collection.balanceOf(user.address, 1)).to.equal(5);
            // expect(await collection.balanceOf(creator.address, 1)).to.equal(95); // 100 - 5 transferred
        });
        
        it("Should support multiple tokens with different royalties", async function() {
            const { marketplace, seller, buyer, royaltyRecipient } = await loadFixture(deployMarketplaceFixture);
            
            // Deploy ERC721
            const MockERC721 = await ethers.getContractFactory("MockERC721");
            const erc721 = (await MockERC721.deploy("Test Multiple", "MULTI")) as any;
            
            // Don't try to transfer ownership, mint directly to seller
            await erc721.mint(seller.address, "uri/1");
            await erc721.setTokenRoyalty(0, royaltyRecipient.address, 250);
            
            await erc721.mint(seller.address, "uri/2");
            await erc721.setTokenRoyalty(1, royaltyRecipient.address, 750);
            
            // Approve marketplace
            await erc721.connect(seller).setApprovalForAll(marketplace.target, true);
            
            // List both tokens
            await marketplace.connect(seller).createERC721Listing(
                erc721.target, 0, TOKEN_PRICE, 0, { value: LISTING_FEE }
            );
            
            await marketplace.connect(seller).createERC721Listing(
                erc721.target, 1, TOKEN_PRICE, 0, { value: LISTING_FEE }
            );
            
            // Calculate expected royalties
            const royaltyAmount1 = (TOKEN_PRICE * 250n) / 10000n;
            const royaltyAmount2 = (TOKEN_PRICE * 750n) / 10000n;
            
            // Buy first token and check royalty
            await expect(
                marketplace.connect(buyer).buyItem(1, 1, { value: TOKEN_PRICE })
            ).to.changeEtherBalance(royaltyRecipient, royaltyAmount1);
            
            // Buy second token and check royalty
            await expect(
                marketplace.connect(buyer).buyItem(2, 1, { value: TOKEN_PRICE })
            ).to.changeEtherBalance(royaltyRecipient, royaltyAmount2);
        });
    });
}); 