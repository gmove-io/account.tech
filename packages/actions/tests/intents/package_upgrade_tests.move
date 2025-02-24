#[test_only]
module account_actions::package_upgrade_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::{Self, Account};
use account_actions::{
    package_upgrade,
    package_upgrade_intents,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Witness() has drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock, UpgradeCap) {
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

    let account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()], vector[@account_protocol, @account_actions], vector[1, 1], scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    let upgrade_cap = package::test_publish(@0x1.to_id(), scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, upgrade_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config, Outcome>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_request_execute_upgrade() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    package_upgrade_intents::request_upgrade_package(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        1000,
        2000, 
        b"Degen".to_string(),
        b"", 
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (mut executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());

    let ticket = package_upgrade_intents::execute_upgrade_package(&mut executable, &mut account, &clock);
    let receipt = ticket.test_upgrade();
    package_upgrade_intents::complete_upgrade_package(executable, &mut account, receipt);

    let mut expired = account.destroy_empty_intent(key);
    package_upgrade::delete_upgrade(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_restrict_all() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), Witness());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    package_upgrade_intents::request_restrict_policy(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0,
        2000, 
        b"Degen".to_string(), 
        128, // additive
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    package_upgrade_intents::execute_restrict_policy(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    package_upgrade_intents::request_restrict_policy(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0,
        3000, 
        b"Degen".to_string(), 
        192, // deps only
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    package_upgrade_intents::execute_restrict_policy(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    package_upgrade_intents::request_restrict_policy(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0,
        4000, 
        b"Degen".to_string(), 
        255, // immutable
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    let (executable, _) = account::execute_intent(&mut account, key, &clock, version::current(), Witness());
    package_upgrade_intents::execute_restrict_policy(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();
    // lock destroyed with upgrade cap
    assert!(!package_upgrade::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}