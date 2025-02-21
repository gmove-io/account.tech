#[test_only]
module account_protocol::issuer_tests;

// === Imports ===

use std::type_name;
use sui::test_scenario as ts;
use account_protocol::issuer;

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;
public struct WrongWitness() has drop;

// === Tests ===

#[test]
fun test_issuer() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::new(@0x0, b"dummy".to_string(), DummyIntent());
    // assertions
    issuer.assert_is_account(@0x0);
    issuer.assert_is_intent(DummyIntent());
    // getters 
    assert!(issuer.account_addr() == @0x0);
    assert!(issuer.intent_key() == b"dummy".to_string());
    assert!(issuer.intent_type() == type_name::get<DummyIntent>());

    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_wrong_witness() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::new(@0x0, b"dummy".to_string(), DummyIntent());
    // assertions
    issuer.assert_is_intent(WrongWitness());

    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_wrong_account() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::new(@0x0, b"dummy".to_string(), DummyIntent());
    // assertions
    issuer.assert_is_account(@0x1);

    ts::end(scenario);
}