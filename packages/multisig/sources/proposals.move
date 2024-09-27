/// This is the core module managing Proposals.
/// It provides the interface to create, approve and execute proposals which is used in the `multisig` module.

module kraken_multisig::proposals;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet}, 
    bag::{Self, Bag},
    event,
};
use kraken_multisig::{
    auth::Auth,
    members::Member,
};

// === Errors ===

const EAlreadyApproved: u64 = 0;
const ENotApproved: u64 = 1;
const EProposalNotFound: u64 = 2;
const EProposalKeyAlreadyExists: u64 = 3;
const EHasntExpired: u64 = 4;

// === Events ===

public struct Created has copy, drop, store {
    auth_witness: String,
    auth_name: String,
    key: String,
    description: String,
}

public struct Approved has copy, drop, store {
    auth_witness: String,
    auth_name: String,
    key: String,
    description: String,
}

public struct Executed has copy, drop, store {
    auth_witness: String,
    auth_name: String,
    key: String,
    description: String,
}

// === Structs ===

/// Parent struct protecting the proposals
public struct Proposals has store {
    inner: vector<Proposal>
}

/// Child struct, proposal owning a single action requested to be executed
/// can be executed if total_weight >= multisig.thresholds.global
/// or role_weight >= multisig.thresholds.role
public struct Proposal has store {
    // module that issued the proposal and must destroy it
    auth: Auth,
    // name of the proposal, serves as a key, should be unique
    key: String,
    // what this proposal aims to do, for informational purpose
    description: String,
    // the proposal can be deleted from this epoch
    expiration_epoch: u64,
    // proposer can add a timestamp_ms before which the proposal can't be executed
    // can be used to schedule actions via a backend
    execution_time: u64,
    // heterogenous array of actions to be executed from last to first
    actions: Bag,
    // total weight of all members that approved the proposal
    total_weight: u64,
    // sum of the weights of members who approved and have the role
    role_weight: u64, 
    // who has approved the proposal
    approved: VecSet<address>,
}

// === View functions ===

public fun length(proposals: &Proposals): u64 {
    proposals.inner.length()
}

public fun get_idx(proposals: &Proposals, key: String): u64 {
    proposals.inner.find_index!(|proposal| proposal.key == key).destroy_some()
}

public fun contains(proposals: &Proposals, key: String): bool {
    proposals.inner.any!(|proposal| proposal.key == key)
}

public fun get(proposals: &Proposals, key: String): &Proposal {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &proposals.inner[idx]
}

public fun auth(proposal: &Proposal): &Auth {
    &proposal.auth
}

public fun description(proposal: &Proposal): String {
    proposal.description
}

public fun expiration_epoch(proposal: &Proposal): u64 {
    proposal.expiration_epoch
}

public fun execution_time(proposal: &Proposal): u64 {
    proposal.execution_time
}

public fun actions_length(proposal: &Proposal): u64 {
    proposal.actions.length()
}

public fun total_weight(proposal: &Proposal): u64 {
    proposal.total_weight
}

public fun role_weight(proposal: &Proposal): u64 {
    proposal.role_weight
}

public fun approved(proposal: &Proposal): vector<address> {
    proposal.approved.into_keys()
}

public fun has_approved(proposal: &Proposal, addr: address): bool {
    proposal.approved.contains(&addr)
}

// === Multisig-only functions ===

/// Inserts an action to the proposal bag, safe because proposal_mut is only accessible upon creation
public fun add_action<A: store>(proposal: &mut Proposal, action: A) {
    let idx = proposal.actions.length();
    proposal.actions.add(idx, action);
}

// === Package functions ===

/// The following functions are only used in the `multisig` module

public(package) fun new(): Proposals {
    Proposals { inner: vector[] }
}

public(package) fun new_proposal(
    auth: Auth,
    key: String,
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    ctx: &mut TxContext
): Proposal {
    Proposal { 
        auth,
        key,
        description,
        execution_time,
        expiration_epoch,
        actions: bag::new(ctx),
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(), 
    }
}

public(package) fun get_mut(proposals: &mut Proposals, key: String): &mut Proposal {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &mut proposals.inner[idx]
}

public(package) fun add(
    proposals: &mut Proposals,
    proposal: Proposal,
) {
    assert!(!proposals.contains(proposal.key), EProposalKeyAlreadyExists);

    event::emit(Created {
        auth_witness: proposal.auth.witness().into_string().to_string(),
        auth_name: proposal.auth.name(),
        key: proposal.key,
        description: proposal.description,
    });

    proposals.inner.push_back(proposal);
}

public(package) fun remove(
    proposals: &mut Proposals,
    key: String,
): (Auth, Bag) {
    let idx = proposals.get_idx(key);
    let Proposal { auth, actions, description, .. } = proposals.inner.remove(idx);

    event::emit(Executed {
        auth_witness: auth.witness().into_string().to_string(),
        auth_name: auth.name(),
        key,
        description,
    });

    (auth, actions)
}

public(package) fun delete(
    proposals: &mut Proposals,
    key: String,
    ctx: &TxContext
): (Auth, Bag) {
    let idx = proposals.get_idx(key);
    let Proposal { auth, expiration_epoch, actions, .. } = proposals.inner.remove(idx);
    assert!(expiration_epoch <= ctx.epoch(), EHasntExpired);

    (auth, actions)
}

public(package) fun approve(
    proposal: &mut Proposal, 
    member: &Member, 
    ctx: &TxContext
) {
    assert!(!proposal.has_approved(ctx.sender()), EAlreadyApproved);
    
    event::emit(Approved {
        auth_witness: proposal.auth.witness().into_string().to_string(),
        auth_name: proposal.auth.name(),
        key: proposal.key,
        description: proposal.description,
    });

    let role = proposal.auth().into_role();
    let has_role = member.has_role(role);

    let weight = member.weight();
    proposal.approved.insert(ctx.sender()); // throws if already approved
    proposal.total_weight = proposal.total_weight + weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight + weight;
}

public(package) fun disapprove(
    proposal: &mut Proposal, 
    member: &Member, 
    ctx: &TxContext
) {
    assert!(proposal.has_approved(ctx.sender()), ENotApproved);
    let role = proposal.auth().into_role();
    let has_role = member.has_role(role);

    let weight = member.weight();
    proposal.approved.remove(&ctx.sender()); // throws if already approved
    proposal.total_weight = proposal.total_weight - weight;
    if (has_role)
        proposal.role_weight = proposal.role_weight - weight;
}

