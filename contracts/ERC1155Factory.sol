// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Rather than importing the full contract, import an interface
interface IMyERC1155 {
    function initialize(
        string memory _uri,
        string memory _name,
        string memory _symbol,
        address initialOwner,
        string memory _newcontractURI,
        address _marketplace,
        address _auction
    ) external;
    
    function setContractURI(string memory newContractURI) external;
}

// Import OpenZeppelin Clones library
import "@openzeppelin/contracts/proxy/Clones.sol";

// Define factory-specific implementation
contract ERC1155Factory {
    // Factory for deploying MyERC1155 contracts
    address public immutable myERC1155Implementation;
    
    struct Collection {
        address contractAddress;
        string name;
        string symbol;
        string baseURI;
        string contractURI;
        address creator;
        uint256 createdAt;
        bool verified;
    }
    
    Collection[] public collections;
    mapping(address => Collection[]) private creatorCollections;
    address public marketplaceAddress;
    address public auctionAddress;
    
    // Event for tracking collection creation
    event CollectionCreated(
        address indexed contractAddress,
        string name,
        string symbol,
        string baseURI,
        string contractURI,
        address indexed creator
    );
    
    // Event for collection verification
    event CollectionVerified(address indexed contractAddress);

    /**
     * @dev Constructor that takes the address of the MyERC1155 implementation
     * @param _implementation Address of the deployed MyERC1155 implementation
     */
    constructor(address _implementation, address _marketplaceAddress, address _auctionAddress) {
        myERC1155Implementation = _implementation;
        marketplaceAddress = _marketplaceAddress;
        auctionAddress = _auctionAddress;
    }

    /**
     * @dev Create a new ERC1155 collection (contract)
     * @param name Collection name
     * @param symbol Collection symbol
     * @param baseURI Base URI for the collection
     * @param contractURI URI for the OpenSea collection-level metadata
     * @return address of the created collection contract
     */
    function createCollection(
        string memory name,
        string memory symbol,
        string memory baseURI,
        string memory contractURI
    ) public returns (address) {
        // Deploy new collection using minimal proxy pattern
        address newCollectionAddress = _createClone(myERC1155Implementation);
        
        // Initialize the collection
        IMyERC1155(newCollectionAddress).initialize(baseURI, name, symbol, msg.sender, contractURI,marketplaceAddress, auctionAddress);
        
        
        // Store collection metadata
        Collection memory collection = Collection({
            contractAddress: newCollectionAddress,
            name: name,
            symbol: symbol,
            baseURI: baseURI,
            contractURI: contractURI,
            creator: msg.sender,
            createdAt: block.timestamp,
            verified: false
        });
        
        // Track collections
        collections.push(collection);
        creatorCollections[msg.sender].push(collection);
        
        emit CollectionCreated(
            newCollectionAddress,
            name,
            symbol,
            baseURI,
            contractURI,
            msg.sender
        );
        
        return newCollectionAddress;
    }
    
    /**
     * @dev Get all collections
     */
    function getAllCollections() public view returns (Collection[] memory) {
        return collections;
    }
    
    /**
     * @dev Get collections by creator
     */
    function getCollectionsByCreator(address creator) public view returns (Collection[] memory) {
        return creatorCollections[creator];
    }
    
    /**
     * @dev Get collection by index
     */
    function getCollection(uint256 index) public view returns (Collection memory) {
        require(index < collections.length, "Index out of bounds");
        return collections[index];
    }
    
    /**
     * @dev Count total collections
     */
    function collectionsCount() public view returns (uint256) {
        return collections.length;
    }
    
    /**
     * @dev Verify a collection (could be restricted to an admin role in production)
     */
    function verifyCollection(uint256 collectionIndex) public {
        require(collectionIndex < collections.length, "Index out of bounds");
        collections[collectionIndex].verified = true;
        
        emit CollectionVerified(collections[collectionIndex].contractAddress);
    }
    
    /**
     * @dev Creates a minimal proxy clone of a contract
     * @param implementation The address of the implementation contract to clone
     * @return instance Address of the new clone
     */
    function _createClone(address implementation) internal returns (address instance) {
        // Use OpenZeppelin's Clones library instead of raw assembly
        instance = Clones.clone(implementation);
        return instance;
    }
}
