#[test_only]
module account_protocol::issuer_tests;

// === Imports ===

use std::{
    type_name,
    string::String,
};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_protocol::{
    account::{Self, Account},
    issuer::Self,
    version,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyProposal() has drop;
public struct WrongWitness() has drop;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<bool, bool>) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let account = account::new(&extensions, b"Main".to_string(), true, scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<bool, bool>) {
    destroy(extensions);
    destroy(account);
    ts::end(scenario);
}

fun full_role(): String {
    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::issuer_tests::DummyProposal::Degen");
    full_role
}

// === Tests ===

#[test]
fun test_issuer() {
    let (scenario, extensions, account) = start();

    let issuer = issuer::construct(account.addr(), version::current(), DummyProposal(), b"Degen".to_string());
    // assertions
    issuer.assert_is_account(account.addr());
    issuer.assert_is_constructor(DummyProposal());
    // getters 
    assert!(issuer.full_role() == full_role());
    assert!(issuer.account_addr() == account.addr());
    assert!(issuer.role_type() == type_name::get<DummyProposal>());
    assert!(issuer.role_name() == b"Degen".to_string());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_wrong_witness() {
    let (scenario, extensions, account) = start();

    let issuer = issuer::construct(account.addr(), version::current(), DummyProposal(), b"Degen".to_string());
    // assertions
    issuer.assert_is_constructor(WrongWitness());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_wrong_account() {
    let (mut scenario, extensions, account) = start();

    let issuer = issuer::construct(account.addr(), version::current(), DummyProposal(), b"Degen".to_string());
    // assertions
    let account2 = account::new<bool, bool>(&extensions, b"Main".to_string(), true, scenario.ctx());
    issuer.assert_is_account(account2.addr());

    destroy(account2);
    end(scenario, extensions, account);
}