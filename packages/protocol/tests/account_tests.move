#[test_only]
module account_protocol::account_tests;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String,
};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock,
};
use account_protocol::{
    account::{Self, Account},
    auth,
    version,
    deps,
    issuer,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;

// === Structs ===

public struct DummyIntent() has drop;
public struct WrongWitness() has drop;

public struct Key has copy, drop, store {}
public struct Struct has store {
    inner: bool
}
public struct Object has key, store {
    id: UID,
}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<bool, bool>) {
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
    extensions.add(&cap, b"AccountConfig".to_string(), @0x1, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0x2, 1);
    // Account generic types are dummy types (bool, bool)
    let account = account::new(&extensions, true, scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<bool, bool>) {
    destroy(extensions);
    destroy(account);
    ts::end(scenario);
}

fun full_role(): String {
    let mut full_role = @account_protocol.to_string();
    full_role.append_utf8(b"::account_tests::DummyIntent::Degen");
    full_role
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
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
    assert!(account.deps().contains_name(b"AccountConfig".to_string()));
    assert!(account.deps().contains_name(b"AccountActions".to_string()));
    assert!(account.intents().length() == 0);
    assert!(account.config() == true);

    end(scenario, extensions, account);
}

#[test]
fun test_intent_execute_flow() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let mut intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );
    intent.add_action(Struct { inner: true }, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, outcome) = account.execute_intent(
        b"one".to_string(), 
        &clock, 
        version::current(), 
    );
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

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    scenario.next_tx(ALICE);
    let (executable, outcome) = account.execute_intent(
        b"one".to_string(), 
        &clock, 
        version::current(), 
    );

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

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
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
fun test_lock_object() {
    let (mut scenario, extensions, mut account) = start();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );

    account.lock_object(&intent, @0x1D.to_id(), version::current(), DummyIntent());
    assert!(account.intents().locked().contains(&@0x1D.to_id()));

    account.add_intent(intent, version::current(), DummyIntent());
    let expired = account.delete_expired_intent(b"one".to_string(), &clock);
    let action = Struct { inner: true };
    account.unlock_object(&expired, &action, @0x1D.to_id(), version::current(), DummyIntent());
    assert!(!account.intents().locked().contains(&@0x1D.to_id()));

    destroy(action);
    destroy(expired);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_managed_structs() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_struct(Key {}, Struct { inner: true }, version::current());
    account.has_managed_struct(Key {});
    let `struct`: &Struct = account.borrow_managed_struct(Key {}, version::current());
    assert!(`struct`.inner == true);
    let `struct`: &mut Struct = account.borrow_managed_struct_mut(Key {}, version::current());
    assert!(`struct`.inner == true);
    let Struct { .. } = account.remove_managed_struct(Key {}, version::current());

    end(scenario, extensions, account);
}

#[test]
fun test_managed_objects() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_object(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    account.has_managed_object(Key {});
    let _object: &Object = account.borrow_managed_object(Key {}, version::current());
    let _object: &mut Object = account.borrow_managed_object_mut(Key {}, version::current());
    let Object { id } = account.remove_managed_object(Key {}, version::current());
    id.delete();

    end(scenario, extensions, account);
}

#[test]
fun test_receive_object() {
    let (mut scenario, extensions, mut account) = start();

    account.keep(Object { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let id = object::id(&account);
    let Object { id } = account.receive(ts::most_recent_receiving_ticket<Object>(&id), version::current());
    id.delete();

    end(scenario, extensions, account);
}

#[test]
fun test_account_getters_mut() {
    let (mut scenario, extensions, mut account) = start();

    assert!(account.metadata_mut(version::current()).size() == 0);
    assert!(account.deps_mut(version::current()).contains_name(b"AccountProtocol".to_string()));
    assert!(account.deps_mut(version::current()).contains_name(b"AccountConfig".to_string()));
    assert!(account.deps_mut(version::current()).contains_name(b"AccountActions".to_string()));
    assert!(account.intents_mut(version::current()).length() == 0);
    assert!(account.config_mut(version::current()) == true);
    // intent
    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(),
        b"Degen".to_string(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    assert!(account.intents_mut(version::current()).length() == 1);
    assert!(account.intents_mut(version::current()).get_mut(b"one".to_string()).actions().length() == 0);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongAccount)]
fun test_error_cannot_create_intent_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, @0xFA15E, full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );

    destroy(intent);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_create_intent_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        wrong_version(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );

    destroy(intent);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_intent_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );
    account.add_intent(intent, wrong_version(), DummyIntent());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_add_intent_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), issuer::wrong_witness());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_execute_intent_from_not_core_dep() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(
        auth, 
        b"one".to_string(), 
        b"description".to_string(), 
        vector[0],
        1, 
        true, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, wrong_version());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ECantBeExecutedYet)]
