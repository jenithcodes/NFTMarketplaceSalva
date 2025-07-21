import { ethers } from "hardhat";

async function main() {
  // Get network information
  const network = await ethers.provider.getNetwork();
  console.log("Deploying contracts to network:", network.name);

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  try {
    // 1. Deploy the SalvaNFTMarketplace
    console.log("Deploying SalvaNFTMarketplace...");
    const SalvaNFTMarketplaceFactory = await ethers.getContractFactory("SalvaNFTMarketplace");
    
    // Set initial marketplace parameters
    const initialListingFee = ethers.parseEther("0.001"); // 0.001 ETH listing fee
    const initialOwner = deployer.address;
    
    const marketplace = await SalvaNFTMarketplaceFactory.deploy(initialListingFee, initialOwner);
    await marketplace.waitForDeployment();
    
    const marketplaceAddress = await ethers.resolveAddress(marketplace.target);
    console.log("SalvaNFTMarketplace deployed to:", marketplaceAddress);
    console.log("Initial listing fee:", ethers.formatEther(initialListingFee), "ETH");
    console.log("Initial owner:", initialOwner);

    // 2. Deploy the Auction contract
    console.log("\nDeploying Auction contract...");
    const AuctionFactory = await ethers.getContractFactory("Auction");
    
    // Set auction parameters - using deployer as fee recipient
    const feeRecipient = deployer.address;
    
    const auction = await AuctionFactory.deploy(feeRecipient);
    await auction.waitForDeployment();
    
    const auctionAddress = await ethers.resolveAddress(auction.target);
    console.log("Auction deployed to:", auctionAddress);
    console.log("Fee recipient:", feeRecipient);

    // 3. Deploy the MyERC1155 implementation contract
    console.log("\nDeploying MyERC1155 implementation...");
    const MyERC1155Factory = await ethers.getContractFactory("MyERC1155");
    const myERC1155 = await MyERC1155Factory.deploy();
    await myERC1155.waitForDeployment();
    
    const implementationAddress = await ethers.resolveAddress(myERC1155.target);
    console.log("MyERC1155 implementation deployed to:", implementationAddress);

    // 4. Deploy the ERC1155Factory with implementation, marketplace, and auction addresses
    console.log("\nDeploying ERC1155Factory...");
    const ERC1155FactoryContract = await ethers.getContractFactory("ERC1155Factory");
    const erc1155Factory = await ERC1155FactoryContract.deploy(
      implementationAddress,
      marketplaceAddress,
      auctionAddress
    );
    await erc1155Factory.waitForDeployment();
    
    const factoryAddress = await ethers.resolveAddress(erc1155Factory.target);
    console.log("ERC1155Factory deployed to:", factoryAddress);
    console.log("Configured with marketplace:", marketplaceAddress);
    console.log("Configured with auction:", auctionAddress);

    // 5. Create a sample collection using the factory (good for testing)
    console.log("\nCreating a sample collection...");
    const name = "Sample NFT Collection";
    const symbol = "SAMPLE";
    const baseURI = "https://api.example.com/metadata/";
    const contractURI = "https://api.example.com/collection-metadata.json";
    
    const createTx = await erc1155Factory.createCollection(name, symbol, baseURI, contractURI);
    await createTx.wait();
    
    // Get the new collection address
    const collectionsCount = await erc1155Factory.collectionsCount();
    const collection = await erc1155Factory.getCollection(collectionsCount - 1n);
    console.log("Sample collection created at address:", collection.contractAddress);
    console.log("Collection name:", collection.name);
    console.log("Collection symbol:", collection.symbol);
    console.log("Collection baseURI:", collection.baseURI);
    console.log("Collection creator:", collection.creator);

    console.log("\nDeployment completed successfully!");
    
    // Log deployment addresses for quick reference
    console.log("\n-------------------------------------------------------------");
    console.log("DEPLOYMENT ADDRESSES");
    console.log("-------------------------------------------------------------");
    console.log("SalvaNFTMarketplace:      ", marketplaceAddress);
    console.log("Auction:                  ", auctionAddress);
    console.log("MyERC1155 implementation: ", implementationAddress);
    console.log("ERC1155Factory:           ", factoryAddress);
    console.log("Sample collection:        ", collection.contractAddress);
    console.log("-------------------------------------------------------------");
    
    // Log a reminder to verify contracts on Etherscan (useful for non-hardhat networks)
    if (network.name !== "hardhat" && network.name !== "localhost") {
      console.log("\n-------------------------------------------------------------");
      console.log("Verify contracts on Etherscan with these commands:");
      console.log(`npx hardhat verify --network ${network.name} ${marketplaceAddress} ${initialListingFee} ${initialOwner}`);
      console.log(`npx hardhat verify --network ${network.name} ${auctionAddress} ${feeRecipient}`);
      console.log(`npx hardhat verify --network ${network.name} ${implementationAddress}`);
      console.log(`npx hardhat verify --network ${network.name} ${factoryAddress} ${implementationAddress} ${marketplaceAddress} ${auctionAddress}`);
      console.log("-------------------------------------------------------------\n");
    }
    
    // Return the deployed contract addresses for potential further use
    return {
      marketplaceAddress: marketplaceAddress,
      auctionAddress: auctionAddress,
      myERC1155Address: implementationAddress,
      factoryAddress: factoryAddress,
      sampleCollectionAddress: collection.contractAddress
    };
    
  } catch (error) {
    console.error("Deployment failed:", error);
    process.exit(1);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 