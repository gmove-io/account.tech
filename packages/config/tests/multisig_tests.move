#[test_only]
module account_config::multisig_tests;

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
use account_config::{
    multisig::{Self, Multisig, Approvals, Invite},
    version,
    user,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct DummyProposal() has drop;

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
    extensions.add(&cap, b"AccountConfig".to_string(), @account_config, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let mut account = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    account.config_mut(version::current()).add_role_to_multisig(full_role(), 1);
    account.config_mut(version::current()).member_mut(OWNER).add_role_to_member(full_role());
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
    let mut full_role = @account_config.to_string();
    full_role.append_utf8(b"::multisig_tests::DummyProposal::Degen");
    full_role
}

fun create_and_add_dummy_proposal(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
) {
    let auth = multisig::authenticate(extensions, account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    let proposal = account.create_proposal(
        auth, 
        outcome, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"dummy".to_string(), 
        b"".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
}

fun create_and_add_other_proposal(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
) {
    let auth = multisig::authenticate(extensions, account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    let proposal = account.create_proposal(
        auth, 
        outcome, 
        version::current(), 
        DummyProposal(), 
        b"".to_string(), 
        b"other".to_string(), 
        b"".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
}

// === Tests ===

#[test]
fun test_join_and_leave() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut user = user::new(scenario.ctx());

    multisig::join(&mut user, &mut account);
    assert!(user.all_ids() == vector[account.addr()]);
    multisig::leave(&mut user, &mut account);
    assert!(user.all_ids() == vector[]);

    destroy(user);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_invite_and_accept() {
    let (mut scenario, extensions, mut account, clock) = start();

    let user = user::new(scenario.ctx());
    account.config_mut(version::current()).add_member(ALICE);
    multisig::send_invite(&account, ALICE, scenario.ctx());

    scenario.next_tx(ALICE);
    let invite = scenario.take_from_sender<Invite>();
    multisig::refuse_invite(invite);
    assert!(user.all_ids() == vector[]);

    destroy(user);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_invite_and_refuse() {
    let (mut scenario, extensions, mut account, clock) = start();

    let mut user = user::new(scenario.ctx());
    account.config_mut(version::current()).add_member(ALICE);
    multisig::send_invite(&account, ALICE, scenario.ctx());

    scenario.next_tx(ALICE);
    let invite = scenario.take_from_sender<Invite>();
    multisig::accept_invite(&mut user, invite);
    assert!(user.all_ids() == vector[account.addr()]);

    destroy(user);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_members_accessors() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(account.config().addresses() == vector[OWNER]);
    assert!(account.config().member(OWNER).weight() == 1);
    assert!(account.config_mut(version::current()).member_mut(OWNER).weight() == 1);
    assert!(account.config().get_member_idx(OWNER) == 0);
    assert!(account.config().is_member(OWNER));
    account.config().assert_is_member(scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_member_getters() {
    let (scenario, extensions, account, clock) = start();

    assert!(account.config().member(OWNER).weight() == 1);
    assert!(account.config().member(OWNER).roles() == vector[full_role()]);
    assert!(account.config().member(OWNER).has_role(full_role()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_roles_getters() {
    let (scenario, extensions, mut account, clock) = start();
    account.config_mut(version::current()).add_role_to_multisig(full_role(), 1);

    assert!(account.config().get_global_threshold() == 1);
    assert!(account.config().get_role_threshold(full_role()) == 1);
    assert!(account.config().get_role_idx(full_role()) == 0);
    assert!(account.config().role_exists(full_role()));

    end(scenario, extensions, account, clock);
}

// outcome getters tested in the test below

#[test]
fun test_proposal_approval() {
    let (mut scenario, extensions, mut account, clock) = start();

    // create proposal
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    // approve
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    let outcome = account.proposal(b"dummy".to_string()).outcome();
    assert!(outcome.total_weight() == 1);
    assert!(outcome.role_weight() == 1); // OWNER has the role
    assert!(outcome.approved() == vector[OWNER]);
    // disapprove
    multisig::disapprove_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    let outcome = account.proposal(b"dummy".to_string()).outcome();
    assert!(outcome.total_weight() == 0);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[]);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_approval_with_role() {
    let (mut scenario, extensions, mut account, clock) = start();
    // create proposal
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    // approve with role
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    let outcome = account.proposal(b"dummy".to_string()).outcome();
    assert!(outcome.total_weight() == 1);
    assert!(outcome.role_weight() == 1);
    assert!(outcome.approved() == vector[OWNER]);
    // disapprove with role
    multisig::disapprove_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    let outcome = account.proposal(b"dummy".to_string()).outcome();
    assert!(outcome.total_weight() == 0);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[]);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_approval_without_role() {
    let (mut scenario, extensions, mut account, clock) = start();
    account.config_mut(version::current()).member_mut(OWNER).remove_role_from_member(full_role());
    // create proposal
    create_and_add_other_proposal(&mut scenario, &mut account, &extensions);
    // approve WITHOUT role
    multisig::approve_proposal(&mut account, b"other".to_string(), scenario.ctx());
    let outcome = account.proposal(b"other".to_string()).outcome();
    assert!(outcome.total_weight() == 1);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[OWNER]);
    // add role to OWNER
    account.config_mut(version::current()).member_mut(OWNER).add_role_to_member(full_role());
    // disapprove with role (shouldn't throw)
    multisig::disapprove_proposal(&mut account, b"other".to_string(), scenario.ctx());
    let outcome = account.proposal(b"other".to_string()).outcome();
    assert!(outcome.total_weight() == 0);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[]);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_disapprove_with_higher_weight() {
    let (mut scenario, extensions, mut account, clock) = start();
    account.config_mut(version::current()).member_mut(OWNER).remove_role_from_member(full_role());
    // create proposal
    create_and_add_other_proposal(&mut scenario, &mut account, &extensions);
    // approve WITHOUT role
    multisig::approve_proposal(&mut account, b"other".to_string(), scenario.ctx());
    let outcome = account.proposal(b"other".to_string()).outcome();
    assert!(outcome.total_weight() == 1);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[OWNER]);
    // increase OWNER's weight
    account.config_mut(version::current()).member_mut(OWNER).set_weight(2);
    // disapprove with role (shouldn't throw)
    multisig::disapprove_proposal(&mut account, b"other".to_string(), scenario.ctx());
    let outcome = account.proposal(b"other".to_string()).outcome();
    assert!(outcome.total_weight() == 0);
    assert!(outcome.role_weight() == 0);
    assert!(outcome.approved() == vector[]);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_approve_multiple() {
    let (mut scenario, extensions, mut account, clock) = start();
    // create proposals
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    create_and_add_other_proposal(&mut scenario, &mut account, &extensions);
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    create_and_add_other_proposal(&mut scenario, &mut account, &extensions);
    // approve all dummy proposals
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    // check dummy are approved
    let idx = account.proposals().all_idx(b"dummy".to_string());
    idx.do!(|i| {
        let outcome = account.proposal_mut(i, version::current()).outcome();
        assert!(outcome.total_weight() == 1);
        assert!(outcome.approved() == vector[OWNER]);
    });
    // check other aren't approved
    let idx = account.proposals().all_idx(b"other".to_string());
    idx.do!(|i| {
        let outcome = account.proposal_mut(i, version::current()).outcome();
        assert!(outcome.total_weight() == 0);
        assert!(outcome.approved() == vector[]);
    });
    // disapprove all dummy proposals
    multisig::disapprove_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    // check dummy are approved
    let idx = account.proposals().all_idx(b"dummy".to_string());
    idx.do!(|i| {
        let outcome = account.proposal_mut(i, version::current()).outcome();
        assert!(outcome.total_weight() == 0);
        assert!(outcome.approved() == vector[]);
    });

    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_execution() {
    let (mut scenario, extensions, mut account, clock) = start();

    // create proposal
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    // approve
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    // execute proposal
    let executable = multisig::execute_proposal(&mut account, b"dummy".to_string(), &clock);
    assert!(executable.issuer().full_role() == full_role());

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_proposal_deletion() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);

    // create proposal
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    // execute proposal
    let expired = multisig::delete_proposal(&mut account, b"dummy".to_string(), &clock);
    let outcome = expired.remove_expired_outcome();

    destroy(outcome);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_multisig() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account,
        outcome,
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
    multisig::approve_proposal(&mut account, b"config".to_string(), scenario.ctx());
    let executable = multisig::execute_proposal(&mut account, b"config".to_string(), &clock);
    multisig::execute_config_multisig(executable, &mut account);

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
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
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
    let mut expired = multisig::delete_proposal(&mut account, b"config".to_string(), &clock);
    multisig::delete_expired_config_multisig(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ECallerIsNotMember)]
fun test_error_empty_outcome_not_member() {
    let (mut scenario, extensions, account, clock) = start();

    scenario.next_tx(ALICE);
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    destroy(outcome);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ECallerIsNotMember)]
fun test_error_authenticate_not_member() {
    let (mut scenario, extensions, account, clock) = start();

    scenario.next_tx(ALICE);
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());

    destroy(auth);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ERoleNotFound)]
fun test_error_authenticate_member_no_role() {
    let (mut scenario, extensions, mut account, clock) = start();
    account.config_mut(version::current()).add_member(ALICE);

    scenario.next_tx(ALICE);
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());

    destroy(auth);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EAlreadyApproved)]
fun test_error_already_approved() {
    let (mut scenario, extensions, mut account, clock) = start();
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);

    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EMemberNotFound)]
fun test_error_approve_not_member() {
    let (mut scenario, extensions, mut account, clock) = start();
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);

    scenario.next_tx(ALICE);
    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ENotApproved)]
fun test_error_disapprove_not_approved() {
    let (mut scenario, extensions, mut account, clock) = start();
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    multisig::disapprove_proposal(&mut account, b"dummy".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EMemberNotFound)]
fun test_error_disapprove_not_member() {
    let (mut scenario, extensions, mut account, clock) = start();
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);

    multisig::approve_proposal(&mut account, b"dummy".to_string(), scenario.ctx());
    account.config_mut(version::current()).remove_member(OWNER);
    multisig::disapprove_proposal(&mut account, b"dummy".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ENotMember)]
