#[test_only]
module account_protocol::executable_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario as ts,
};
use account_protocol::{
    executable,
    issuer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;
public struct WrongIntent() has drop;

// === Tests ===

#[test]
fun test_executable_flow() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut executable = executable::new(b"one".to_string(), issuer);
    // verify initial state (pending action)
    assert!(executable.key() == b"one".to_string());
    assert!(executable.issuer().account_addr() == @0x0);
    assert!(executable.action_idx() == 0);
    // first step: execute action
    let (key, action_idx) = executable.next_action<DummyIntent>(@0x0, DummyIntent());
    assert!(key == b"one".to_string());
    assert!(action_idx == 0);
    assert!(executable.action_idx() == 1);
    // second step: destroy executable
    executable.destroy(1, DummyIntent());

    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_next_action_wrong_witness() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut executable = executable::new(b"one".to_string(), issuer);
    let (_, _) = executable.next_action(@0x0, issuer::wrong_witness());

    destroy(executable);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_cannot_next_action_wrong_account() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut executable = executable::new(b"one".to_string(), issuer);
    let (_, _) = executable.next_action<DummyIntent>(@0x1, DummyIntent());

    destroy(executable);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = executable::EActionsRemaining)]
fun test_error_cannot_destroy_actions_remaining() {
    let scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let executable = executable::new(b"one".to_string(), issuer);
    executable.destroy(1, DummyIntent());

    ts::end(scenario);
}
