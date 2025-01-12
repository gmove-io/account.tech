/// This is the core module managing Intents.
/// It provides the interface to create, approve and execute intents which is used in the `account` module.

module account_protocol::intents;

// === Imports ===

use std::string::String;
use sui::{
    dynamic_field as df,
    clock::Clock,
    vec_set::{Self, VecSet},
};
use account_protocol::{
    issuer::Issuer,
};

// === Errors ===

#[error]
const ECantBeExecutedYet: vector<u8> = b"Intent hasn't reached execution time";
#[error]
const EHasntExpired: vector<u8> = b"Intent hasn't reached expiration time";
#[error]
const EIntentNotFound: vector<u8> = b"Intent not found for key";
#[error]
const EExpirationBeforeExecution: vector<u8> = b"Expiration time must be greater than execution time";
#[error]
const EObjectAlreadyLocked: vector<u8> = b"Object already locked";
#[error]
const EObjectNotLocked: vector<u8> = b"Object not locked";
#[error]
const ENoExecutionTime: vector<u8> = b"No execution time";
#[error]
const EExecutionTimesNotAscending: vector<u8> = b"Execution times are not ascending";
#[error]
const ECantBeDestroyedYet: vector<u8> = b"Intent can't be destroyed yet";

// === Structs ===

/// Parent struct protecting the intents, fork of a Bag
/// Heterogenous array with u64 as key and Intent as value
public struct Intents has key, store {
    id: UID,
    // to keep track of the last index
    size: u64,
    // ids of the objects that are being requested in intents, to avoid state changes
    locked: VecSet<ID>,
}

/// Child struct, proposal owning a sequence of actions requested to be executed
/// Outcome is a custom struct depending on the config
public struct Intent<Action, Outcome> has store {
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
    // heterogenous array of actions to be executed from last to first
    action: Action,
    // Generic struct storing vote related data, depends on the config
    outcome: Outcome,
}

// === Public functions ===

public fun lock(intents: &mut Intents, id: ID) {
    assert!(!intents.locked.contains(&id), EObjectAlreadyLocked);
    intents.locked.insert(id);
}

public fun unlock(intents: &mut Intents, id: ID) {
    assert!(intents.locked.contains(&id), EObjectNotLocked);
    intents.locked.remove(&id);
}

// === View functions ===

public fun size(intents: &Intents): u64 {
    intents.size
}

public fun locked(intents: &Intents): &VecSet<ID> {
    &intents.locked
}

public fun contains<Action: store, Outcome: store>(intents: &Intents, key: String): bool {
    let mut i = 0;
    while (i < intents.size) {
        if (df::borrow<u64, Intent<Action, Outcome>>(&intents.id, i).key == key)
            return true;
        i = i + 1;
    };

    false
}

public fun get_idx<Action: store, Outcome: store>(intents: &Intents, key: String): u64 {
    let mut idx = 0;
    loop {
        if (df::borrow<u64, Intent<Action, Outcome>>(&intents.id, idx).key == key)
            return idx;

        idx = idx + 1;

        if (idx == intents.size) 
            assert!(false, EIntentNotFound);
    };

    idx
}

public fun get<Action: store, Outcome: store>(intents: &Intents, key: String): &Intent<Action, Outcome> {
    assert!(intents.contains<Action, Outcome>(key), EIntentNotFound);
    let idx = intents.get_idx<Action, Outcome>(key);
    df::borrow<u64, Intent<Action, Outcome>>(&intents.id, idx)
}

public fun issuer<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): &Issuer {
    &intent.issuer
}

public fun description<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): String {
    intent.description
}

public fun execution_times<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): vector<u64> {
    intent.execution_times
}

public fun expiration_time<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): u64 {
    intent.expiration_time
}

public fun action<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): &Action {
    &intent.action
}

public fun outcome<Action: store, Outcome: store>(intent: &Intent<Action, Outcome>): &Outcome {
    &intent.outcome
}

/// safe because &mut Intent is only accessible in core deps
/// only used in AccountConfig 
public fun outcome_mut<Action: store, Outcome: store>(intent: &mut Intent<Action, Outcome>): &mut Outcome {
    &mut intent.outcome
}

// === Package functions ===

/// The following functions are only used in the `account` module

public(package) fun empty(ctx: &mut TxContext): Intents {
    Intents { id: object::new(ctx), size: 0, locked: vec_set::empty() }
}

public(package) fun new_intent<Action, Outcome>(
    issuer: Issuer,
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    action: Action,
    outcome: Outcome,
): Intent<Action, Outcome> {
    assert!(execution_times[0] < expiration_time, EExpirationBeforeExecution);
    assert!(!execution_times.is_empty(), ENoExecutionTime);
    let i = 0;
    while (i < vector::length(&execution_times) - 1) {
        assert!(execution_times[i] < execution_times[i + 1], EExecutionTimesNotAscending);
        i = i + 1;
    };

    Intent<Action, Outcome> { 
        issuer,
        key,
        description,
        execution_times,
        expiration_time,
        action,
        outcome,
    }
}

public(package) fun add<Action: store, Outcome: store>(
    intents: &mut Intents,
    intent: Intent<Action, Outcome>,
) {
    df::add(&mut intents.id, intents.size, intent);
    intents.size = intents.size + 1;
}

public(package) fun get_mut<Action: store, Outcome: store>(
    intents: &mut Intents, 
    key: String
): &mut Intent<Action, Outcome> {
    let idx = intents.get_idx<Action, Outcome>(key);
    df::borrow_mut<u64, Intent<Action, Outcome>>(&mut intents.id, idx)
}

public(package) fun pop_front_execution_time<Action: store, Outcome: store>(
    intent: &mut Intent<Action, Outcome>,
    clock: &Clock,
) {
    let time = intent.execution_times.remove(0);
    assert!(clock.timestamp_ms() >= time, ECantBeExecutedYet);
}

/// Removes an proposal being executed if the execution_time is reached
/// Outcome must be validated in AccountConfig to be destroyed
public(package) fun destroy<Action: store, Outcome: drop + store>(
    intents: &mut Intents,
    key: String,
): Action {
    let Intent<Action, Outcome> { action, execution_times, .. } = swap_remove(intents, key);
    
    assert!(execution_times.is_empty(), ECantBeDestroyedYet);

    action
}

public(package) fun delete<Action: store, Outcome: drop + store>(
    intents: &mut Intents,
    key: String,
    clock: &Clock
): Action {
    let Intent<Action, Outcome> { 
        expiration_time,
        action,
        .. 
    } = intents.swap_remove(key);

    assert!(clock.timestamp_ms() >= expiration_time, EHasntExpired);

    action
}

// === Private functions ===

fun swap_remove<Action: store, Outcome: store>(
    intents: &mut Intents,
    key: String,
): Intent<Action, Outcome> {
    let idx = intents.get_idx<Action, Outcome>(key);
    let intent = df::remove(&mut intents.id, idx);

    // need to swap last element with the one being removed
    let last_idx = intents.size - 1;
    let last_intent = df::remove<u64, Intent<Action, Outcome>>(&mut intents.id, last_idx);
    df::add(&mut intents.id, idx, last_intent);

    intent
}