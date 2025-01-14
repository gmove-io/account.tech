#[test_only]
module account_protocol::intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario as ts,
    clock,
};
use account_protocol::{
    intents,
    issuer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has drop;

public struct DummyAction has store {}

// === Tests ===

#[test]
fun test_getters() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    // create intents
    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent1 = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intents.add(intent1);
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent2 = intents::new_intent(issuer, b"two".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intents.add(intent2);

    // check intents getters
    assert!(intents.length() == 2);
    assert!(intents.locked().size() == 0);
    assert!(intents.contains(b"one".to_string()));
    assert!(intents.contains(b"two".to_string()));
    assert!(intents.get_idx(b"one".to_string()) == 0);
    assert!(intents.get_idx(b"two".to_string()) == 1);

    // check intent getters
    let intent1 = intents.get(b"one".to_string());
    assert!(intent1.issuer().account_addr() == @0x0);
    assert!(intent1.description() == b"".to_string());
    assert!(intent1.execution_times() == vector[0]);
    assert!(intent1.expiration_time() == 1);
    assert!(intent1.actions().length() == 0);
    assert!(intent1.outcome() == true);
    let intent_mut1 = intents.get_mut(b"one".to_string());
    let outcome = intent_mut1.outcome_mut();
    assert!(outcome == true);

    // check expired getters
    let expired = intents.delete(b"one".to_string(), &clock);
    assert!(expired.key() == b"one".to_string());
    assert!(expired.issuer().account_addr() == @0x0);
    assert!(expired.start_index() == 0);
    assert!(expired.actions().length() == 0);

    destroy(expired);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_add_remove_action() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intent.add_action(DummyAction {}, DummyIntent());
    assert!(intent.actions().length() == 1);
    intents.add(intent);

    let mut expired = intents.delete(b"one".to_string(), &clock);
    let DummyAction {} = expired.remove_action();

    destroy(intents);
    destroy(expired);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_pop_front_execution_time() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    
    intent.pop_front_execution_time(&clock);
    assert!(intent.execution_times().is_empty());

    destroy(clock);
    destroy(intent);
    scenario.end();
}

#[test]
fun test_lock_unlock_id() {
    let scenario = ts::begin(OWNER);

    let mut intents = intents::empty<bool>();
    intents.lock(@0x1D.to_id());
    assert!(intents.locked().contains(&@0x1D.to_id()));
    intents.unlock(@0x1D.to_id());
    assert!(!intents.locked().contains(&@0x1D.to_id()));

    destroy(intents);
    scenario.end();
}

#[test]
fun test_add_destroy_intent() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intents.add(intent);
    // remove intent
    intents.get_mut(b"one".to_string()).pop_front_execution_time(&clock);
    let expired = intents.destroy(b"one".to_string());
    assert!(expired.key() == b"one".to_string());
    assert!(expired.issuer().account_addr() == @0x0);
    assert!(expired.start_index() == 0);
    assert!(expired.actions().length() == 0);

    destroy(clock);
    destroy(expired);
    destroy(intents);
    scenario.end();
}

#[test]
fun test_delete_proposal() {
    let mut scenario = ts::begin(OWNER);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intents.add(intent);
    // remove intent
    let expired = intents.delete(b"one".to_string(), &clock);
    assert!(expired.key() == b"one".to_string());
    assert!(expired.issuer().account_addr() == @0x0);
    assert!(expired.start_index() == 0);
    assert!(expired.actions().length() == 0);

    destroy(expired);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EProposalNotFound)]
fun test_error_get_proposal() {
    let scenario = ts::begin(OWNER);

    let intents = intents::empty<bool>();
    let _ = intents.get(b"one".to_string());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EProposalNotFound)]
fun test_error_get_mut_proposal() {
    let scenario = ts::begin(OWNER);

    let mut intents = intents::empty<bool>();
    let _ = intents.get_mut(b"one".to_string());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::ENoExecutionTime)]
fun test_error_no_execution_time() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[], 1, true, scenario.ctx());

    destroy(intent);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EExecutionTimesNotAscending)]
fun test_error_execution_times_not_ascending() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[1, 0], 1, true, scenario.ctx());

    destroy(intent);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::ECantBeExecutedYet)]
fun test_error_cant_be_executed_yet() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[1], 1, true, scenario.ctx());
    // remove intent
    intent.pop_front_execution_time(&clock);

    destroy(intent);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EObjectAlreadyLocked)]
fun test_error_lock_object_already_locked() {
    let scenario = ts::begin(OWNER);

    let mut intents = intents::empty<bool>();
    intents.lock(@0x1D.to_id());
    intents.lock(@0x1D.to_id());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EObjectNotLocked)]
fun test_error_unlock_object_not_locked() {
    let scenario = ts::begin(OWNER);

    let mut intents = intents::empty<bool>();
    intents.lock(@0x1D.to_id());
    intents.unlock(@0x1D1.to_id());

    destroy(intents);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::ECantBeRemovedYet)]
fun test_error_cant_be_removed_yet() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[1], 1, true, scenario.ctx());
    // remove intent
    intents.add(intent);
    let expired = intents.destroy(b"one".to_string());

    destroy(expired);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = intents::EHasntExpired)]
fun test_error_cant_delete_proposal_not_expired() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx()); 

    let mut intents = intents::empty<bool>();
    let issuer = issuer::construct(@0x0, DummyIntent(), b"".to_string());
    let mut intent = intents::new_intent(issuer, b"one".to_string(), b"".to_string(), vector[0], 1, true, scenario.ctx());
    intent.add_action(DummyAction {}, DummyIntent());
    intents.add(intent);
    // remove intent
    let expired = intents.delete(b"one".to_string(), &clock);

    destroy(expired);
    destroy(intents);
    destroy(clock);
    scenario.end();
}

