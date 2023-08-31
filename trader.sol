//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Swapper is Ownable {
    enum AssetType {
        ERC20,
        ERC721
    }

    struct Proposal {
        address from;
        address to;
        Content[] giveContents;
        Content[] receiveContents;
        uint expiryDate;
        bool fulfilled;
    }

    struct Content {
        AssetType assetType;
        address tokenAddress;
        uint amountOrId;
    }

    uint proposalsCount;
    mapping(uint => Proposal) public proposals;

    event ProposalFulfilled(uint indexed _id, Proposal _proposal);

    function addProposal(
        address _to,
        Content[] calldata _giveContents,
        Content[] calldata _receiveContents,
        uint _expiryDate
    ) external returns (uint) {
        proposalsCount++;
        Proposal storage proposal = proposals[proposalsCount];
        proposal.from = msg.sender;
        proposal.to = _to;
        proposal.expiryDate = _expiryDate;
        proposal.fulfilled = false;
        for (uint i = 0; i < _giveContents.length; i++) {
            Content memory _giveContent = _giveContents[i];
            sideIsAbleToFulfillTheirPart(_giveContent, msg.sender, true);
            proposal.giveContents.push(_giveContent);
        }
        for (uint i = 0; i < _receiveContents.length; i++) {
            Content memory _receiveContent = _receiveContents[i];
            proposal.receiveContents.push(_receiveContent);
        }
        return proposalsCount;
    }

    function fulfillProposal(uint _id) external {
        Proposal storage proposal = proposals[_id];
        require(proposal.expiryDate <= block.timestamp);
        require(
            proposal.to == msg.sender,
            "You're not the Taker of this proposal"
        );
        require(
            proposal.fulfilled == false,
            "This proposal has already been fulfilled"
        );
        for (uint i = 0; i < proposal.giveContents.length; i++) {
            Content memory _content = proposal.giveContents[i];
            performTransactionInContent(
                _content,
                proposal.from,
                proposal.to,
                true
            );
        }
        for (uint i = 0; i < proposal.receiveContents.length; i++) {
            Content memory _content = proposal.receiveContents[i];
            performTransactionInContent(
                _content,
                proposal.to,
                proposal.from,
                false
            );
        }
        proposal.fulfilled = true;

        emit ProposalFulfilled(_id, proposal);
    }

    function clearProposalWithId(uint _id) external {
        Proposal storage proposal = proposals[_id];
        require(
            proposal.from == msg.sender,
            "You're not the Maker of this proposal"
        );
        delete proposals[_id];
    }

    function performTransactionInContent(
        Content memory _content,
        address _transactionOrigin,
        address _transactionDestination,
        bool _isMaker
    ) internal {
        sideIsAbleToFulfillTheirPart(_content, _transactionOrigin, _isMaker);
        if (_content.assetType == AssetType.ERC20) {
            uint _amountInWei = _content.amountOrId * 10 ** 18;
            IERC20 token = IERC20(_content.tokenAddress);
            token.transferFrom(
                _transactionOrigin,
                _transactionDestination,
                _amountInWei
            );
        } else if (_content.assetType == AssetType.ERC721) {
            uint _tokenId = _content.amountOrId;
            IERC721 token = IERC721(_content.tokenAddress);
            token.safeTransferFrom(
                _transactionOrigin,
                _transactionDestination,
                _tokenId
            );
        }
    }

    function sideIsAbleToFulfillTheirPart(
        Content memory _content,
        address _from,
        bool _isMaker
    ) internal view {
        if (_content.assetType == AssetType.ERC20) {
            uint _amountInWei = _content.amountOrId * 10 ** 18;
            IERC20 token = IERC20(_content.tokenAddress);
            require(
                token.allowance(_from, address(this)) >= _amountInWei,
                string.concat(
                    _isMaker ? "Maker" : "Taker",
                    " has not approved ",
                    Strings.toHexString(_content.tokenAddress)
                )
            );
            require(
                token.balanceOf(_from) >= _amountInWei,
                string.concat(
                    _isMaker ? "Maker" : "Taker",
                    " has not enough balance"
                )
            );
        } else if (_content.assetType == AssetType.ERC721) {
            uint _tokenId = _content.amountOrId;
            IERC721 token = IERC721(_content.tokenAddress);
            require(
                token.isApprovedForAll(_from, address(this)),
                string.concat(
                    _isMaker ? "Maker" : "Taker",
                    " has not approved ",
                    Strings.toHexString(_content.tokenAddress)
                )
            );
            require(
                token.ownerOf(_tokenId) == _from,
                string.concat(
                    _isMaker ? "Maker" : "Taker",
                    " is not the owner of NFT with ID ",
                    Strings.toString(_tokenId),
                    " in collection ",
                    Strings.toHexString(_content.tokenAddress)
                )
            );
        }
    }
}
