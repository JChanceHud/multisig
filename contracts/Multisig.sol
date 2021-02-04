// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.1;

import "./interfaces/ERC20.sol";

contract Multisig {
  enum ProposalType {
    ADD_OWNER,
    REMOVE_OWNER,
    FUND_ADDRESS
  }

  struct Proposal {
    ProposalType _type;
    uint32 votesFor;
    uint32 votesAgainst;
    uint32 voteEnd;
    bool complete;
    bool executed;
    bytes data;
  }

  mapping (address => bool) owners;
  address[] _owners;
  uint32 public ownerCount = 0;

  mapping (address => uint) ownerVotes;
  mapping (address => uint) balances;
  mapping (address => mapping (address => uint)) tokenBalances;

  uint32 voteLength = 3 days;

  event NewProposal(uint index);

  Proposal[] proposals;

  constructor() {
    proposals.push(Proposal({
      _type: ProposalType.ADD_OWNER,
      voteEnd: uint32(block.timestamp),
      data: abi.encode(msg.sender),
      complete: true,
      executed: true,
      votesFor: 0,
      votesAgainst: 0
    }));
    addOwner(msg.sender);
  }

  function activeProposalExists() public view returns (bool) {
    return !proposals[proposals.length - 1].complete;
  }

  function proposeNewOwner(address owner) public {
    require(!activeProposalExists());
    require(owners[msg.sender]);
    require(!owners[owner]);
    proposals.push(Proposal({
      _type: ProposalType.ADD_OWNER,
      voteEnd: uint32(block.timestamp + voteLength),
      data: abi.encode(owner),
      complete: false,
      executed: false,
      votesFor: 0,
      votesAgainst: 0
    }));
    emit NewProposal(proposals.length - 1);
  }

  function proposeRemoveOwner(address owner) public {
    require(!activeProposalExists());
    require(owners[msg.sender]);
    require(owners[owner]);
    proposals.push(Proposal({
      _type: ProposalType.REMOVE_OWNER,
      voteEnd: uint32(block.timestamp + voteLength),
      data: abi.encode(owner),
      complete: false,
      executed: false,
      votesFor: 0,
      votesAgainst: 0
    }));
  }

  function proposeEtherFunding(address recipient, uint amount) public {
    proposeFunding(address(0), recipient, amount);
  }

  function proposeFunding(address token, address recipient, uint amount) public {
    require(!activeProposalExists());
    require(owners[msg.sender]);
    proposals.push(Proposal({
      _type: ProposalType.FUND_ADDRESS,
      voteEnd: uint32(block.timestamp + voteLength),
      data: abi.encode(recipient, token, amount),
      complete: false,
      executed: false,
      votesFor: 0,
      votesAgainst: 0
    }));
  }

  function vote(bool affirm) public {
    require(owners[msg.sender]);
    uint proposalIndex = proposals.length - 1;
    require(ownerVotes[msg.sender] < proposalIndex);
    require(block.timestamp < proposals[proposalIndex].voteEnd);
    ownerVotes[msg.sender] = proposalIndex;
    if (affirm) {
      proposals[proposalIndex].votesFor += 1;
    } else {
      proposals[proposalIndex].votesAgainst += 1;
    }
  }

  function renounceOwnership() public {
    deleteOwner(msg.sender);
  }

  // Complete the voting for a proposal and execute it if the votes passed
  function completeProposal(uint index) public {
    Proposal storage p = proposals[index];
    require(p.votesFor + p.votesAgainst == ownerCount || p.voteEnd > block.timestamp);
    require(!p.complete, "Proposal is already complete");
    p.complete = true;
    // Vote failed
    if (p.votesFor < (ownerCount / 2) + 1) return;
    // Otherwise, vote succeeded
    if (p._type == ProposalType.ADD_OWNER) {
      (address newOwner) = abi.decode(p.data, (address));
      p.executed = addOwner(newOwner);
    } else if (p._type == ProposalType.REMOVE_OWNER) {
      (address oldOwner) = abi.decode(p.data, (address));
      p.executed = deleteOwner(oldOwner);
    } else if (p._type == ProposalType.FUND_ADDRESS) {
      (
        address payable recipient,
        address token,
        uint amount
      ) = abi.decode(p.data, (address, address, uint));
      uint amountPerOwner = amount / ownerCount;
      uint _amount = amountPerOwner * ownerCount;
      if (token == address(0)) {
        p.executed = fundEther(recipient, _amount);
      } else {
        p.executed = fundToken(token, recipient, _amount);
      }
    }
  }

  function fundEther(address payable recipient, uint amount) private returns (bool) {
    uint amountPerOwner = amount / ownerCount;
    for (uint32 x = 0; x < _owners.length; x++) {
      if (balances[_owners[x]] < amountPerOwner) return false;
      balances[_owners[x]] -= amountPerOwner;
    }
    return recipient.send(amount);
  }

  function fundToken(address token, address recipient, uint amount) private returns (bool) {
    if (ERC20(token).balanceOf(address(this)) < amount) {
      return false;
    }
    uint amountPerOwner = amount / ownerCount;
    for (uint32 x = 0; x < _owners.length; x++) {
      if (tokenBalances[_owners[x]][token] < amountPerOwner) return false;
      tokenBalances[_owners[x]][token] -= amountPerOwner;
    }
    try ERC20(token).transfer(recipient, amount) returns (bool success) {
      return success;
    } catch {
      return false;
    }
  }

  function addOwner(address owner) private returns (bool) {
    if (owners[owner]) return true; // already owner
    owners[owner] = true;
    ownerCount++;
    _owners.push(owner);
    return true;
  }

  function deleteOwner(address owner) private returns (bool) {
    if (!owners[owner]) return true; // already not owner
    owners[owner] = false;
    uint32 index = type(uint32).max;
    for (uint32 x = 0; x < _owners.length; x++) {
      if (_owners[x] == owner) {
        index = x;
        break;
      }
    }
    if (index < _owners.length) {
      _owners[index] = _owners[_owners.length - 1];
      delete _owners[_owners.length - 1];
    }
    ownerCount--;
    return true;
  }

  function deposit() public payable {
    balances[msg.sender] += msg.value;
  }

  function withdraw(uint amount) public {
    require(amount >= balances[msg.sender]);
    balances[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);
  }

  function depositToken(address token, uint amount) public {
    require(ERC20(token).allowance(msg.sender, address(this)) >= amount);
    require(ERC20(token).transferFrom(msg.sender, address(this), amount));
    tokenBalances[msg.sender][token] += amount;
  }

  function withdrawToken(address token, uint amount) public {
    require(amount >= tokenBalances[msg.sender][token]);
    tokenBalances[msg.sender][token] -= amount;
    require(ERC20(token).transfer(msg.sender, amount));
  }
}
