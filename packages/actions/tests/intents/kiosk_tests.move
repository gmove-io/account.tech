#[test_only]
module account_actions::kiosk_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    kiosk::{Self, Kiosk, KioskOwnerCap},
    package,
    clock::{Self, Clock},
    transfer_policy::{Self, TransferPolicy},
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::account::Account;
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    kiosk as acc_kiosk,
    kiosk_intents as acc_kiosk_intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct KIOSK_TESTS has drop {}

public struct Nft has key, store {
    id: UID
}

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

    let mut account = multisig::new_account(&extensions, scenario.ctx());
    account.deps_mut_for_testing().add(&extensions, b"AccountActions".to_string(), @account_actions, 1);
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

fun init_account_kiosk_with_nfts(account: &mut Account<Multisig, Approvals>, policy: &mut TransferPolicy<Nft>, amount: u64, scenario: &mut Scenario): (Kiosk, vector<ID>) {
    let auth = multisig::authenticate(account, scenario.ctx());
    acc_kiosk::open(auth, account, b"Degen".to_string(), scenario.ctx());
    scenario.next_tx(OWNER);
    let mut acc_kiosk = scenario.take_shared<Kiosk>();
    
    let (mut kiosk, kiosk_cap, ids) = init_caller_kiosk_with_nfts(policy, amount, scenario);
    let mut nft_ids = ids;

    amount.do!(|_| {
        let auth = multisig::authenticate(account, scenario.ctx());
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

// === Tests ===

#[test]
fun test_request_execute_take() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    acc_kiosk_intents::request_take_nfts(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"Degen".to_string(),
        ids,
        OWNER,
        scenario.ctx()
    );
    multisig::approve_intent(&mut account, b"dummy".to_string(), scenario.ctx());

    let mut executable = multisig::execute_intent(&mut account, b"dummy".to_string(), &clock);
    let request = acc_kiosk_intents::execute_take_nfts<Multisig, Approvals, Nft>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        scenario.ctx()
    );
    policy.confirm_request(request);
    let request = acc_kiosk_intents::execute_take_nfts<Multisig, Approvals, Nft>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        scenario.ctx()
    );
    policy.confirm_request(request);
    acc_kiosk_intents::complete_take_nfts(executable, &account);

    let mut expired = account.destroy_empty_intent(b"dummy".to_string());
    acc_kiosk::delete_take(&mut expired);
    acc_kiosk::delete_take(&mut expired);
    expired.destroy_empty();

    assert!(caller_kiosk.has_item(ids.pop_back()));
    assert!(caller_kiosk.has_item(ids.pop_back()));

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_request_execute_list() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);
    
    // list nfts
    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    acc_kiosk_intents::request_list_nfts(
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
    acc_kiosk_intents::execute_list_nfts<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list_nfts<Multisig, Approvals, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::complete_list_nfts(executable, &account);

    let mut expired = account.destroy_empty_intent(b"dummy".to_string());
    acc_kiosk::delete_list(&mut expired);
    acc_kiosk::delete_list(&mut expired);
    expired.destroy_empty();

    assert!(acc_kiosk.is_listed(ids.pop_back()));
    assert!(acc_kiosk.is_listed(ids.pop_back()));

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENoLock)]
fun test_error_request_take_from_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, policy) = start();
    
    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    acc_kiosk_intents::request_take_nfts(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"NotDegen".to_string(),
        vector[@0x0.to_id()],
        OWNER,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENoLock)]
fun test_error_request_list_from_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, policy) = start();
    
    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    acc_kiosk_intents::request_list_nfts(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"NotDegen".to_string(),
        vector[@0x0.to_id()],
        vector[100],
        scenario.ctx()
    ); 

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENftsPricesNotSameLength)]
fun test_error_request_list_nfts_prices_not_same_length() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (acc_kiosk, _) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);

    let auth = multisig::authenticate(&account, scenario.ctx());
    let outcome = multisig::empty_outcome();
    acc_kiosk_intents::request_list_nfts(
        auth, 
        outcome,
        &mut account, 
        b"dummy".to_string(),
        b"".to_string(),
        0,
        1,
        b"Degen".to_string(),
        vector[@0x0.to_id()],
        vector[100, 200],
        scenario.ctx()
    );

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}
