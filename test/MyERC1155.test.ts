import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("MyERC1155", function () {
  // Fixture to deploy the contract
  async function deployMyERC1155Fixture() {
    const [owner, creator, user1, user2] = await ethers.getSigners();

    // Deploy the contract
    const MyERC1155Factory = await ethers.getContractFactory("MyERC1155");
    const myERC1155 = await MyERC1155Factory.deploy();
    
    // Initialize the contract
    await myERC1155.initialize(
      "https://example.com/metadata/",
      "Test Collection",
      "TEST",
      owner.address
    );

    return { myERC1155, owner, creator, user1, user2 };
  }

  describe("Deployment", function () {
    it("Should deploy with correct parameters", async function () {
      const { myERC1155, owner } = await loadFixture(deployMyERC1155Fixture);
      
      expect(await myERC1155.name()).to.equal("Test Collection");
      expect(await myERC1155.symbol()).to.equal("TEST");
      expect(await myERC1155.baseURI()).to.equal("https://example.com/metadata/");
      expect(await myERC1155.owner()).to.equal(owner.address);
    });
  });

  describe("Token Creation", function () {
    it("Should create a token with correct parameters", async function () {
      const { myERC1155, owner } = await loadFixture(deployMyERC1155Fixture);
      
      const tokenURI = "https://example.com/token/1";
      const supply = 100;
      
      await expect(myERC1155.createToken(supply, tokenURI))
        .to.emit(myERC1155, "TokenCreated")
        .withArgs(1, owner.address, supply, false);
      
      expect(await myERC1155.tokenSupply(1)).to.equal(supply);
      expect(await myERC1155.balanceOf(owner.address, 1)).to.equal(supply);
      expect(await myERC1155.uri(1)).to.equal(tokenURI);
      expect(await myERC1155.isUnique(1)).to.equal(false);
    });

    it("Should create a unique token (supply=1)", async function () {
      const { myERC1155, owner } = await loadFixture(deployMyERC1155Fixture);
      
      const tokenURI = "https://example.com/token/unique";
      const supply = 1;
      
      await expect(myERC1155.createToken(supply, tokenURI))
        .to.emit(myERC1155, "TokenCreated")
        .withArgs(1, owner.address, supply, true);
      
      expect(await myERC1155.isUnique(1)).to.equal(true);
    });

    it("Should prevent non-owners from creating tokens", async function () {
      const { myERC1155, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      await expect(
        myERC1155.connect(user1).createToken(100, "https://example.com/token/1")
      ).to.be.revertedWith("Not owner or collaborator");
    });

    it("Should allow collaborators to create tokens", async function () {
      const { myERC1155, owner, creator } = await loadFixture(deployMyERC1155Fixture);
      
      // Add creator as collaborator
      await myERC1155.setCollaborator(creator.address, true);
      expect(await myERC1155.collaborators(creator.address)).to.be.true;
      
      // Creator creates a token
      await expect(
        myERC1155.connect(creator).createToken(50, "https://example.com/token/2")
      ).to.emit(myERC1155, "TokenCreated");
      
      expect(await myERC1155.balanceOf(creator.address, 1)).to.equal(50);
    });
  });

  describe("Token Minting", function () {
    it("Should mint more tokens of existing ID", async function () {
      const { myERC1155, owner, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create initial token
      await myERC1155.createToken(100, "https://example.com/token/1");
      
      // Mint more to user1
      await myERC1155.mintMore(1, user1.address, 50);
      
      expect(await myERC1155.balanceOf(owner.address, 1)).to.equal(100);
      expect(await myERC1155.balanceOf(user1.address, 1)).to.equal(50);
      expect(await myERC1155.tokenSupply(1)).to.equal(150);
    });

    it("Should prevent minting more of unique tokens", async function () {
      const { myERC1155, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create unique token
      await myERC1155.createToken(1, "https://example.com/token/unique");
      
      // Try to mint more
      await expect(
        myERC1155.mintMore(1, user1.address, 1)
      ).to.be.revertedWith("Cannot mint more of a unique NFT");
    });

    it("Should batch mint tokens", async function () {
      const { myERC1155, owner, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create tokens
      await myERC1155.createToken(100, "https://example.com/token/1");
      await myERC1155.createToken(200, "https://example.com/token/2");
      
      // Batch mint
      await myERC1155.mintBatch(
        user1.address,
        [1, 2],
        [50, 75],
        "0x"
      );
      
      expect(await myERC1155.balanceOf(user1.address, 1)).to.equal(50);
      expect(await myERC1155.balanceOf(user1.address, 2)).to.equal(75);
      expect(await myERC1155.tokenSupply(1)).to.equal(150);
      expect(await myERC1155.tokenSupply(2)).to.equal(275);
    });
  });

  describe("Token Burning", function () {
    it("Should burn owned tokens", async function () {
      const { myERC1155, owner } = await loadFixture(deployMyERC1155Fixture);
      
      // Create token
      await myERC1155.createToken(100, "https://example.com/token/1");
      
      // Burn tokens
      await myERC1155.burn(owner.address, 1, 30);
      
      expect(await myERC1155.balanceOf(owner.address, 1)).to.equal(70);
      expect(await myERC1155.tokenSupply(1)).to.equal(70);
    });

    it("Should burn batch of tokens", async function () {
      const { myERC1155, owner } = await loadFixture(deployMyERC1155Fixture);
      
      // Create tokens
      await myERC1155.createToken(100, "https://example.com/token/1");
      await myERC1155.createToken(200, "https://example.com/token/2");
      
      // Burn batch
      await myERC1155.burnBatch(
        owner.address,
        [1, 2],
        [30, 50]
      );
      
      expect(await myERC1155.balanceOf(owner.address, 1)).to.equal(70);
      expect(await myERC1155.balanceOf(owner.address, 2)).to.equal(150);
      expect(await myERC1155.tokenSupply(1)).to.equal(70);
      expect(await myERC1155.tokenSupply(2)).to.equal(150);
    });

    it("Should prevent unauthorized burning", async function () {
      const { myERC1155, owner, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create token
      await myERC1155.createToken(100, "https://example.com/token/1");
      
      // Transfer some to user1
      await myERC1155.safeTransferFrom(owner.address, user1.address, 1, 50, "0x");
      
      // Try to burn user1's tokens from owner account
      await expect(
        myERC1155.burn(user1.address, 1, 10)
      ).to.be.revertedWith("Caller is not owner nor approved");
    });
  });

  describe("Metadata Management", function () {
    it("Should update collection metadata", async function () {
      const { myERC1155 } = await loadFixture(deployMyERC1155Fixture);
      
      const newName = "Updated Collection";
      const newSymbol = "UPDATED";
      const newBaseURI = "https://updated.com/metadata/";
      
      await myERC1155.updateCollectionMetadata(newName, newSymbol, newBaseURI);
      
      expect(await myERC1155.name()).to.equal(newName);
      expect(await myERC1155.symbol()).to.equal(newSymbol);
      expect(await myERC1155.baseURI()).to.equal(newBaseURI);
    });

    it("Should freeze metadata permanently", async function () {
      const { myERC1155 } = await loadFixture(deployMyERC1155Fixture);
      
      // Freeze metadata
      await myERC1155.freezeMetadata();
      expect(await myERC1155.metadataFrozen()).to.be.true;
      
      // Try to update metadata
      await expect(
        myERC1155.updateCollectionMetadata("New Name", "NEW", "https://new.com/")
      ).to.be.revertedWith("Metadata is frozen");
    });

    it("Should set and get token attributes", async function () {
      const { myERC1155 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create token
      await myERC1155.createToken(100, "https://example.com/token/1");
      
      // Set attributes
      await myERC1155.setTokenAttribute(1, "color", "blue");
      await myERC1155.setTokenAttribute(1, "size", "large");
      
      // Get attributes
      expect(await myERC1155.getTokenAttribute(1, "color")).to.equal("blue");
      expect(await myERC1155.getTokenAttribute(1, "size")).to.equal("large");
    });
  });

  describe("Royalties", function () {
    it("Should set default royalties", async function () {
      const { myERC1155, owner, user1 } = await loadFixture(deployMyERC1155Fixture);
      
      // Set new default royalty
      await myERC1155.setDefaultRoyalty(user1.address, 500); // 5%
      
      // Create token (should inherit default royalty)
      await myERC1155.createToken(100, "https://example.com/token/1");
      
      // Check royalty info
      const price = ethers.parseEther("1");
      const [receiver, royaltyAmount] = await myERC1155.royaltyInfo(1, price);
      
      expect(receiver).to.equal(user1.address);
      expect(royaltyAmount).to.equal(price * 500n / 10000n);
    });

    it("Should set token-specific royalties", async function () {
      const { myERC1155, owner, user1, user2 } = await loadFixture(deployMyERC1155Fixture);
      
      // Create tokens
      await myERC1155.createToken(100, "https://example.com/token/1");
      await myERC1155.createToken(100, "https://example.com/token/2");
      
      // Set different royalties for each token
      await myERC1155.setTokenRoyalty(1, user1.address, 500); // 5%
      await myERC1155.setTokenRoyalty(2, user2.address, 1000); // 10%
      
      // Check royalty info
      const price = ethers.parseEther("1");
      
      const [receiver1, royaltyAmount1] = await myERC1155.royaltyInfo(1, price);
      expect(receiver1).to.equal(user1.address);
      expect(royaltyAmount1).to.equal(price * 500n / 10000n);
      
      const [receiver2, royaltyAmount2] = await myERC1155.royaltyInfo(2, price);
      expect(receiver2).to.equal(user2.address);
      expect(royaltyAmount2).to.equal(price * 1000n / 10000n);
    });
  });
}); 