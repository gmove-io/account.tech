#[test_only]
module account_multisig::config_tests;

// === Imports ===

use std::string::String;
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
};
use account_multisig::{
    multisig::{Self, Multisig, Approvals},
    config,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

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
    // Account generic types are dummy types (bool, bool)
    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.config_mut(version::current(), multisig::config_witness()).add_role_to_multisig(full_role(), 1);
    account.config_mut(version::current(), multisig::config_witness()).member_mut(OWNER).add_role_to_member(full_role());
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

fun full_role(): String {
    let mut full_role = @account_multisig.to_string();
    full_role.append_utf8(b"::multisig_tests::Degen");
    full_role
}

// === Tests ===

#[test]
fun test_config_multisig() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();

    config::request_config_multisig(
        auth,
        outcome,
        &mut account,
        b"config".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        vector[OWNER, @0xBABE], 
        vector[2, 1], 
        vector[vector[full_role()], vector[]], 
        2, 
        vector[full_role()], 
        vector[1], 
        scenario.ctx()
    );
    multisig::approve_intent(&mut account, b"config".to_string(), scenario.ctx());
    let executable = multisig::execute_intent(&mut account, b"config".to_string(), &clock);
    config::execute_config_multisig(executable, &mut account);

    let mut expired = account.destroy_empty_intent(b"config".to_string());
    config::delete_config_multisig(&mut expired);
    expired.destroy_empty();

    assert!(account.config().addresses() == vector[OWNER, @0xBABE]);
    assert!(account.config().member(OWNER).weight() == 2);
    assert!(account.config().member(OWNER).roles() == vector[full_role()]);
    assert!(account.config().member(@0xBABE).weight() == 1);
    assert!(account.config().member(@0xBABE).roles() == vector[]);
    assert!(account.config().get_global_threshold() == 2);
    assert!(account.config().get_role_threshold(full_role()) == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_multisig_deletion() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();

    config::request_config_multisig(
        auth,
        outcome,
        &mut account, 
        b"config".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        vector[OWNER, @0xBABE], 
        vector[2, 1],
        vector[vector[full_role()], vector[]], 
        2, 
        vector[full_role()], 
        vector[1], 
        scenario.ctx()
    );
    let mut expired = account.delete_expired_intent(b"config".to_string(), &clock);
    config::delete_config_multisig(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}