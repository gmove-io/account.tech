#[test_only]
module account_actions::transfer_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin,
    sui::SUI,
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
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct Obj has key, store {
    id: UID
}

public struct DummyProposal() has copy, drop;
public struct WrongProposal() has copy, drop;

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
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);
    // Account generic types are dummy types (bool, bool)
    let account = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
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

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun create_dummy_proposal(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Proposal<Approvals> {
    let auth = multisig::authenticate(extensions, account, b"".to_string(), scenario.ctx());
    let outcome = multisig::new_outcome(account, scenario.ctx());
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
fun test_transfer_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let obj = Obj { id: object::new(scenario.ctx()) };

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    acc_transfer::new_transfer(&mut proposal, OWNER, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        obj,
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    scenario.next_tx(OWNER);
    assert!(scenario.has_most_recent_for_sender<Obj>());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_transfer_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    acc_transfer::new_transfer(&mut proposal, OWNER, DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to disable from the account that didn't approve the proposal
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        DummyProposal(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_transfer_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    acc_transfer::new_transfer(&mut proposal, OWNER, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong witness that didn't approve the proposal
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        WrongProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_transfer_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    acc_transfer::new_transfer(&mut proposal, OWNER, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong version TypeName that didn't approve the proposal
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        wrong_version(), 
        DummyProposal(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}