#[test_only]
module account_actions::access_control_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    proposals::Proposal,
    issuer,
    deps,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    access_control,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyProposal() has copy, drop;
public struct WrongProposal() has copy, drop;

public struct Cap has key, store { id: UID }
public struct WrongCap has store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @account_config, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);
    // Account generic types are dummy types (bool, bool)
    let account = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun cap(scenario: &mut Scenario): Cap {
    Cap { id: object::new(scenario.ctx()) }
}

fun create_dummy_proposal(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Proposal<Approvals> {
    let auth = multisig::authenticate(extensions, account, b"".to_string(), scenario.ctx());
    let outcome = multisig::new_outcome(account, scenario.ctx());
    account.create_proposal(
        auth, 
        outcome, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"dummy".to_string(), 
        b"".to_string(), 
        0,
        1, 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock_cap() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_propose_execute_access() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::new_outcome(&account, scenario.ctx());
    access_control::propose_access<Multisig, Approvals, Cap>(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        scenario.ctx()
    );

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let (borrow, cap) = access_control::execute_access<Multisig, Approvals, Cap>(&mut executable, &mut account);
    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    // do something with the cap
    access_control::complete_access(executable, &mut account, borrow, cap);
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());

    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, version::current(), DummyProposal());
    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    // do something with the cap
    access_control::return_cap(&mut account, borrow, cap, version::current());
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));

    access_control::destroy_access<Cap, DummyProposal>(&mut executable, version::current(), DummyProposal());
    executable.terminate(version::current(), DummyProposal());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"key".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    let mut expired = account.delete_proposal(key, version::current(), &clock);
    access_control::delete_access_action<Approvals, Cap>(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

/// Test error: cannot return wrong cap type because of type args

#[test, expected_failure(abort_code = access_control::EAlreadyLocked)]
fun test_error_lock_cap_already_locked() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::ENoLock)]
fun test_error_propose_access_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::new_outcome(&account, scenario.ctx());
    access_control::propose_access<Multisig, Approvals, Cap>(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::ENoLock)]
fun test_error_access_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());

    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, version::current(), DummyProposal());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::EWrongAccount)]
fun test_error_return_to_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());

    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, version::current(), DummyProposal());
    // create other account
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    access_control::return_cap(&mut account2, borrow, cap, version::current());
    executable.terminate(version::current(), DummyProposal());

    destroy(account2);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_access_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    // create other account and lock same type of cap
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account2, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account2, cap(&mut scenario));
    
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account2, version::current(), DummyProposal());

    destroy(account2);
    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_access_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, WrongProposal>(&mut executable, &mut account, version::current(), WrongProposal());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_access_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, wrong_version(), DummyProposal());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error__destroy_access_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, version::current(), DummyProposal());
    access_control::return_cap(&mut account, borrow, cap, version::current());
    
    access_control::destroy_access<Cap, WrongProposal>(&mut executable, version::current(), WrongProposal());
    executable.terminate(version::current(), DummyProposal());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_destroy_access_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"key".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    
    access_control::new_access<Approvals, Cap, DummyProposal>(&mut proposal, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock, scenario.ctx());
    
    let (borrow, cap) = access_control::access_cap<Multisig, Approvals, Cap, DummyProposal>(&mut executable, &mut account, version::current(), DummyProposal());
    access_control::return_cap(&mut account, borrow, cap, version::current());
    
    access_control::destroy_access<Cap, DummyProposal>(&mut executable, wrong_version(), DummyProposal());
    executable.terminate(version::current(), DummyProposal());

    end(scenario, extensions, account, clock);
}