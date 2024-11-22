#[test_only]
module account_actions::upgrade_policies_tests;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String,    
};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    proposals::Proposal,
    issuer,
    deps,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    upgrade_policies,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyProposal() has copy, drop;
public struct WrongProposal() has copy, drop;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock, UpgradeCap) {
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
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);
    // Account generic types are dummy types (bool, bool)
    let mut account = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    account.config_mut(version::current()).add_role_to_multisig(role(b"LockCommand", b""), 1);
    account.config_mut(version::current()).member_mut(OWNER).add_role_to_member(role(b"LockCommand", b""));
    let clock = clock::create_for_testing(scenario.ctx());
    let upgrade_cap = package::test_publish(@0x1.to_id(), scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, upgrade_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun role(action: vector<u8>, name: vector<u8>): String {
    let mut full_role = @account_actions.to_string();
    full_role.append_utf8(b"::upgrade_policies::");
    full_role.append_utf8(action);
    full_role.append_utf8(b"::");
    full_role.append_utf8(name);
    full_role
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun create_dummy_proposal(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Proposal<Approvals> {
    let auth = multisig::authenticate(extensions, account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    account.create_proposal(
        auth, 
        outcome, 
        version::current(), 
        DummyProposal(), 
        b"".to_string(), 
        b"dummy".to_string(), 
        b"".to_string(), 
        0,
        1, 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    assert!(upgrade_policies::has_cap(&account, @0x1));
    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.package() == @0x1.to_id());

    let rules = upgrade_policies::borrow_rules(&account, @0x1);
    assert!(rules.cap_id() == object::id(cap));
    assert!(rules.name() == b"Degen".to_string());
    assert!(rules.time_delay() == 1000);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_propose_execute_upgrade() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_upgrade(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        2000, 
        @0x1, 
        b"", 
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);

    let (ticket, cap, rules) = upgrade_policies::execute_upgrade(&mut executable, &mut account);
    let receipt = ticket.test_upgrade();
    upgrade_policies::complete_upgrade(executable, &mut account, receipt, cap, rules);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_propose_execute_restrict_all() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_restrict(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        2000, 
        @0x1, 
        128, // additive
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::execute_restrict(executable, &mut account);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_restrict(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        3000, 
        @0x1, 
        192, // deps only
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::execute_restrict(executable, &mut account);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_restrict(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        4000, 
        @0x1, 
        255, // immutable
        &clock, 
        scenario.ctx()
    );

    clock.increment_for_testing(1000);
    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::execute_restrict(executable, &mut account);
    // lock destroyed with upgrade cap
    assert!(!upgrade_policies::has_cap(&account, @0x1));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_flow() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        cap, 
        rules, 
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_additive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 128, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 128);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_deps_only() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 192, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 192);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_immutable() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 255, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    assert!(!upgrade_policies::has_cap(&account, @0x1));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    let mut expired = account.delete_proposal(key, version::current(), &clock);
    upgrade_policies::delete_upgrade_action(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 128, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    let mut expired = account.delete_proposal(key, version::current(), &clock);
    upgrade_policies::delete_restrict_action(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::ELockAlreadyExists)]
fun test_error_lock_name_already_exists() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let upgrade_cap1 = package::test_publish(@0x1.to_id(), scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap1, b"Degen".to_string(), 1000);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::ENoLock)]
fun test_error_propose_upgrade_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_upgrade(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        2000, 
        @0x1, 
        b"", 
        &clock, 
        scenario.ctx()
    );

    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::EWrongUpgradeCap)]
fun test_upgrade_return_wrong_cap() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        package::test_publish(@0x1.to_id(), scenario.ctx()), 
        rules, 
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    destroy(cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::ENoLock)]
fun test_error_propose_restrict_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    upgrade_policies::propose_restrict(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        2000, 
        @0x1, 
        128, 
        &clock, 
        scenario.ctx()
    );

    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::EPolicyShouldRestrict)]
fun test_error_new_restrict_not_restrictive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 0, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::EInvalidPolicy)]
fun test_error_new_restrict_invalid_policy() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_restrict(&mut proposal, @0x1, 0, 1, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    destroy(account2);
    destroy(executable);
    destroy(ticket);
    destroy(cap);
    destroy(rules);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongProposal(),
    );

    destroy(executable);
    destroy(ticket);
    destroy(cap);
    destroy(rules);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        wrong_version(), 
        DummyProposal(),
    );

    destroy(executable);
    destroy(ticket);
    destroy(cap);
    destroy(rules);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_confirm_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    account2.config_mut(version::current()).add_role_to_multisig(role(b"LockCommand", b""), 1);
    account2.config_mut(version::current()).member_mut(OWNER).add_role_to_member(role(b"LockCommand", b""));
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    let auth = multisig::authenticate(&extensions, &account2, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account2, package::test_publish(@0x1.to_id(), scenario.ctx()), b"Degen".to_string(), 1000);
    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account2, 
        version::current(), 
        DummyProposal(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        cap, 
        rules, 
        version::current(), 
        DummyProposal(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_confirm_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        cap, 
        rules, 
        version::current(), 
        WrongProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_confirm_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the proposal
    let (ticket, cap, rules) = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        cap, 
        rules, 
        wrong_version(), 
        DummyProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_restrict_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the proposal
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyProposal(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_restrict_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the proposal
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_restrict_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, role(b"LockCommand", b""), scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    upgrade_policies::new_upgrade(&mut proposal, @0x1, b"", DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the proposal
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        wrong_version(), 
        DummyProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}