#[test_only]
module account_protocol::executable_tests;

// === Imports ===

use sui::test_scenario as ts;
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

    let issuer = issuer::new(@0x0, b"one".to_string(), DummyIntent());
    let mut executable = executable::new(issuer);
    // verify initial state (pending action)
    assert!(executable.issuer().account_addr() == @0x0);
    assert!(executable.issuer().intent_key() == b"one".to_string());
    assert!(executable.action_idx() == 0);
    // first step: execute action
    let action_idx = executable.next_action();
    assert!(action_idx == 0);
    assert!(executable.action_idx() == 1);
    // second step: destroy executable
    executable.destroy();

    ts::end(scenario);
}