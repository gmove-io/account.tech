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

// === Structs ===

public struct DummyProposal() has drop;
public struct WrongWitness() has drop;

public struct Key has copy, drop, store {}
public struct Value has store {
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
    let account = account::new(&extensions, b"Main".to_string(), true, scenario.ctx());
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
    full_role.append_utf8(b"::account_tests::DummyProposal::Degen");
    full_role
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

// === Tests ===

#[test]
fun test_create_and_share_account() {
    let (scenario, extensions, account) = start();

    account.share();

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
    let (mut scenario, extensions, mut account) = start();

    assert!(account.addr() == object::id(&account).to_address());
    assert!(account.metadata().get(b"name".to_string()) == b"Main".to_string());
    assert!(account.deps().contains_name(b"AccountProtocol".to_string()));
    assert!(account.deps().contains_name(b"AccountConfig".to_string()));
    assert!(account.deps().contains_name(b"AccountActions".to_string()));
    assert!(account.proposals().length() == 0);
    // proposal
    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    assert!(account.proposals().length() == 1);
    assert!(account.proposal(b"one".to_string()).execution_time() == 0);
    assert!(account.proposal(b"one".to_string()).outcome() == true);

    end(scenario, extensions, account);
}

#[test]
fun test_proposal_execute_flow() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    let (executable, outcome) = account.execute_proposal(
        b"one".to_string(), 
        &clock, 
        version::current(), 
        scenario.ctx()
    );

    destroy(outcome);
    destroy(executable);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_proposal_delete_flow() {
    let (mut scenario, extensions, mut account) = start();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    let expired = account.delete_proposal(
        b"one".to_string(), 
        version::current(), 
        &clock, 
    );

    destroy(expired);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test]
fun test_managed_assets() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Value { inner: true }, version::current());
    account.has_managed_asset(Key {});
    let asset: &Value = account.borrow_managed_asset(Key {}, version::current());
    assert!(asset.inner == true);
    let asset: &mut Value = account.borrow_managed_asset_mut(Key {}, version::current());
    assert!(asset.inner == true);
    let Value { .. } = account.remove_managed_asset(Key {}, version::current());

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

    assert!(account.metadata_mut(version::current()).get(b"name".to_string()) == b"Main".to_string());
    assert!(account.deps_mut(version::current()).contains_name(b"AccountProtocol".to_string()));
    assert!(account.deps_mut(version::current()).contains_name(b"AccountConfig".to_string()));
    assert!(account.deps_mut(version::current()).contains_name(b"AccountActions".to_string()));
    assert!(account.proposals_mut(version::current()).length() == 0);
    assert!(account.config_mut(version::current()) == true);
    // proposal
    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    assert!(account.proposals_mut(version::current()).length() == 1);
    assert!(account.proposal_mut(0, version::current()).actions_length() == 0);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = auth::EWrongAccount)]
fun test_error_cannot_create_proposal_with_wrong_account() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, full_role(), @0xFA15E, version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );

    destroy(proposal);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_create_proposal_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        wrong_version(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );

    destroy(proposal);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_proposal_from_not_dependent_package() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, wrong_version(), DummyProposal());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_cannot_add_proposal_with_wrong_witness() {
    let (mut scenario, extensions, mut account) = start();

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), WrongWitness());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_execute_proposal_from_not_core_dep() {
    let (mut scenario, extensions, mut account) = start();
    let clock = clock::create_for_testing(scenario.ctx());

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    let (executable, outcome) = account.execute_proposal(b"one".to_string(), &clock, wrong_version(), scenario.ctx());

    destroy(executable);
    destroy(outcome);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_delete_proposal_from_not_core_dep() {
    let (mut scenario, extensions, mut account) = start();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(1);

    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    let expired = account.delete_proposal(b"one".to_string(), wrong_version(), &clock);

    destroy(expired);
    destroy(clock);
    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_add_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Value { inner: true }, wrong_version());

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Value { inner: true }, version::current());
    let asset: &Value = account.borrow_managed_asset(Key {}, wrong_version());
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_borrow_mut_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Value { inner: true }, version::current());
    let asset: &mut Value = account.borrow_managed_asset_mut(Key {}, wrong_version());
    assert!(asset.inner == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_cannot_remove_managed_asset_from_not_dependent_package() {
    let (scenario, extensions, mut account) = start();

    account.add_managed_asset(Key {}, Value { inner: true }, version::current());
    let Value { .. } = account.remove_managed_asset(Key {}, wrong_version());

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
fun test_error_cannot_access_proposals_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.proposals_mut(wrong_version()).length() == 0);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_config_mut_from_not_core_dep() {
    let (scenario, extensions, mut account) = start();

    assert!(account.config_mut(wrong_version()) == true);

    end(scenario, extensions, account);
}

#[test, expected_failure(abort_code = deps::EDepNotFound)]
fun test_error_cannot_access_proposal_mut_from_not_core_dep() {
    let (mut scenario, extensions, mut account) = start();

    assert!(account.proposals_mut(version::current()).length() == 0);
    // proposal
    let auth = auth::new(&extensions, full_role(), account.addr(), version::current());
    let proposal = account.create_proposal(
        auth, 
        true, 
        version::current(), 
        DummyProposal(), 
        b"Degen".to_string(), 
        b"one".to_string(), 
        b"description".to_string(), 
        0,
        1, 
        scenario.ctx()
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    assert!(account.proposal_mut(0, wrong_version()).actions_length() == 0);

    end(scenario, extensions, account);
}
