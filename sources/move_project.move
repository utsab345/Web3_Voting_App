#[allow(duplicate_alias, lint(self_transfer))]
module move_project::voting_system;

use sui::object::{UID, ID, id, new};
use sui::tx_context::{TxContext, sender};
use sui::transfer;
use sui::event;
use std::string;
use std::vector;

const EAlreadyVoted: u64 = 1;

// Events for tracking proposals and votes
public struct ProposalCreated has copy, drop {
    proposal_id: ID,
    creator: address,
    title: string::String,
    description: string::String,
}

public struct VoteCast has copy, drop {
    proposal_id: ID,
    voter: address,
    choice: bool,
}

// Admin capability (optional, can be used for system administration)
public struct AdminCap has key, store {
    id: UID,
}

// Proposal struct - now anyone can create these
public struct Proposal has key, store {
    id: UID,
    creator: address,
    title: string::String,
    description: string::String,
    yes_votes: u64,
    no_votes: u64,
    voters: vector<address>,
    created_at: u64, // timestamp when created
}

// Vote NFT as proof of participation
public struct VoteNFT has key, store {
    id: UID,
    proposal_id: ID,
    voter: address,
    choice: bool,
    voted_at: u64, // timestamp when voted
}

// Global registry to track all proposals (shared object)
public struct ProposalRegistry has key {
    id: UID,
    proposal_count: u64,
    active_proposals: vector<ID>,
}

fun init(ctx: &mut TxContext) {
    let registry = ProposalRegistry {
        id: new(ctx),
        proposal_count: 0,
        active_proposals: vector::empty<ID>(),
    };
    
    let admin_cap = AdminCap {
        id: new(ctx),
    };
    
    transfer::share_object(registry);
    transfer::public_transfer(admin_cap, sender(ctx));
}


// Anyone can create a proposal (no admin cap required)
public fun create_proposal(
    registry: &mut ProposalRegistry,
    title: string::String, 
    description: string::String, 
    ctx: &mut TxContext
): ID {
    let proposal = Proposal {
        id: new(ctx),
        creator: sender(ctx),
        title,
        description,
        yes_votes: 0,
        no_votes: 0,
        voters: vector::empty<address>(),
        created_at: sui::tx_context::epoch_timestamp_ms(ctx),
    };
    
    let proposal_id = id(&proposal);
    
    // Add to registry
    registry.proposal_count = registry.proposal_count + 1;
    vector::push_back(&mut registry.active_proposals, proposal_id);
    
    // Emit event
    event::emit(ProposalCreated {
        proposal_id,
        creator: sender(ctx),
        title,
        description,
    });
    
    // Share the proposal so anyone can vote
    transfer::share_object(proposal);
    
    proposal_id
}

// Vote on a proposal
public fun vote(proposal: &mut Proposal, choice: bool, ctx: &mut TxContext) {
    let voter = sender(ctx);
    let voters_ref = &proposal.voters;
    let len = vector::length(voters_ref);
    let mut i = 0;
    
    // Check if voter already voted
    while (i < len) {
        assert!(*vector::borrow(voters_ref, i) != voter, EAlreadyVoted);
        i = i + 1;
    };
    
    // Add voter to the list
    vector::push_back(&mut proposal.voters, voter);
    
    // Update vote counts
    if (choice) {
        proposal.yes_votes = proposal.yes_votes + 1;
    } else {
        proposal.no_votes = proposal.no_votes + 1;
    };
    
    // Create vote NFT
    let vote_nft = VoteNFT {
        id: new(ctx),
        proposal_id: id(proposal),
        voter,
        choice,
        voted_at: sui::tx_context::epoch_timestamp_ms(ctx),
    };
    
    // Emit event
    event::emit(VoteCast {
        proposal_id: id(proposal),
        voter,
        choice,
    });
    
    // Transfer vote NFT to voter
    transfer::public_transfer(vote_nft, voter);
}

// Get proposal details (view function)
public fun get_proposal_info(proposal: &Proposal): (
    address, // creator
    string::String, // title
    string::String, // description
    u64, // yes_votes
    u64, // no_votes
    u64, // total_voters
    u64  // created_at
) {
    (
        proposal.creator,
        proposal.title,
        proposal.description,
        proposal.yes_votes,
        proposal.no_votes,
        vector::length(&proposal.voters),
        proposal.created_at
    )
}

// Get registry info (view function)
public fun get_registry_info(registry: &ProposalRegistry): (u64, vector<ID>) {
    (registry.proposal_count, registry.active_proposals)
}

// Check if user has voted on a proposal
public fun has_voted(proposal: &Proposal, user: address): bool {
    let voters_ref = &proposal.voters;
    let len = vector::length(voters_ref);
    let mut i = 0;
    
    while (i < len) {
        if (*vector::borrow(voters_ref, i) == user) {
            return true
        };
        i = i + 1;
    };
    
    false
}

// Admin function to remove a proposal from registry (optional)
public fun remove_proposal_from_registry(
    _admin: &AdminCap,
    registry: &mut ProposalRegistry,
    proposal_id: ID
) {
    let active_proposals = &mut registry.active_proposals;
    let len = vector::length(active_proposals);
    let mut i = 0;
    
    while (i < len) {
        if (*vector::borrow(active_proposals, i) == proposal_id) {
            vector::remove(active_proposals, i);
            break
        };
        i = i + 1;
    };
}