fun test_invite_not_member() {
    let (mut scenario, extensions, account, clock) = start();

    let user = user::new(scenario.ctx());
    multisig::send_invite(&account, ALICE, scenario.ctx());

    destroy(user);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EThresholdNotReached)]
fun test_error_outcome_validate_global_threshold_reached() {
    let (mut scenario, extensions, mut account, clock) = start();
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    let executable = multisig::execute_proposal(&mut account, b"dummy".to_string(), &clock);

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EThresholdNotReached)]
fun test_error_outcome_validate_no_threshold_reached() {
    let (mut scenario, extensions, mut account, clock) = start();
    account.config_mut(version::current()).add_role_to_multisig(full_role(), 2);
    
    create_and_add_dummy_proposal(&mut scenario, &mut account, &extensions);
    let executable = multisig::execute_proposal(&mut account, b"dummy".to_string(), &clock);

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EMembersNotSameLength)]
fun test_error_verify_rules_addresses_weights_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[OWNER, @0xBABE], 
        vector[2], 
        vector[vector[full_role()], vector[]], 
        1, 
        vector[], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EMembersNotSameLength)]
fun test_error_verify_rules_addresses_roles_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[OWNER, @0xBABE], 
        vector[2, 1], 
        vector[vector[full_role()]], 
        1, 
        vector[], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ERolesNotSameLength)]
