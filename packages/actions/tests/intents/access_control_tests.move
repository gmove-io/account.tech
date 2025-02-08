#[test_only]
module account_actions::access_control_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::Account;
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    access_control_intents,
    access_control,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Cap has key, store { id: UID }

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

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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

// === Tests ===

#[test]
fun test_request_execute_borrow_cap() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    access_control::lock_cap(auth, &mut account, cap(&mut scenario));
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    access_control_intents::request_borrow_cap<Multisig, Approvals, Cap>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0],
        1, 
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account));
    let (borrow, cap) = access_control_intents::execute_borrow_cap<Multisig, Approvals, Cap>(&mut executable, &mut account);
    assert!(!access_control::has_lock<Multisig, Approvals, Cap>(&account));
    // do something with the cap
    access_control_intents::complete_borrow_cap(executable, &mut account, borrow, cap);
    assert!(access_control::has_lock<Multisig, Approvals, Cap>(&account)); 

    let mut expired = account.destroy_empty_intent(key);
    access_control::delete_borrow<Cap>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = access_control_intents::ENoLock)]
fun test_error_request_borrow_cap_no_lock() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    access_control_intents::request_borrow_cap<Multisig, Approvals, Cap>(
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
