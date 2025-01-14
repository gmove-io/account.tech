/// This is the core module managing Proposals.
/// It provides the interface to create, approve and execute proposals which is used in the `account` module.

module account_protocol::intents;

// === Imports ===

use std::string::String;
use sui::{
    bag::{Self, Bag},
    clock::Clock,
    vec_set::{Self, VecSet},
};
use account_protocol::{
    issuer::Issuer,
};

// === Errors ===

#[error]
const ECantBeExecutedYet: vector<u8> = b"Proposal hasn't reached execution time";
#[error]
const EHasntExpired: vector<u8> = b"Proposal hasn't reached expiration time";
#[error]
const EProposalNotFound: vector<u8> = b"Proposal not found for key";
#[error]
const EObjectAlreadyLocked: vector<u8> = b"Object already locked";
#[error]
const EObjectNotLocked: vector<u8> = b"Object not locked";
#[error]
const ENoExecutionTime: vector<u8> = b"No execution time provided";
#[error]
const EExecutionTimesNotAscending: vector<u8> = b"Execution times must be in ascending order";
#[error]
const ECantBeRemovedYet: vector<u8> = b"Proposal hasn't reached expiration time";

// === Structs ===

/// Parent struct protecting the proposals
public struct Intents<Outcome> has store {
    inner: vector<Intent<Outcome>>,
    // ids of the objects that are being requested in intents, to avoid state changes
    locked: VecSet<ID>,
}

/// Child struct, proposal owning a sequence of actions requested to be executed
/// Outcome is a custom struct depending on the config
public struct Intent<Outcome> has store {
    // module that issued the proposal and must destroy it
    issuer: Issuer,
    // name of the proposal, serves as a key, should be unique
    key: String,
    // what this proposal aims to do, for informational purpose
    description: String,
    // proposer can add a timestamp_ms before which the proposal can't be executed
    // can be used to schedule actions via a backend
    // recurring intents can be executed at these times
    execution_times: vector<u64>,
    // the proposal can be deleted from this timestamp
    expiration_time: u64,
    // heterogenous array of actions to be executed in order
    actions: Bag,
    // Generic struct storing vote related data, depends on the config
    outcome: Outcome
}

/// Hot potato wrapping actions from an intent that expired or has been executed
public struct Expired {
    // key of the intent that expired
    key: String,
    // issuer of the intent that expired
    issuer: Issuer,
    // index of the first action in the bag
    start_index: u64,
    // actions that expired
    actions: Bag
}

// === View functions ===

public fun length<Outcome>(intents: &Intents<Outcome>): u64 {
    intents.inner.length()
}

public fun locked<Outcome>(intents: &Intents<Outcome>): &VecSet<ID> {
    &intents.locked
}

public fun contains<Outcome>(intents: &Intents<Outcome>, key: String): bool {
    intents.inner.any!(|intent| intent.key == key)
}

public fun get_idx<Outcome>(intents: &Intents<Outcome>, key: String): u64 {
    let opt_idx = intents.inner.find_index!(|intent| intent.key == key);
    assert!(opt_idx.is_some(), EProposalNotFound);
    opt_idx.destroy_some()
}

public fun get<Outcome>(intents: &Intents<Outcome>, key: String): &Intent<Outcome> {
    let idx = intents.get_idx(key);
    &intents.inner[idx]
}

/// safe because &mut Intent is only accessible in core deps
public fun get_mut<Outcome>(
    intents: &mut Intents<Outcome>, 
    key: String
): &mut Intent<Outcome> {
    let idx = intents.get_idx(key);
    &mut intents.inner[idx]
}

public fun issuer<Outcome>(intent: &Intent<Outcome>): &Issuer {
    &intent.issuer
}

public fun description<Outcome>(intent: &Intent<Outcome>): String {
    intent.description
}

public fun execution_times<Outcome>(intent: &Intent<Outcome>): vector<u64> {
    intent.execution_times
}

public fun expiration_time<Outcome>(intent: &Intent<Outcome>): u64 {
    intent.expiration_time
}

public fun actions<Outcome>(intent: &Intent<Outcome>): &Bag {
    &intent.actions
}

