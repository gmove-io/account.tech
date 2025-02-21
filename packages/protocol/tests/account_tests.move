#[test_only]
module account_protocol::account_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock,
};
use account_protocol::{
    account::{Self, Account},
    version,
    version_witness,
    deps,
    issuer,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct Witness() has drop;
public struct DummyIntent() has copy, drop;
public struct WrongWitness() has drop;

public struct Key has copy, drop, store {}
public struct Struct has store {
    inner: bool
}
public struct Object has key, store {
    id: UID,
}

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    account::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountMultisig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);

    let account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config, Outcome>) {
    destroy(extensions);
    destroy(account);
    ts::end(scenario);
}

// === Tests ===

#[test]
fun test_create_and_share_account() {
    let (scenario, extensions, account) = start();

    transfer::public_share_object(account);

    destroy(extensions);
    scenario.end();
}

#[test]
fun test_keep_object() {
    let (mut scenario, extensions, account) = start();

    account.keep(Object { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let Object { id } = scenario.take_from_address<Object>(account.addr());
    id.delete();

    end(scenario, extensions, account);
}

#[test]
fun test_account_getters() {
    let (scenario, extensions, account) = start();

    assert!(account.addr() == object::id(&account).to_address());
    assert!(account.metadata().size() == 0);
    assert!(account.deps().contains_name(b"AccountProtocol".to_string()));
    assert!(account.intents().length() == 0);
    assert!(account.config() == Config {});

    end(scenario, extensions, account);
}

#[test]
fun test_intent_create_execute_flow() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(),
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, Struct { inner: true }, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &Struct = account.process_action(&mut executable, version::current(), DummyIntent());
    assert!(account.intents().get(b"one".to_string()).execution_times().length() == 0);
    account.confirm_execution(executable, version::current(), DummyIntent());
    assert!(account.intents().length() == 1);
    let expired = account.destroy_empty_intent(b"one".to_string());
    assert!(account.intents().length() == 0);

    destroy(expired);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_anyone_can_execute_intent() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    scenario.next_tx(ALICE);
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    
    destroy(outcome);
    destroy(executable);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_intent_delete_flow() {
    let (mut scenario, extensions, mut account) = start();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    assert!(account.intents().length() == 1);
    let expired = account.delete_expired_intent(b"one".to_string(), &clock);
    assert!(account.intents().length() == 0);
    expired.destroy_empty();
    
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_managed_structs() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_data(Key {}, Struct { inner: true }, version::current());
    account.has_managed_data(Key {});
    let `struct`: &Struct = account.borrow_managed_data(Key {}, version::current());
    assert!(`struct`.inner == true);
    let `struct`: &mut Struct = account.borrow_managed_data_mut(Key {}, version::current());
    assert!(`struct`.inner == true);
    let Struct { .. } = account.remove_managed_data(Key {}, version::current());

    end(scenario, extensions, account);
}

#[test]
fun test_managed_objects() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    account.has_managed_asset(Key {});
    let _object: &Object = account.borrow_managed_asset(Key {}, version::current());
    let _object: &mut Object = account.borrow_managed_asset_mut(Key {}, version::current());
    let Object { id } = account.remove_managed_asset(Key {}, version::current());
    id.delete();

    end(scenario, extensions, account);
}

#[test]
fun test_receive_object() {
    let (mut scenario, extensions, mut account) = start();

    account.keep(Object { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let id = object::id(&account);
    let Object { id } = account.receive(ts::most_recent_receiving_ticket<Object>(&id));
    id.delete();

    end(scenario, extensions, account);
}

#[test]
fun test_lock_object() {
    let (scenario, extensions, mut account) = start();

    assert!(!account.intents().locked().contains(&@0x1D.to_id()));
    account.lock_object(@0x1D.to_id());
    assert!(account.intents().locked().contains(&@0x1D.to_id()));
    account.unlock_object(@0x1D.to_id());
    assert!(!account.intents().locked().contains(&@0x1D.to_id()));

    end(scenario, extensions, account);
}

#[test]
#[allow(unused_mut_ref)]
fun test_account_getters_mut() {
    let (scenario, extensions, mut account) = start();

    assert!(account.metadata_mut(version::current()).size() == 0);
    assert!(account.deps_mut(version::current()).contains_name(b"AccountProtocol".to_string()));
    assert!(account.intents_mut(version::current(), Witness()).length() == 0);
    assert!(account.config_mut(version::current(), Witness()) == &mut Config {});

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::EWrongAccount)]
fun test_error_cannot_verify_wrong_account() {
    let (mut scenario, extensions, account) = start();
    
    let auth = account.new_auth(version::current(), Witness());
    let account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.verify(auth);

    destroy(account2);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_create_intent_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version_witness::new_for_testing(@0xDE9), 
        DummyIntent(), 
        scenario.ctx()
    );

    destroy(intent);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_action_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version_witness::new_for_testing(@0xDE9), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_cannot_add_action_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();
    let account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account2.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    destroy(account2);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_add_action_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), WrongWitness());
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_intent_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version_witness::new_for_testing(@0xDE9), DummyIntent());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_cannot_add_intent_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();
    let mut account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    destroy(account2);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_add_intent_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), WrongWitness());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_process_action_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account.process_action(&mut executable, version_witness::new_for_testing(@0xDE9), DummyIntent());

    destroy(executable);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_cannot_process_action_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());
    let mut account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let mut intent2 = account2.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account2.add_action(&mut intent2, true, version::current(), DummyIntent());
    account2.add_intent(intent2, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account2.process_action(&mut executable, version::current(), DummyIntent());

    destroy(account2);
    destroy(executable);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_process_action_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account.process_action(&mut executable, version::current(), WrongWitness());

    destroy(executable);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_confirm_execution_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account.process_action(&mut executable, version::current(), DummyIntent());
    account.confirm_execution(executable, version_witness::new_for_testing(@0xDE9), DummyIntent());

    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_cannot_confirm_execution_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());
    let account2 = account::new<Config, Outcome>(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account.process_action(&mut executable, version::current(), DummyIntent());
    account2.confirm_execution(executable, version::current(), DummyIntent());

    destroy(account2);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_confirm_execution_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, true, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    let _: &bool = account.process_action(&mut executable, version::current(), DummyIntent());
    account.confirm_execution(executable, version::current(), WrongWitness());

    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::EActionsRemaining)]
