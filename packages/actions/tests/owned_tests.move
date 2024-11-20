#[test_only]
module account_actions::owned_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
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
    owned,
    vesting::Stream,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

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

fun send_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
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
fun test_propose_execute_transfer() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id1 = send_coin(account.addr(), 1, &mut scenario);
    let id2 = send_coin(account.addr(), 2, &mut scenario);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    owned::propose_transfer(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        vector[id1, id2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // loop over execute_transfer to execute each action
    owned::execute_transfer<Multisig, Approvals, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id1));
    owned::execute_transfer<Multisig, Approvals, Coin<SUI>>(&mut executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id2));
    owned::complete_transfer(executable);

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<SUI>>(@0x2);
    assert!(coin2.value() == 2);

    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_propose_execute_vesting() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    owned::propose_vesting(
        auth, 
        &mut account, 
        outcome, 
        key, 
        b"".to_string(), 
        0, 
        1,
        id, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let executable = multisig::execute_proposal(&mut account, key, &clock);
    owned::execute_vesting<Multisig, Approvals, SUI>(executable, &mut account, ts::receiving_ticket_by_id<Coin<SUI>>(id), scenario.ctx());

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Stream<SUI>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    owned::new_withdraw(&mut proposal, id, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        DummyProposal(),
    );
    executable.destroy(version::current(), DummyProposal());

    assert!(coin.value() == 5);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_withdraw_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    owned::new_withdraw(&mut proposal, id, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    let mut expired = account.delete_proposal(key, version::current(), &clock);
    owned::delete_withdraw_action(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = owned::EObjectsRecipientsNotSameLength)]
fun test_error_propose_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    owned::propose_transfer(
        auth, 
        &mut account, 
        outcome, 
        b"dummy".to_string(), 
        b"".to_string(), 
        0, 
        1, 
        vector[@0x1D.to_id()],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_withdraw_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    owned::new_withdraw(&mut proposal, id, DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to disable from the account that didn't approve the proposal
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        DummyProposal(),
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_withdraw_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    owned::new_withdraw(&mut proposal, id, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong witness that didn't approve the proposal
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        version::current(), 
        WrongProposal(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_withdraw_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let id = send_coin(account.addr(), 5, &mut scenario);

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    owned::new_withdraw(&mut proposal, id, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong version TypeName that didn't approve the proposal
    let coin: Coin<SUI> = owned::do_withdraw(
        &mut executable, 
        &mut account, 
        ts::receiving_ticket_by_id<Coin<SUI>>(id),
        wrong_version(), 
        DummyProposal(),
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}