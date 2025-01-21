#[test_only]
module account_actions::upgrade_policies_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    intents::Intent,
    issuer,
    deps,
    version_witness,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    upgrade_policies,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

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

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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
        b"Degen".to_string(), 
        outcome, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    assert!(upgrade_policies::has_cap(&account, b"Degen".to_string()));
    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.package() == @0x1.to_id());

    let time_delay = upgrade_policies::get_time_delay(&account, b"Degen".to_string());
    assert!(time_delay == 1000);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_flow() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    clock.increment_for_testing(1000);

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_additive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 128, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 128);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_deps_only() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 192, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let cap = upgrade_policies::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 192);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_immutable() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 255, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    assert!(!upgrade_policies::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    upgrade_policies::delete_upgrade(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 128, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    upgrade_policies::delete_restrict(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::ELockAlreadyExists)]
fun test_error_lock_name_already_exists() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let upgrade_cap1 = package::test_publish(@0x1.to_id(), scenario.ctx());

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap1, b"Degen".to_string(), 1000);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::EPolicyShouldRestrict)]
fun test_error_new_restrict_not_restrictive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 0, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = upgrade_policies::EInvalidPolicy)]
fun test_error_new_restrict_invalid_policy() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_restrict(&mut intent, &account, 0, 1, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_confirm_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);
    let auth = multisig::authenticate(&account2, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account2, package::test_publish(@0x1.to_id(), scenario.ctx()), b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account2, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_confirm_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_confirm_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    let ticket = upgrade_policies::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_restrict_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    account2.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_restrict_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_restrict_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    upgrade_policies::new_upgrade(&mut intent, &account, b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    upgrade_policies::do_restrict(
        &mut executable, 
        &mut account, 
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}