#[test_only]
module account_protocol::executable_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    bag,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    executable,
    deps,
    issuer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyProposal() has drop;

public struct DummyAction has store {}
public struct WrongAction has store {}

// === Helpers ===

fun start(): (Scenario, Extensions) {
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
    extensions.add(&cap, b"External".to_string(), @0xA, 1);
    // create world
    destroy(cap);
    (scenario, extensions)
}

fun end(scenario: Scenario, extensions: Extensions) {
    destroy(extensions);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_executable_flow() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});
    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    // verify initial state (pending action)
    assert!(executable.deps().length() == 3);
    assert!(executable.issuer().account_addr() == @0x0);
    assert!(!executable.action_is_completed<DummyAction>());
    // first step: execute action
    let _action_mut = executable.load<DummyAction, DummyProposal>(@0x0, version::current(), DummyProposal());
    executable.process<DummyAction, DummyProposal>(version::current(), DummyProposal());
    assert!(executable.action_is_completed<DummyAction>());
    // second step: destroy action
    let DummyAction {} = executable.cleanup(version::current(), DummyProposal());
    assert!(!executable.action_is_completed<DummyAction>());
    executable.terminate(version::current(), DummyProposal());

    end(scenario, extensions);
}

#[test, expected_failure(abort_code = executable::EActionNotFound)]
fun test_error_cannot_load_action() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});
    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    let _action_mut = executable.load<WrongAction, DummyProposal>(@0x0, version::current(), DummyProposal());

    destroy(executable);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = executable::EActionNotPending)]
fun test_error_cannot_process_action() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});

    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    executable.process<WrongAction, DummyProposal>(version::current(), DummyProposal());

    destroy(executable);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = executable::EActionNotCompleted)]
fun test_error_cannot_cleanup_action() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});

    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    executable.process<DummyAction, DummyProposal>(version::current(), DummyProposal());
    let action = executable.cleanup<WrongAction, DummyProposal>(version::current(), DummyProposal());

    destroy(action);
    destroy(executable);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = executable::EPendingNotEmpty)]
fun test_error_cannot_terminate_pending_remaining() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});
    actions.add(1, DummyAction {});

    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    executable.process<DummyAction, DummyProposal>(version::current(), DummyProposal());
    let action = executable.cleanup<DummyAction, DummyProposal>(version::current(), DummyProposal());
    executable.terminate(version::current(), DummyProposal());

    destroy(action);
    end(scenario, extensions);
}

#[test, expected_failure(abort_code = executable::ECompletedNotEmpty)]
fun test_error_cannot_terminate_completed_remaining() {
    let (mut scenario, extensions) = start();

    let deps = deps::new(&extensions);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut actions = bag::new(scenario.ctx());
    actions.add(0, DummyAction {});
    actions.add(1, DummyAction {});

    let mut executable = executable::new(deps, issuer, actions, scenario.ctx());
    executable.process<DummyAction, DummyProposal>(version::current(), DummyProposal());
    executable.process<DummyAction, DummyProposal>(version::current(), DummyProposal());
    let action = executable.cleanup<DummyAction, DummyProposal>(version::current(), DummyProposal());
    executable.terminate(version::current(), DummyProposal());

    destroy(action);
    end(scenario, extensions);
}
