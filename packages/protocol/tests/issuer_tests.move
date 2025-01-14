#[test_only]
module account_protocol::issuer_tests;

// === Imports ===

use std::string::String;
use sui::test_scenario as ts;
use account_protocol::issuer;

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;

// === Helpers ===

fun full_role(): String {
    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::issuer_tests::Degen");
    full_role
}

// === Tests ===

#[test]
fun test_issuer() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"Degen".to_string());
    // assertions
    issuer.assert_is_account(@0x0);
    issuer.assert_is_constructor(DummyIntent());
    // getters 
    assert!(issuer.full_role() == full_role());
    assert!(issuer.account_addr() == @0x0);
    assert!(issuer.package_id() == @account_protocol.to_string());
    assert!(issuer.module_name() == b"issuer_tests".to_string());
    assert!(issuer.opt_name() == b"Degen".to_string());

    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_wrong_witness() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"Degen".to_string());
    // assertions
    issuer.assert_is_constructor(issuer::wrong_witness());

    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_wrong_account() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"Degen".to_string());
    // assertions
    issuer.assert_is_account(@0x1);

    ts::end(scenario);
}