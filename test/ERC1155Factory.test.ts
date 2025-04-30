// import { expect } from "chai";
// import { ethers } from "hardhat";
// import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
// import { ERC1155Factory, MyERC1155 } from "../typechain-types";
// import { Signer } from "ethers";

// describe("ERC1155Factory", function () {
//   // Test fixture
//   async function deployFactoryFixture() {
//     const [owner, creator1, creator2, user] = await ethers.getSigners();

//     // First deploy the implementation contract
//     const MyERC1155Factory = await ethers.getContractFactory("MyERC1155");
//     const implementationContract = await MyERC1155Factory.deploy();
//     const implementationAddress = await ethers.resolveAddress(implementationContract.target);

//     // Deploy the ERC1155Factory contract with the implementation address
//     const ERC1155FactoryFactory = await ethers.getContractFactory("ERC1155Factory");
//     const factory = await ERC1155FactoryFactory.deploy(implementationAddress);

//     return { factory, implementationContract, owner, creator1, creator2, user };
//   }

//   describe("Collection Creation", function () {
//     it("Should create a new ERC1155 collection", async function () {
//       const { factory, creator1 } = await loadFixture(deployFactoryFixture);
      
//       const name = "Test Collection";
//       const symbol = "TEST";
//       const baseURI = "https://test.com/metadata/";
      
//       // Create a collection
//       const tx = await factory.connect(creator1).createCollection(name, symbol, baseURI);
//       await tx.wait();
      
//       // Check collections count
//       expect(await factory.collectionsCount()).to.equal(1);
      
//       // Verify collection data
//       const collection = await factory.getCollection(0);
//       expect(collection.name).to.equal(name);
//       expect(collection.symbol).to.equal(symbol);
//       expect(collection.baseURI).to.equal(baseURI);
//       expect(collection.creator).to.equal(creator1.address);
//       expect(collection.verified).to.be.false;
//     });

//     it("Should track collections by creator", async function () {
//       const { factory, creator1, creator2 } = await loadFixture(deployFactoryFixture);
      
//       // Creator 1 makes 2 collections
//       await factory.connect(creator1).createCollection("C1", "C1", "uri1/");
//       await factory.connect(creator1).createCollection("C2", "C2", "uri2/");
      
//       // Creator 2 makes 1 collection
//       await factory.connect(creator2).createCollection("C3", "C3", "uri3/");
      
//       // Check collection counts
//       expect(await factory.collectionsCount()).to.equal(3);
      
//       // Check creator collections
//       const creator1Collections = await factory.getCollectionsByCreator(creator1.address);
//       expect(creator1Collections.length).to.equal(2);
//       expect(creator1Collections[0].name).to.equal("C1");
//       expect(creator1Collections[1].name).to.equal("C2");
      
//       const creator2Collections = await factory.getCollectionsByCreator(creator2.address);
//       expect(creator2Collections.length).to.equal(1);
//       expect(creator2Collections[0].name).to.equal("C3");
//     });
//   });

//   describe("Collection Verification", function () {
//     it("Should allow verification of collections", async function () {
//       const { factory, creator1 } = await loadFixture(deployFactoryFixture);
      
//       // Create a collection
//       await factory.connect(creator1).createCollection("Test", "TST", "uri/");
      
//       // Verify the collection
//       await factory.verifyCollection(0);
      
//       // Check verification status
//       const collection = await factory.getCollection(0);
//       expect(collection.verified).to.be.true;
//     });

//     it("Should revert when verifying non-existent collection", async function () {
//       const { factory } = await loadFixture(deployFactoryFixture);
      
//       // Try to verify non-existent collection
//       await expect(factory.verifyCollection(0))
//         .to.be.revertedWith("Index out of bounds");
//     });
//   });

//   describe("Collection Interaction", function () {
//     it("Should return all collections", async function () {
//       const { factory, creator1, creator2 } = await loadFixture(deployFactoryFixture);
      
//       // Create collections
//       await factory.connect(creator1).createCollection("C1", "C1", "uri1/");
//       await factory.connect(creator2).createCollection("C2", "C2", "uri2/");
      
//       // Get all collections
//       const collections = await factory.getAllCollections();
//       expect(collections.length).to.equal(2);
//       expect(collections[0].name).to.equal("C1");
//       expect(collections[1].name).to.equal("C2");
//     });

//     it("Should return collections count", async function () {
//       const { factory, creator1 } = await loadFixture(deployFactoryFixture);
      
//       expect(await factory.collectionsCount()).to.equal(0);
      
//       // Create a collection
//       await factory.connect(creator1).createCollection("Test", "TST", "uri/");
      
//       expect(await factory.collectionsCount()).to.equal(1);
//     });
//   });
// }); 