fun test_error_verify_rules_roles_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[], 
        vector[], 
        vector[], 
        1, 
        vector[full_role()], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EThresholdTooHigh)]
fun test_error_verify_rules_global_threshold_too_high() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[], 
        vector[], 
        vector[], 
        2, 
        vector[], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EThresholdNull)]
fun test_error_verify_rules_global_threshold_null() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[], 
        vector[], 
        vector[], 
        0, 
        vector[], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ERoleNotAdded)]
fun test_error_verify_rules_role_not_added_but_given() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[OWNER], 
        vector[1], 
        vector[vector[full_role()]], 
        1, 
        vector[], 
        vector[], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EThresholdTooHigh)]
fun test_error_verify_rules_role_threshold_too_high() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, full_role(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());

    multisig::propose_config_multisig(
        auth,
        &mut account, 
        outcome,
        b"config".to_string(), 
        b"".to_string(), 
        0,
        1, 
        vector[OWNER], 
        vector[1], 
        vector[vector[full_role()]], 
        1, 
        vector[full_role()], 
        vector[2], 
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::EMemberNotFound)]
fun test_error_get_member_idx_not_found() {
    let (scenario, extensions, account, clock) = start();

    assert!(account.config().get_member_idx(ALICE) == 1);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = multisig::ERoleNotFound)]
fun test_error_get_role_idx_not_found() {
    let (scenario, extensions, account, clock) = start();

    assert!(account.config().get_role_idx(b"".to_string()) == 1);

    end(scenario, extensions, account, clock);
}