public fun outcome<Outcome>(intent: &Intent<Outcome>): &Outcome {
    &intent.outcome
}

/// safe because &mut Proposal is only accessible in core deps
/// only used in AccountConfig 
public fun outcome_mut<Outcome>(intent: &mut Intent<Outcome>): &mut Outcome {
    &mut intent.outcome
}

public use fun expired_key as Expired.key;
public fun expired_key(expired: &Expired): String {
    expired.key
}

public use fun expired_issuer as Expired.issuer;
public fun expired_issuer(expired: &Expired): &Issuer {
    &expired.issuer
}

public use fun expired_start_index as Expired.start_index;
public fun expired_start_index(expired: &Expired): u64 {
    expired.start_index
}

public use fun expired_actions as Expired.actions;
public fun expired_actions(expired: &Expired): &Bag {
    &expired.actions
}

// === Proposal functions ===

/// Inserts an action to the proposal bag
public fun add_action<Outcome, A: store, W: drop>(
    intent: &mut Intent<Outcome>, 
    action: A, 
    witness: W
) {
    // ensures the function is called within the same proposal as the one that created Proposal
    intent.issuer().assert_is_constructor(witness);

    let idx = intent.actions.length();
    intent.actions.add(idx, action);
}

public fun remove_action<Action: store>(
    expired: &mut Expired, 
): Action {
    let idx = expired.start_index;
    expired.start_index = idx + 1;

    expired.actions.remove(idx)
}

// === Package functions ===

/// The following functions are only used in the `account` module

public(package) fun empty<Outcome>(): Intents<Outcome> {
    Intents<Outcome> { inner: vector[], locked: vec_set::empty() }
}

public(package) fun new_intent<Outcome>(
    issuer: Issuer,
    key: String,
    description: String,
    execution_times: vector<u64>, // timestamp in ms
    expiration_time: u64,
    outcome: Outcome,
    ctx: &mut TxContext
): Intent<Outcome> {
    assert!(!execution_times.is_empty(), ENoExecutionTime);
    let mut i = 0;
    while (i < vector::length(&execution_times) - 1) {
        assert!(execution_times[i] < execution_times[i + 1], EExecutionTimesNotAscending);
        i = i + 1;
    };

    Intent<Outcome> { 
        issuer,
        key,
        description,
        execution_times,
        expiration_time,
        actions: bag::new(ctx),
        outcome
    }
}

public(package) fun pop_front_execution_time<Outcome>(
    intent: &mut Intent<Outcome>,
    clock: &Clock,
) {
    let time = intent.execution_times.remove(0);
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);
}

public(package) fun add<Outcome>(
    intents: &mut Intents<Outcome>,
    intent: Intent<Outcome>,
) {
    intents.inner.push_back(intent);
}

public(package) fun lock<Outcome>(intents: &mut Intents<Outcome>, id: ID) {
    assert!(!intents.locked.contains(&id), EObjectAlreadyLocked);
    intents.locked.insert(id);
}

public(package) fun unlock<Outcome>(intents: &mut Intents<Outcome>, id: ID) {
    assert!(intents.locked.contains(&id), EObjectNotLocked);
    intents.locked.remove(&id);
}

/// Removes an proposal being executed if the execution_time is reached
/// Outcome must be validated in AccountConfig to be destroyed
public(package) fun destroy<Outcome: drop>(
    intents: &mut Intents<Outcome>,
    key: String,
): Expired {
    let idx = intents.get_idx(key);
    let Intent { issuer, key, execution_times, actions, .. } = intents.inner.remove(idx);
    
    assert!(execution_times.is_empty(), ECantBeRemovedYet);

    Expired { key, issuer, start_index: 0, actions }
}

public(package) fun delete<Outcome: drop>(
    intents: &mut Intents<Outcome>,
    key: String,
    clock: &Clock
): Expired {
    let idx = intents.get_idx(key);
    let Intent<Outcome> { issuer, key, expiration_time, actions, .. } = intents.inner.remove(idx);

    assert!(clock.timestamp_ms() >= expiration_time, EHasntExpired);
        
    Expired { key, issuer, start_index: 0, actions }
}