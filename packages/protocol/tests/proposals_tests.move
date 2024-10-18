#[test_only]
module account_protocol::proposals_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario as ts,
    clock,
};
use account_protocol::{
    proposals,
    issuer,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyProposal() has drop;

public struct DummyAction has store {}

// === Tests ===

#[test]
fun test_proposals_getters() {
    let mut scenario = ts::begin(OWNER);

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal1 = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposals.add(proposal1);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal2 = proposals::new_proposal(issuer, b"two".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposals.add(proposal2);
    // check proposals getters
    assert!(proposals.length() == 2);
    assert!(proposals.contains(b"one".to_string()));
    assert!(proposals.contains(b"two".to_string()));
    assert!(proposals.get_idx(b"one".to_string()) == 0);
    assert!(proposals.get_idx(b"two".to_string()) == 1);
    let proposal_mut1 = proposals.get_mut(b"one".to_string());
    let outcome = proposal_mut1.outcome_mut();
    assert!(outcome == true);
    // check proposal getters
    let proposal1 = proposals.get(b"one".to_string());
    assert!(proposal1.issuer().account_addr() == @0x0);
    assert!(proposal1.description() == b"".to_string());
    assert!(proposal1.expiration_epoch() == 0);
    assert!(proposal1.execution_time() == 0);
    assert!(proposal1.actions_length() == 0);
    assert!(proposal1.outcome() == true);

    destroy(proposals);
    scenario.end();
}

#[test]
fun test_actions() {
    let mut scenario = ts::begin(OWNER);

    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut proposal = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposal.add_action(DummyAction {}, DummyProposal());
    assert!(proposal.actions_length() == 1);

    destroy(proposal);
    scenario.end();
}

#[test]
fun test_remove_proposal() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposals.add(proposal);
    // remove proposal
    let (issuer, actions, outcome) = proposals.remove(b"one".to_string(), &clock);
    assert!(issuer.account_addr() == @0x0);
    assert!(outcome == true);
    actions.destroy_empty();

    destroy(proposals);
    destroy(clock);
    scenario.end();
}

#[test]
fun test_delete_proposal() {
    let mut scenario = ts::begin(OWNER);

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut proposal = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposal.add_action(DummyAction {}, DummyProposal());
    proposals.add(proposal);
    // remove proposal
    let mut expired = proposals.delete(b"one".to_string(), scenario.ctx());
    let action: DummyAction = expired.remove_expired_action();
    let outcome = expired.remove_expired_outcome();

    destroy(action);
    destroy(outcome);
    destroy(proposals);
    scenario.end();
}

#[test, expected_failure(abort_code = proposals::EProposalKeyAlreadyExists)]
fun test_error_key_already_exists() {
    let mut scenario = ts::begin(OWNER);

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal1 = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposals.add(proposal1);
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal2 = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 0, true, scenario.ctx());
    proposals.add(proposal2);

    destroy(proposals);
    scenario.end();
}

#[test, expected_failure(abort_code = proposals::EProposalNotFound)]
fun test_error_get_proposal() {
    let scenario = ts::begin(OWNER);

    let proposals = proposals::empty<bool>();
    let _ = proposals.get(b"one".to_string());

    destroy(proposals);
    scenario.end();
}

#[test, expected_failure(abort_code = proposals::EProposalNotFound)]
fun test_error_get_mut_proposal() {
    let scenario = ts::begin(OWNER);

    let mut proposals = proposals::empty<bool>();
    let _ = proposals.get_mut(b"one".to_string());

    destroy(proposals);
    scenario.end();
}

#[test, expected_failure(abort_code = proposals::ECantBeExecutedYet)]
fun test_error_cant_be_executed_yet() {
    let mut scenario = ts::begin(OWNER);
    let clock = clock::create_for_testing(scenario.ctx());

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let proposal = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 1, 0, true, scenario.ctx());
    proposals.add(proposal);
    // remove proposal
    let (issuer, actions, outcome) = proposals.remove(b"one".to_string(), &clock);

    destroy(issuer);
    destroy(actions);
    destroy(outcome);
    destroy(proposals);
    destroy(clock);
    scenario.end();
}

#[test, expected_failure(abort_code = proposals::EHasntExpired)]
fun test_error_cant_delete_proposal_not_expired() {
    let mut scenario = ts::begin(OWNER);

    let mut proposals = proposals::empty<bool>();
    let issuer = issuer::construct(@0x0, version::current(), DummyProposal(), b"".to_string());
    let mut proposal = proposals::new_proposal(issuer, b"one".to_string(), b"".to_string(), 0, 1, true, scenario.ctx());
    proposal.add_action(DummyAction {}, DummyProposal());
    proposals.add(proposal);
    // remove proposal
    let mut expired = proposals.delete(b"one".to_string(), scenario.ctx());
    let action: DummyAction = expired.remove_expired_action();
    let outcome = expired.remove_expired_outcome();

    destroy(action);
    destroy(outcome);
    destroy(proposals);
    scenario.end();
}

