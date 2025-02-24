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
    account::{Self, Account},
    intents::Intent,
    issuer,
    deps,
    version_witness,
};
use account_actions::{
    version,
    access_control,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;
public struct Witness() has copy, drop;

public struct Cap has key, store { id: UID }
public struct WrongCap has store {}

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let mut account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config, Outcome>, clock: Clock) {
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
    account: &mut Account<Config, Outcome>, 
): Intent<Outcome> {
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock_cap() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!access_control::has_lock<Config, Outcome, Cap>(&account));
    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    assert!(access_control::has_lock<Config, Outcome, Cap>(&account));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());

    assert!(access_control::has_lock<Config, Outcome, Cap>(&account));
    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());
    assert!(!access_control::has_lock<Config, Outcome, Cap>(&account));
    // do something with the cap
    access_control::return_borrowed(&mut account, borrow, cap, version::current());
    assert!(access_control::has_lock<Config, Outcome, Cap>(&account));

    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_access_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
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

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::ENoLock)]
fun test_error_access_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());

    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control::EWrongAccount)]
fun test_error_return_to_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());

    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, DummyIntent>(&mut executable, &mut account, version::current(), DummyIntent());
    // create other account
    let mut account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
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

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    // create other account and lock same type of cap
    let mut account2 = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let auth = account2.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account2, cap(&mut scenario));
    
    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, DummyIntent>(&mut executable, &mut account2, version::current(), DummyIntent());

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

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    
    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, WrongWitness>(&mut executable, &mut account, version::current(), WrongWitness());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_access_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    access_control::new_borrow<Config, Outcome, Cap, DummyIntent>(&mut intent, &account, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    
    let (borrow, cap) = access_control::do_borrow<Config, Outcome, Cap, DummyIntent>(&mut executable, &mut account, version_witness::new_for_testing(@0xFA153), DummyIntent());

    destroy(executable);
    destroy(borrow);
    destroy(cap);
    end(scenario, extensions, account, clock);
}