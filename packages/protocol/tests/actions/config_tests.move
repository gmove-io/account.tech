#[test_only]
module account_protocol::config_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    config,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

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
    extensions.add(&cap, b"AccountMultisig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // add external dep
    extensions.add(&cap, b"External".to_string(), @0xABC, 1);
    // Account generic types are dummy types (bool, bool)
    let account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
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

// === Tests ===

#[test]
fun test_edit_config_metadata() {
    let (scenario, extensions, mut account, clock) = start();    
    assert!(account.metadata().size() == 0);

    let auth = account.new_auth(version::current(), Witness());
    config::edit_metadata(
        auth, 
        &mut account,
        vector[b"name".to_string()], 
        vector[b"New Name".to_string()], 
    );

    assert!(account.metadata().get(b"name".to_string()) == b"New Name".to_string());
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_config_deps() {
    let (mut scenario, extensions, mut account, clock) = start();    
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    config::request_config_deps(
        auth, 
        Outcome {}, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        &extensions,
        vector[b"AccountProtocol".to_string(), b"External".to_string()], 
        vector[@account_protocol, @0xABC], 
        vector[1, 1], 
        scenario.ctx()
    );
    assert!(!account.deps().contains_name(b"External".to_string()));

    let (executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    config::execute_config_deps(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();
    
    let package = account.deps().get_by_name(b"External".to_string());
    assert!(package.addr() == @0xABC);
    assert!(package.version() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_deps_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();    
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    config::request_config_deps(
        auth, 
        Outcome {}, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        &extensions,
        vector[b"External".to_string()], 
        vector[@0xABC], 
        vector[1], 
        scenario.ctx()
    );
    
    let mut expired = account.delete_expired_intent(key, &clock);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_toggle_unverified_allowed() {
    let (mut scenario, extensions, mut account, clock) = start();    
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    config::request_toggle_unverified_allowed(
        auth, 
        Outcome {}, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        scenario.ctx()
    );

    let (executable, _) = account.execute_intent(key, &clock, version::current(), Witness());
    config::execute_toggle_unverified_allowed(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    config::delete_toggle_unverified_allowed(&mut expired);
    expired.destroy_empty();
    
    assert!(account.deps().unverified_allowed() == true);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_toggle_unverified_allowed_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();    
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    config::request_toggle_unverified_allowed(
        auth, 
        Outcome {}, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        scenario.ctx()
    );
    
    let mut expired = account.delete_expired_intent(key, &clock);
    config::delete_toggle_unverified_allowed(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}