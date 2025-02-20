#[test_only]
module account_actions::transfer_tests;

// === Imports ===

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
    intents::Intent,
    issuer,
    version_witness,
    deps,
};
use account_multisig::multisig::{Self, Multisig, Approvals};
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

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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
    extensions.add(&cap, b"AccountMultisig".to_string(), @account_multisig, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
): Intent<Approvals> {
    let outcome = multisig::empty_outcome();
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        b"".to_string(), 
        outcome, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_transfer_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let obj = Obj { id: object::new(scenario.ctx()) };

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    acc_transfer::new_transfer(&mut intent, &account, OWNER, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        obj,
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    scenario.next_tx(OWNER);
    assert!(scenario.has_most_recent_for_sender<Obj>());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_transfer_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    acc_transfer::new_transfer(&mut intent, &account2, OWNER, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to disable from the account that didn't approve the intent
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_transfer_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    acc_transfer::new_transfer(&mut intent, &account, OWNER, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to disable with the wrong witness that didn't approve the intent
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_transfer_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    acc_transfer::new_transfer(&mut intent, &account, OWNER, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to disable with the wrong version TypeName that didn't approve the intent
    acc_transfer::do_transfer(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}