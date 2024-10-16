/// This is the core module managing Proposals.
/// It provides the interface to create, approve and execute proposals which is used in the `account` module.

module account_protocol::proposals;

// === Imports ===

use std::string::String;
use sui::{
    bag::{Self, Bag},
    clock::Clock,
};
use account_protocol::{
    issuer::Issuer,
};

// === Errors ===

#[error]
const ECantBeExecutedYet: vector<u8> = b"Proposal hasn't reached execution time";
#[error]
const EHasntExpired: vector<u8> = b"Proposal hasn't reached expiration epoch";
#[error]
const EProposalNotFound: vector<u8> = b"Proposal not found for key";
#[error]
const EProposalKeyAlreadyExists: vector<u8> = b"Proposal key already exists";
#[error]
const EActionNotFound: vector<u8> = b"Action not found for type";

// === Structs ===

/// Parent struct protecting the proposals
public struct Proposals<Outcome> has store {
    inner: vector<Proposal<Outcome>>
}

/// Child struct, proposal owning a sequence of actions requested to be executed
/// Outcome is a custom struct depending on the config
public struct Proposal<Outcome> has store {
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // name of the proposal, serves as a key, should be unique
    key: String,
    // what this proposal aims to do, for informational purpose
    description: String,
    // proposer can add a timestamp_ms before which the proposal can't be executed
    // can be used to schedule actions via a backend
    execution_time: u64,
    // the proposal can be deleted from this epoch
    expiration_epoch: u64,
    // heterogenous array of actions to be executed from last to first
    actions: Bag,
    // Generic struct storing vote related data, depends on the config
    outcome: Outcome
}

/// Hot potato wrapping actions and outcome from a proposal that expired
public struct Expired<Outcome> {
    actions: Bag,
    outcome: Outcome,
}

// === View functions ===

public fun length<Outcome>(proposals: &Proposals<Outcome>): u64 {
    proposals.inner.length()
}

public fun contains<Outcome>(proposals: &Proposals<Outcome>, key: String): bool {
    proposals.inner.any!(|proposal| proposal.key == key)
}

public fun get_idx<Outcome>(proposals: &Proposals<Outcome>, key: String): u64 {
    proposals.inner.find_index!(|proposal| proposal.key == key).destroy_some()
}

public fun get<Outcome>(proposals: &Proposals<Outcome>, key: String): &Proposal<Outcome> {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &proposals.inner[idx]
}

public fun issuer<Outcome>(proposal: &Proposal<Outcome>): &Issuer {
    &proposal.issuer
}

public fun description<Outcome>(proposal: &Proposal<Outcome>): String {
    proposal.description
}

public fun expiration_epoch<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.expiration_epoch
}

public fun execution_time<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.execution_time
}

public fun actions_length<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.actions.length()
}

public fun outcome<Outcome>(proposal: &Proposal<Outcome>): &Outcome {
    &proposal.outcome
}

// === Proposal functions ===

/// Inserts an action to the proposal bag
public fun add_action<Outcome, A: store, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    action: A, 
    witness: W
) {
    // ensures the function is called within the same proposal as the one that created Proposal
    proposal.issuer().assert_is_constructor(witness);

    let idx = proposal.actions.length();
    proposal.actions.add(idx, action);
}

// === Package functions ===

/// The following functions are only used in the `account` module

public(package) fun empty<Outcome>(): Proposals<Outcome> {
    Proposals<Outcome> { inner: vector[] }
}

public(package) fun new_proposal<Outcome>(
    issuer: Issuer,
    key: String,
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    outcome: Outcome,
    ctx: &mut TxContext
): Proposal<Outcome> {
    Proposal<Outcome> { 
        issuer,
        key,
        description,
        execution_time,
        expiration_epoch,
        actions: bag::new(ctx),
        outcome
    }
}

public(package) fun add<Outcome>(
    proposals: &mut Proposals<Outcome>,
    proposal: Proposal<Outcome>,
) {
    assert!(!proposals.contains(proposal.key), EProposalKeyAlreadyExists);
    proposals.inner.push_back(proposal);
}

/// Removes an proposal being executed if the execution_time is reached
/// Outcome must be validated in AccountConfig to be destroyed
public(package) fun remove<Outcome>(
    proposals: &mut Proposals<Outcome>,
    key: String,
    clock: &Clock,
): (Issuer, Bag, Outcome) {
    let idx = proposals.get_idx(key);
    let Proposal { execution_time, issuer, actions, outcome, .. } = proposals.inner.remove(idx);
    assert!(clock.timestamp_ms() >= execution_time, ECantBeExecutedYet);

    (issuer, actions, outcome)
}

public(package) fun get_mut<Outcome>(proposals: &mut Proposals<Outcome>, key: String): &mut Proposal<Outcome> {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &mut proposals.inner[idx]
}

public(package) fun outcome_mut<Outcome>(proposal: &mut Proposal<Outcome>): &mut Outcome {
    &mut proposal.outcome
}

public(package) fun delete<Outcome>(
    proposals: &mut Proposals<Outcome>,
    key: String,
    ctx: &TxContext
): Expired<Outcome> {
    let idx = proposals.get_idx(key);
    let Proposal<Outcome> { expiration_epoch, actions, outcome, .. } = proposals.inner.remove(idx);
    assert!(expiration_epoch <= ctx.epoch(), EHasntExpired);

    Expired { actions, outcome }
}

/// After calling `account::delete_proposal`, delete each action in its own module
public fun remove_expired_action<Outcome, A: store>(expired: &mut Expired<Outcome>) : A {
    let idx = action_index<Outcome, A>(expired);
    let action = expired.actions.remove(idx);
    
    action
}

/// When the actions bag is empty, call this function from the right AccountConfig module
public fun remove_expired_outcome<Outcome>(expired: Expired<Outcome>) : Outcome {
    let Expired { actions, outcome, .. } = expired;
    actions.destroy_empty();

    outcome
}

// === Private functions ===

fun action_index<Outcome, A: store>(expired: &Expired<Outcome>): u64 {
    let mut idx = 0;
    expired.actions.length().do!(|i| {
        if (expired.actions.contains_with_type<u64, A>(i)) idx = i;
        // returns length if not found
    });
    assert!(idx != expired.actions.length(), EActionNotFound);

    idx
}