fun test_error_cannot_confirm_execution_before_all_actions_executed() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_action(&mut intent, Struct { inner: true }, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());
    account.confirm_execution(executable, version::current(), DummyIntent());

    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ECantBeRemovedYet)]
fun test_error_cannot_destroy_intent_without_executing_the_action() {
    let (mut scenario, extensions, mut account) = start();

    let intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[1], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let expired = account.destroy_empty_intent(b"one".to_string());

    destroy(expired);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::EHasntExpired)]
fun test_error_cannot_delete_intent_not_expired() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[1], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let expired = account.delete_expired_intent(b"one".to_string(), &clock);

    destroy(expired);
    destroy(clock);
    end(scenario, extensions, account);
}


#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_data(Key {}, Struct { inner: true }, version_witness::new_for_testing(@0xDE9));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_data(Key {}, Struct { inner: true }, version::current());
    let asset: &Struct = account.borrow_managed_data(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_data(Key {}, Struct { inner: true }, version::current());
    let asset: &mut Struct = account.borrow_managed_data_mut(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_data(Key {}, Struct { inner: true }, version::current());
    let Struct { .. } = account.remove_managed_data(Key {}, version_witness::new_for_testing(@0xDE9));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Object { id: object::new(scenario.ctx()) }, version_witness::new_for_testing(@0xDE9));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let asset: &Object = account.borrow_managed_asset(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.id.to_inner() == object::id(&account));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let asset: &mut Object = account.borrow_managed_asset_mut(Key {}, version_witness::new_for_testing(@0xDE9));
    assert!(asset.id.to_inner() == object::id(&account));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let Object { id } = account.remove_managed_asset(Key {}, version_witness::new_for_testing(@0xDE9));
    id.delete();

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_new_auth_not_called_from_not_dep() {
    let (scenario, extensions, account) = start();

    let auth = account.new_auth(version_witness::new_for_testing(@0xDE9), Witness());
    account.verify(auth);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ENotCalledFromConfigModule)]
fun test_error_new_auth_not_called_from_config_module() {
    let (scenario, extensions, account) = start();

    let auth = account.new_auth(version::current(), account::not_config_witness());
    account.verify(auth);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_execute_intent_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version_witness::new_for_testing(@0xDE9), Witness());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ENotCalledFromConfigModule)]
fun test_error_cannot_execute_intent_not_called_from_config_module() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[0], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current(), account::not_config_witness());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ECantBeExecutedYet)]
fun test_error_cannot_execute_intent_before_execution_time() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let intent = account.create_intent(
        b"one".to_string(), 
        b"".to_string(), 
        vector[1], 
        1, 
        b"".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current(), Witness());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}