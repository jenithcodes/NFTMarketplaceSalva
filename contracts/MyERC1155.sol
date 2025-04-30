// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyERC1155 is ERC1155, ERC2981, Ownable {
    using Strings for uint256;
    
    // Collection metadata
    string public name;
    string public symbol;
    string public baseURI;
    
    // Track if metadata is frozen
    bool public metadataFrozen;
    
    // Initialize tracker to prevent multiple initializations
    bool private _initialized;
    
    // Collaborators who can mint tokens
    mapping(address => bool) public collaborators;
    
    // Token specific properties
    mapping(uint256 => string) private _tokenURIs;
    mapping(uint256 => uint256) public tokenSupply;
    mapping(uint256 => bool) public isUnique; // Indicates if token is unique (supply = 1)
    
    // Mapping for token attributes/traits
    mapping(uint256 => mapping(string => string)) private _tokenAttributes;
    
    // Track the next token ID to be minted
    uint256 private _nextTokenId = 1;
    
    // Events
    event TokenCreated(uint256 indexed tokenId, address indexed creator, uint256 supply, bool isUnique);
    event CollectionMetadataUpdated(string name, string symbol, string baseURI);
    event MetadataFrozen();
    event CollaboratorUpdated(address indexed collaborator, bool status);
    event Initialized(address indexed owner, string name, string symbol);

    constructor() ERC1155("") Ownable(msg.sender) {
        // Empty constructor for clone factory pattern
    }
    
    /**
     * @dev Initialize function to support clone pattern
     * @param _uri Base URI for the collection
     * @param _name Collection name
     * @param _symbol Collection symbol
     * @param initialOwner Owner of the collection
     */
    function initialize(
        string memory _uri,
        string memory _name,
        string memory _symbol,
        address initialOwner
    ) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        
        baseURI = _uri;
        name = _name;
        symbol = _symbol;
        
        // Set default royalty to 2.5%
        _setDefaultRoyalty(initialOwner, 250);
        
        // Transfer ownership to the collection creator
        _transferOwnership(initialOwner);
        
        emit Initialized(initialOwner, _name, _symbol);
    }

    modifier onlyOwnerOrCollaborator() {
        require(owner() == _msgSender() || collaborators[_msgSender()], 
            "Not owner or collaborator");
        _;
    }
    
    modifier metadataNotFrozen() {
        require(!metadataFrozen, "Metadata is frozen");
        _;
    }

    /**
     * @dev Create a new token with specified supply
     * @param supply Number of tokens to mint
     * @param tokenURI URI for the token metadata
     * @return tokenId of the created token
     */
    function createToken(
        uint256 supply,
        string memory tokenURI
    ) public onlyOwnerOrCollaborator returns (uint256) {
        require(supply > 0, "Supply must be positive");
        
        uint256 tokenId = _nextTokenId++;
        _mint(_msgSender(), tokenId, supply, "");
        _setTokenURI(tokenId, tokenURI);
        tokenSupply[tokenId] = supply;
        isUnique[tokenId] = (supply == 1);
        
        emit TokenCreated(tokenId, _msgSender(), supply, supply == 1);
        return tokenId;
    }

    /**
     * @dev Mint more tokens of an existing token ID
     * @param tokenId ID of the token to mint more of
     * @param to Address to mint tokens to
     * @param amount Number of tokens to mint
     */
    function mintMore(
        uint256 tokenId,
        address to,
        uint256 amount
    ) public onlyOwnerOrCollaborator {
        require(tokenSupply[tokenId] > 0, "Token does not exist");
        require(!isUnique[tokenId], "Cannot mint more of a unique NFT");
        
        _mint(to, tokenId, amount, "");
        tokenSupply[tokenId] += amount;
    }

    /**
     * @dev Batch mint tokens
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwnerOrCollaborator {
        for (uint i = 0; i < ids.length; i++) {
            require(tokenSupply[ids[i]] > 0, "Token does not exist");
            require(!isUnique[ids[i]] || (isUnique[ids[i]] && amounts[i] == 1), 
                "Cannot mint multiple of a unique NFT");
            tokenSupply[ids[i]] += amounts[i];
        }
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @dev Burn tokens
     */
    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) public {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "Caller is not owner nor approved"
        );
        _burn(account, id, amount);
        tokenSupply[id] -= amount;
    }

    /**
     * @dev Burn batch of tokens
     */
    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) public {
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "Caller is not owner nor approved"
        );
        _burnBatch(account, ids, amounts);
        
        for (uint i = 0; i < ids.length; i++) {
            tokenSupply[ids[i]] -= amounts[i];
        }
    }

    /**
     * @dev Set token URI for a specific token
     */
    function _setTokenURI(uint256 tokenId, string memory tokenURI) internal {
        _tokenURIs[tokenId] = tokenURI;
    }

    /**
     * @dev Override uri function to provide token-specific URIs
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory tokenURI = _tokenURIs[tokenId];
        
        // If token has specific URI, return it
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        
        // Otherwise use baseURI + tokenId
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId)));
    }

    /**
     * @dev Update collection metadata
     */
    function updateCollectionMetadata(
        string memory _name,
        string memory _symbol,
        string memory _baseURI
    ) public onlyOwner metadataNotFrozen {
        name = _name;
        symbol = _symbol;
        baseURI = _baseURI;
        
        emit CollectionMetadataUpdated(_name, _symbol, _baseURI);
    }

    /**
     * @dev Freeze metadata - cannot be undone
     */
    function freezeMetadata() public onlyOwner {
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    /**
     * @dev Set token attributes/traits
     */
    function setTokenAttribute(
        uint256 tokenId,
        string memory traitType,
        string memory value
    ) public onlyOwnerOrCollaborator metadataNotFrozen {
        require(tokenSupply[tokenId] > 0, "Token does not exist");
        _tokenAttributes[tokenId][traitType] = value;
    }

    /**
     * @dev Get token attribute/trait
     */
    function getTokenAttribute(
        uint256 tokenId,
        string memory traitType
    ) public view returns (string memory) {
        return _tokenAttributes[tokenId][traitType];
    }

    /**
     * @dev Add or remove collaborator
     */
    function setCollaborator(address collaborator, bool status) public onlyOwner {
        collaborators[collaborator] = status;
        
        emit CollaboratorUpdated(collaborator, status);
    }

    /**
     * @dev Set royalties for a specific token
     */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeNumerator
    ) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /**
     * @dev Set default royalties for all tokens
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @dev Get total supply of a specific token
     */
    function getTokenSupply(uint256 tokenId) public view returns (uint256) {
        return tokenSupply[tokenId];
    }

    /**
     * @dev Get the next token ID that will be used for minting
     */
    function getNextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @dev Support for ERC2981 interface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return 
            ERC1155.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }
} 