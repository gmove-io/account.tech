#[test_only]
module account_actions::kiosk_tests;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String,
};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    kiosk::{Self, Kiosk, KioskOwnerCap},
    package,
    clock::{Self, Clock},
    transfer_policy::{Self, TransferPolicy},
    coin::{Self, Coin},
    sui::SUI,
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    intents::Intent,
    issuer,
    deps,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    kiosk as acc_kiosk,
    kiosk_intents as acc_kiosk_intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;
// === Structs ===

public struct KIOSK_TESTS has drop {}

public struct Nft has key, store {
    id: UID
}

public struct DummyIntent() has copy, drop;

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock, TransferPolicy<Nft>) {
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
    let account = multisig::new_account(&extensions, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // instantiate TransferPolicy 
    let publisher = package::test_claim(KIOSK_TESTS {}, scenario.ctx());
    let (mut policy, policy_cap) = transfer_policy::new<Nft>(&publisher, scenario.ctx());
    royalty_rule::add(&mut policy, &policy_cap, 100, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);
    // create world
    destroy(cap);
    destroy(policy_cap);
    destroy(publisher);
    (scenario, extensions, account, clock, policy)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock, policy: TransferPolicy<Nft>) {
    destroy(extensions);
    destroy(account);
    destroy(policy);
    destroy(clock);
    ts::end(scenario);
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun role(name: vector<u8>): String {
    let mut full_role = @account_actions.to_string();
    full_role.append_utf8(b"::kiosk");
    if (!name.is_empty()) {
        full_role.append_utf8(b"::");
        full_role.append_utf8(name);
    };
    full_role
}

fun init_caller_kiosk_with_nfts(policy: &TransferPolicy<Nft>, amount: u64, scenario: &mut Scenario): (Kiosk, KioskOwnerCap, vector<ID>) {
    let (mut kiosk, kiosk_cap) = kiosk::new(scenario.ctx());
    let mut ids = vector[];

    amount.do!(|_| {
        let nft = Nft { id: object::new(scenario.ctx()) };
        ids.push_back(object::id(&nft));
        kiosk.lock(&kiosk_cap, policy, nft);
    });

    (kiosk, kiosk_cap, ids)
}

fun init_account_kiosk_with_nfts(extensions: &Extensions, account: &mut Account<Multisig, Approvals>, policy: &mut TransferPolicy<Nft>, amount: u64, scenario: &mut Scenario): (Kiosk, vector<ID>) {
    let auth = multisig::authenticate(extensions, account, scenario.ctx());
    acc_kiosk::open(auth, account, b"Degen".to_string(), scenario.ctx());
    scenario.next_tx(OWNER);
    let mut acc_kiosk = scenario.take_shared<Kiosk>();
    
    let (mut kiosk, kiosk_cap, ids) = init_caller_kiosk_with_nfts(policy, amount, scenario);
    let mut nft_ids = ids;

    amount.do!(|_| {
        let auth = multisig::authenticate(extensions, account, scenario.ctx());
        let request = acc_kiosk::place(
            auth, 
            account, 
            &mut acc_kiosk, 
            &mut kiosk,
            &kiosk_cap, 
            policy,
            b"Degen".to_string(),
            nft_ids.pop_back(),
            scenario.ctx()
        );
        policy.confirm_request(request);
    });

    destroy(kiosk);
    destroy(kiosk_cap);
    (acc_kiosk, ids)
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Intent<Approvals> {
    let auth = multisig::authenticate(extensions, account, scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    account.create_intent(
        auth, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        outcome, 
        version::current(), 
        DummyIntent(), 
        b"Degen".to_string(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_open_kiosk() {
    let (mut scenario, extensions, mut account, clock, policy) = start();

    assert!(!acc_kiosk::has_lock(&account, b"Degen".to_string()));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(acc_kiosk::has_lock(&account, b"Degen".to_string()));

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();
    assert!(kiosk.owner() == account.addr());

    destroy(kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_place_into_kiosk() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 0, &mut scenario);
    let (mut caller_kiosk, caller_cap, mut ids) = init_caller_kiosk_with_nfts(&policy, 1, &mut scenario);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let request = acc_kiosk::place(
        auth, 
        &mut account, 
        &mut acc_kiosk, 
        &mut caller_kiosk,
        &caller_cap, 
        &mut policy,
        b"Degen".to_string(),
        ids.pop_back(),
        scenario.ctx()
    );
    policy.confirm_request(request);

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_place_into_kiosk_without_rules() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 0, &mut scenario);
    let (mut caller_kiosk, caller_cap, mut ids) = init_caller_kiosk_with_nfts(&policy, 1, &mut scenario);
    
    let publisher = package::test_claim(KIOSK_TESTS {}, scenario.ctx());
    let (mut empty_policy, policy_cap) = transfer_policy::new<Nft>(&publisher, scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let request = acc_kiosk::place(
        auth, 
        &mut account, 
        &mut acc_kiosk, 
        &mut caller_kiosk,
        &caller_cap, 
        &mut empty_policy,
        b"Degen".to_string(),
        ids.pop_back(),
        scenario.ctx()
    );
    empty_policy.confirm_request(request);

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    destroy(empty_policy);
    destroy(policy_cap);
    destroy(publisher);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_delist_nfts() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 2, &mut scenario);

    // list nfts
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    acc_kiosk_intents::request_list(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"Degen".to_string(),
        ids,
        vector[1, 2],
        scenario.ctx()
    );
    multisig::approve_intent(&mut account, b"dummy".to_string(), scenario.ctx());

    let mut executable = multisig::execute_intent(&mut account, b"dummy".to_string(), &clock);
    acc_kiosk_intents::execute_list<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::complete_list(executable, &account);

    // delist nfts
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::delist<Multisig, Approvals, Nft>(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), ids.pop_back());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::delist<Multisig, Approvals, Nft>(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), ids.pop_back());

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_withdraw_profits() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 2, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    
    // list nfts
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    acc_kiosk_intents::request_list(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"Degen".to_string(),
        ids,
        vector[100, 200],
        scenario.ctx()
    );
    multisig::approve_intent(&mut account, b"dummy".to_string(), scenario.ctx());

    let mut executable = multisig::execute_intent(&mut account, b"dummy".to_string(), &clock);
    acc_kiosk_intents::execute_list<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::complete_list(executable, &account);

    // purchase nfts
    let (nft1, mut request1) = acc_kiosk.purchase<Nft>(ids.pop_back(), coin::mint_for_testing<SUI>(200, scenario.ctx()));
    caller_kiosk.lock(&caller_cap, &policy, nft1);
    kiosk_lock_rule::prove(&mut request1, &caller_kiosk);
    royalty_rule::pay(&mut policy, &mut request1, coin::mint_for_testing<SUI>(2, scenario.ctx()));
    policy.confirm_request(request1);

    let (nft2, mut request2) = acc_kiosk.purchase<Nft>(ids.pop_back(), coin::mint_for_testing<SUI>(100, scenario.ctx()));
    caller_kiosk.lock(&caller_cap, &policy, nft2);
    kiosk_lock_rule::prove(&mut request2, &caller_kiosk);
    royalty_rule::pay(&mut policy, &mut request2, coin::mint_for_testing<SUI>(1, scenario.ctx()));
    policy.confirm_request(request2);

    // withdraw profits
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::withdraw_profits(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let coin = scenario.take_from_address<Coin<SUI>>(account.addr());
    assert!(coin.value() == 300);

    destroy(coin);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_close_kiosk() {
    let (mut scenario, extensions, mut account, clock, policy) = start();

    assert!(!acc_kiosk::has_lock(&account, b"Degen".to_string()));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(acc_kiosk::has_lock(&account, b"Degen".to_string()));

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();
    assert!(kiosk.owner() == account.addr());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::close(auth, &mut account, b"Degen".to_string(), kiosk, scenario.ctx());

    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_take_flow() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let request = acc_kiosk::do_take<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );
    policy.confirm_request(request);
    account.confirm_execution(executable, version::current(), DummyIntent());

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_list_flow() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_list(&mut intent, ids.pop_back(), 100, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    acc_kiosk::do_list<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_take_expired() {
    let (mut scenario, extensions, mut account, mut clock, mut policy) = start();
    clock.increment_for_testing(1);
    let (acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent(key, &clock);
    acc_kiosk::delete_take(&mut expired);
    expired.destroy_empty();

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_list_expired() {
    let (mut scenario, extensions, mut account, mut clock, mut policy) = start();
    clock.increment_for_testing(1);
    let (acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_list(&mut intent, ids.pop_back(), 100, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    acc_kiosk::delete_list(&mut expired);
    expired.destroy_empty();

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk::EAlreadyExists)]
fun test_error_open_kiosk_already_exists() {
    let (mut scenario, extensions, mut account, clock, policy) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk::ENoLock)]
fun test_error_place_into_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 0, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 1, &mut scenario);
    
    account.config_mut(version::current()).member_mut(OWNER).add_role_to_member(role(b"NotDegen"));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let request = acc_kiosk::place(
        auth, 
        &mut account, 
        &mut acc_kiosk, 
        &mut caller_kiosk,
        &caller_cap, 
        &mut policy,
        b"NotDegen".to_string(),
        @0x0.to_id(),
        scenario.ctx()
    );

    destroy(request);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk::ENoLock)]
fun test_error_delist_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    
    account.config_mut(version::current()).member_mut(OWNER).add_role_to_member(role(b"NotDegen"));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::delist<Multisig, Approvals, Nft>(auth, &mut account, &mut acc_kiosk, b"NotDegen".to_string(), @0x0.to_id());
    
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

// no need for role to do this action
#[test, expected_failure(abort_code = acc_kiosk::ENoLock)]
fun test_error_withdraw_profits_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 0, &mut scenario);
    
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::withdraw_profits(auth, &mut account, &mut acc_kiosk, b"NotDegen".to_string(), scenario.ctx());

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

// no need for role to do this action
#[test, expected_failure(abort_code = acc_kiosk::ENoLock)]
fun test_error_close_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (acc_kiosk, _) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    acc_kiosk::close(auth, &mut account, b"NotDegen".to_string(), acc_kiosk, scenario.ctx());

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk::EWrongReceiver)]
fun test_error_do_take_wrong_receiver() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), ALICE, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let request = acc_kiosk::do_take<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );

    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_take_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    let request = acc_kiosk::do_take<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );

    destroy(account2);
    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_take_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let request = acc_kiosk::do_take<Multisig, Approvals, Nft, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        issuer::wrong_witness(),
        scenario.ctx()
    );

    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_take_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let request = acc_kiosk::do_take<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        wrong_version(),
        DummyIntent(),
        scenario.ctx()
    );

    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_list_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    acc_kiosk::do_list<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_list_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    acc_kiosk::do_list<Multisig, Approvals, Nft, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        issuer::wrong_witness(),
    );

    destroy(executable);
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_list_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&extensions, &mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    acc_kiosk::new_take(&mut intent, ids.pop_back(), OWNER, DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    acc_kiosk::do_list<Multisig, Approvals, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        wrong_version(),
        DummyIntent(),
    );

    destroy(executable);
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}