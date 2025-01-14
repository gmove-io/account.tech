#[test_only]
module account_protocol::auth_tests;

// === Imports ===

use std::string::String;
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
};
use account_protocol::{
    account::{Self, Account},
    auth,
    version,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;
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
    let account = account::new(&extensions, true, scenario.ctx());
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
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");
    full_role
}

// === Tests ===

#[test]
fun test_auth_verify() {
    let (scenario, extensions, account) = start();

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    // getters 
    assert!(auth.role() == full_role());
    assert!(auth.account_addr() == account.addr());

    auth.verify(account.addr());

    end(scenario, extensions, account);
}

#[test]
fun test_auth_verify_with_role() {
    let (scenario, extensions, account) = start();

    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");

    let auth = auth::new(&extensions, account.addr(), full_role, version::current());
    // getters 
    assert!(auth.role() == full_role);
    assert!(auth.account_addr() == account.addr());

    auth.verify_with_role<DummyIntent>(account.addr(), b"Degen".to_string());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongAccount)]
fun test_error_wrong_account() {
    let (mut scenario, extensions, account) = start();

    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");

    let auth = auth::new(&extensions, account.addr(), full_role, version::current());
    
    let account2 = account::new<bool, bool>(&extensions, true, scenario.ctx());
    auth.verify(account2.addr());

    destroy(account2);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongAccount)]
fun test_error_wrong_account_with_role() {
    let (mut scenario, extensions, account) = start();

    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");

    let auth = auth::new(&extensions, account.addr(), full_role, version::current());
    // getters 
    assert!(auth.role() == full_role);
    assert!(auth.account_addr() == account.addr());

    let account2 = account::new<bool, bool>(&extensions, true, scenario.ctx());
    auth.verify_with_role<DummyIntent>(account2.addr(), b"Degen".to_string());

    destroy(account2);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongRole)]
fun test_error_wrong_role_type() {
    let (scenario, extensions, account) = start();

    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");

    let auth = auth::new(&extensions, account.addr(), full_role, version::current());
    // getters 
    assert!(auth.role() == full_role);
    assert!(auth.account_addr() == account.addr());

    auth.verify_with_role<WrongWitness>(account.addr(), b"Degen".to_string());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongRole)]
fun test_error_wrong_role_name() {
    let (scenario, extensions, account) = start();

    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::auth_tests::DummyIntent::Degen");

    let auth = auth::new(&extensions, account.addr(), full_role, version::current());
    // getters 
    assert!(auth.role() == full_role);
    assert!(auth.account_addr() == account.addr());

    auth.verify_with_role<WrongWitness>(account.addr(), b"".to_string());

    end(scenario, extensions, account);
}