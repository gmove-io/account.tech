#[test_only]
module account_actions::access_control_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    intents::Intent,
    issuer,
    deps,
    version_witness,
};
use account_multisig::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    access_control,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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
    extensions.add(&cap, b"AccountMultisig".to_string(), @account_multisig, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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

fun cap(scenario: &mut Scenario): Cap {
    Cap { id: object::new(scenario.ctx()) }
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
): Intent<Approvals> {
    let outcome = multisig::empty_outcome();
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        b"".to_string(), 
        outcome, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock_cap() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);

    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let (borrow, cap) = access_control::do_borrow<Multisig, Approvals, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());
    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    // do something with the cap
    access_control::return_borrowed(&mut account, borrow, cap, version::current());
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));

    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    access_control::delete_borrow<Cap>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

/// Test error: cannot return wrong cap type because of type args

#[test, expected_failure(abort_code = access_control::EAlreadyLocked)]
fun test_error_lock_cap_already_locked() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::ENoLock)]
fun test_error_access_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);

    let (borrow, cap) = access_control::do_borrow<Multisig, Approvals, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::EWrongAccount)]
fun test_error_return_to_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);

    let (borrow, cap) = access_control::do_borrow<Multisig, Approvals, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());
    // create other account
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    access_control::return_borrowed(&mut account2, borrow, cap, version::current());
    account.confirm_execution(executable, version::current(), DummyIntent());

    destroy(account2);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_access_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // create other account and lock same type of cap
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let auth = multisig::authenticate(&account2, scenario.ctx());
    access_control::lock_cap(auth, &mut account2, cap(&mut scenario));
    
    let (borrow, cap) = access_control::do_borrow<Multisig, Approvals, Cap, DummyIntent>(&mut executable, &mut account2, version::current(), DummyIntent());

    destroy(account2);
    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_access_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    
    let (borrow, cap) = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version::current(), WrongWitness());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_access_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<_, _, Cap, _>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    
    let (borrow, cap) = access_control::do_borrow<_, _, Cap, _>(&mut executable, &mut account, version_witness::new_for_testing(@0xFA153), DummyIntent());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}