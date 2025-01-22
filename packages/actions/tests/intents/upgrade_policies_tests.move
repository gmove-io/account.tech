#[test_only]
module account_actions::upgrade_policies_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::Account;
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    upgrade_policies,
    upgrade_policies_intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock, UpgradeCap) {
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
    account.deps_mut_for_testing().add(&extensions, b"AccountConfig".to_string(), @account_config, 1);
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let clock = clock::create_for_testing(scenario.ctx());
    let upgrade_cap = package::test_publish(@0x1.to_id(), scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, upgrade_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock) {
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

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_upgrade(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        2000, 
        b"Degen".to_string(),
        b"", 
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);

    let ticket = upgrade_policies_intents::execute_upgrade(&mut executable, &mut account, &clock);
    let receipt = ticket.test_upgrade();
    upgrade_policies_intents::complete_upgrade(executable, &mut account, receipt);

    let mut expired = account.destroy_empty_intent(key);
    upgrade_policies::delete_upgrade(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_restrict_all() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_restrict(
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
    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies_intents::execute_restrict(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    upgrade_policies::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_restrict(
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
    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies_intents::execute_restrict(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    upgrade_policies::delete_restrict(&mut expired);
    expired.destroy_empty();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_restrict(
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
    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies_intents::execute_restrict(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    upgrade_policies::delete_restrict(&mut expired);
    expired.destroy_empty();
    // lock destroyed with upgrade cap
    assert!(!upgrade_policies::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies_intents::ENoLock)]
fun test_error_request_upgrade_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_upgrade(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(),
        2000, 
        b"Degen".to_string(), 
        b"", 
        &clock, 
        scenario.ctx()
    );

    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies_intents::ENoLock)]
fun test_error_request_restrict_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    upgrade_policies_intents::request_restrict(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0,
        2000, 
        b"Degen".to_string(), 
        128, 
        scenario.ctx()
    );

    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}
