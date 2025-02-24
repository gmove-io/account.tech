#[test_only]
module account_actions::access_control_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    version_witness,
};
use account_actions::{
    access_control_intents,
    access_control,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ACCOUNT_PROTOCOL: address = @0x1;

// === Structs ===

public struct Cap has key, store { id: UID }

// Define Config, Outcome, and Witness structs
public struct Witness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    account::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    // Create account using account_protocol
    let account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()], vector[@account_protocol, @account_actions], vector[1, 1], scenario.ctx());
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

// === Tests ===

#[test]
fun test_request_execute_borrow_cap() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = account.new_auth(version::current(), Witness());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    access_control_intents::request_borrow_cap<Config, Outcome, Cap>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        scenario.ctx()
    );

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    assert!(access_control::has_lock<Config, Outcome, Cap>(&account));
    let (borrow, cap) = access_control_intents::execute_borrow_cap<Config, Outcome, Cap>(&mut executable, &mut account);
    assert!(!access_control::has_lock<Config, Outcome, Cap>(&account));
    // do something with the cap
    access_control_intents::complete_borrow_cap(executable, &mut account, borrow, cap);
    assert!(access_control::has_lock<Config, Outcome, Cap>(&account)); 

    let mut expired = account.destroy_empty_intent(key);
    access_control::delete_borrow<Cap>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control_intents::ENoLock)]
fun test_error_request_borrow_cap_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    access_control_intents::request_borrow_cap<Config, Outcome, Cap>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}