fun test_error_cannot_execute_intent_before_execution_time() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(auth, b"one".to_string(), b"".to_string(), vector[1], 1, true, version::current(), DummyIntent(), b"".to_string(), scenario.ctx());
    account.add_intent(intent, version::current(), DummyIntent());
    let (executable, outcome) = account.execute_intent(b"one".to_string(), &clock, version::current());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::ECantBeRemovedYet)]
fun test_error_cannot_destroy_intent_without_executing_the_action() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(auth, b"one".to_string(), b"".to_string(), vector[1], 1, true, version::current(), DummyIntent(), b"".to_string(), scenario.ctx());
    account.add_intent(intent, version::current(), DummyIntent());
    let expired = account.destroy_empty_intent(b"one".to_string());

    destroy(expired);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = account::EHasntExpired)]
fun test_error_cant_delete_intent_not_expired() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, account.addr(), full_role(), version::current());
    let intent = account.create_intent(auth, b"one".to_string(), b"".to_string(), vector[1], 1, true, version::current(), DummyIntent(), b"".to_string(), scenario.ctx());
    account.add_intent(intent, version::current(), DummyIntent());
    let expired = account.delete_expired_intent(b"one".to_string(), &clock);

    destroy(expired);
    destroy(clock);
    end(scenario, extensions, account);
}


#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_struct(Key {}, Struct { inner: true }, wrong_version());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_struct(Key {}, Struct { inner: true }, version::current());
    let asset: &Struct = account.borrow_managed_struct(Key {}, wrong_version());
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_struct(Key {}, Struct { inner: true }, version::current());
    let asset: &mut Struct = account.borrow_managed_struct_mut(Key {}, wrong_version());
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_struct(Key {}, Struct { inner: true }, version::current());
    let Struct { .. } = account.remove_managed_struct(Key {}, wrong_version());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_object(Key {}, Object { id: object::new(scenario.ctx()) }, wrong_version());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_object(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let asset: &Object = account.borrow_managed_object(Key {}, wrong_version());
    assert!(asset.id.to_inner() == object::id(&account));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_object(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let asset: &mut Object = account.borrow_managed_object_mut(Key {}, wrong_version());
    assert!(asset.id.to_inner() == object::id(&account));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_object_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    account.add_managed_object(Key {}, Object { id: object::new(scenario.ctx()) }, version::current());
    let Object { id } = account.remove_managed_object(Key {}, wrong_version());
    id.delete();

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_receive_object_from_not_core_dep() {
    let (mut scenario, extensions, mut account) = start();

    account.keep(Object { id: object::new(scenario.ctx()) });
    scenario.next_tx(OWNER);
    let id = object::id(&account);
    let Object { id } = account.receive(ts::most_recent_receiving_ticket<Object>(&id), wrong_version());
    id.delete();

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_metadata_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.metadata_mut(wrong_version()).get(b"name".to_string()) == b"Main".to_string());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_deps_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.deps_mut(wrong_version()).contains_name(b"AccountProtocol".to_string()));
    assert!(account.deps_mut(wrong_version()).contains_name(b"AccountConfig".to_string()));
    assert!(account.deps_mut(wrong_version()).contains_name(b"AccountActions".to_string()));

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_intents_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.intents_mut(wrong_version()).length() == 0);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_config_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.config_mut(wrong_version()) == true);

    end(scenario, extensions, account);
}
