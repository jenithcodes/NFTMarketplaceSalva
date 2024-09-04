// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface INFTMarketplace {
    function ownerOf(uint256 tokenId) external view returns (address);

    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract NFTSwap is Ownable {
    INFTMarketplace public nftMarketplace;

    struct SwapProposal {
        uint256 tokenIdOffered; // The NFT token ID that is being offered for swap
        address ownerOfOffered; // Owner of the NFT being offered
        uint256 tokenIdRequested; // The NFT token ID that is being requested in exchange
        address ownerOfRequested; // Owner of the NFT being requested
        bool active; // Whether the swap proposal is active
    }

    mapping(uint256 => SwapProposal) public swapProposals; // Mapping of NFT token ID to swap proposal

    event SwapProposed(
        uint256 indexed tokenIdOffered,
        address indexed ownerOfOffered,
        uint256 indexed tokenIdRequested,
        address ownerOfRequested
    );
    event SwapAccepted(
        uint256 indexed tokenIdOffered,
        uint256 indexed tokenIdRequested,
        address indexed ownerOfOffered,
        address ownerOfRequested
    );
    event SwapCancelled(
        uint256 indexed tokenIdOffered,
        address indexed ownerOfOffered
    );

    constructor(address _nftMarketplace, address owner) Ownable(owner) {
        nftMarketplace = INFTMarketplace(_nftMarketplace);
    }

    function proposeSwap(
        uint256 tokenIdOffered,
        uint256 tokenIdRequested
    ) public {
        address ownerOfOffered = nftMarketplace.ownerOf(tokenIdOffered);
        address ownerOfRequested = nftMarketplace.ownerOf(tokenIdRequested);

        require(
            ownerOfOffered == msg.sender,
            "Only the owner can propose a swap"
        );
        require(ownerOfRequested != address(0), "Requested NFT does not exist");
        require(
            !swapProposals[tokenIdOffered].active,
            "Swap already proposed for this NFT"
        );

        swapProposals[tokenIdOffered] = SwapProposal({
            tokenIdOffered: tokenIdOffered,
            ownerOfOffered: ownerOfOffered,
            tokenIdRequested: tokenIdRequested,
            ownerOfRequested: ownerOfRequested,
            active: true
        });

        emit SwapProposed(
            tokenIdOffered,
            ownerOfOffered,
            tokenIdRequested,
            ownerOfRequested
        );
    }

    function acceptSwap(uint256 tokenIdOffered) public {
        SwapProposal storage proposal = swapProposals[tokenIdOffered];
        require(proposal.active, "No active swap proposal for this NFT");
        require(
            proposal.ownerOfRequested == msg.sender,
            "Only the requested NFT owner can accept the swap"
        );

        // Mark the proposal as inactive
        proposal.active = false;

        // Perform the swap
        nftMarketplace.transferFrom(
            proposal.ownerOfOffered,
            msg.sender,
            proposal.tokenIdOffered
        );
        nftMarketplace.transferFrom(
            msg.sender,
            proposal.ownerOfOffered,
            proposal.tokenIdRequested
        );

        emit SwapAccepted(
            proposal.tokenIdOffered,
            proposal.tokenIdRequested,
            proposal.ownerOfOffered,
            msg.sender
        );
    }

    function cancelSwap(uint256 tokenIdOffered) public {
        SwapProposal storage proposal = swapProposals[tokenIdOffered];
        require(proposal.active, "No active swap proposal for this NFT");
        require(
            proposal.ownerOfOffered == msg.sender,
            "Only the owner of the offered NFT can cancel the swap"
        );

        // Mark the proposal as inactive
        proposal.active = false;

        emit SwapCancelled(tokenIdOffered, msg.sender);
    }

    function getSwapProposal(
        uint256 tokenIdOffered
    ) public view returns (SwapProposal memory) {
        return swapProposals[tokenIdOffered];
    }
}
