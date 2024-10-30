#[test_only]
module account_actions::vesting_tests;

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
    vesting,
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
fun test_create_stream_claim_and_destroy() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    stream.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 1);

    clock.increment_for_testing(2);
    stream.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 2);
    
    clock.increment_for_testing(3);
    stream.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin3 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin3.value() == 3);

    stream.destroy_empty();
    cap.destroy();

    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_stream_disburse_and_cancel() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 1);

    clock.increment_for_testing(2);
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 2);
    
    clock.increment_for_testing(3);
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin3 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin3.value() == 3);

    let auth = multisig::authenticate(&extensions, &account, b"".to_string(), scenario.ctx());
    vesting::cancel_payment(auth, stream, &account, scenario.ctx());

    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_stream_disburse_after_end() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(10);
    stream.disburse(&clock, scenario.ctx());
    stream.destroy_empty();
    
    scenario.next_tx(OWNER);
    let coin = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin.value() == 6);

    destroy(cap);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_stream_disburse_same_time() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(3);
    
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 3);
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 0);

    destroy(stream);
    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_vesting_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    vesting::new_vesting(
        &mut proposal, 
        0, 
        6,
        OWNER, 
        DummyProposal(), 
    );
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    vesting::do_vesting(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        DummyProposal(),
        scenario.ctx()
    );
    executable.destroy(version::current(), DummyProposal());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_vesting_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    vesting::new_vesting(
        &mut proposal, 
        0, 
        6,
        OWNER, 
        DummyProposal(), 
    );
    account.add_proposal(proposal, version::current(), DummyProposal());
    
    let mut expired = account.delete_proposal(key, version::current(), &clock);
    vesting::delete_vesting_action(&mut expired);
    multisig::delete_expired_outcome(expired);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_stream_getters() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    assert!(stream.balance_value() == 6);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 0);
    assert!(stream.end_timestamp() == 6);
    assert!(stream.recipient() == OWNER);

    destroy(cap);
    destroy(stream);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EWrongStream)]
fun test_error_claim_wrong_stream() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap1, mut stream1) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );
    let (cap2, stream2) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    stream1.claim(&cap2, &clock, scenario.ctx());

    destroy(cap1);
    destroy(cap2);
    destroy(stream1);
    destroy(stream2);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::ETooEarly)]
fun test_error_disburse_too_early() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    stream.disburse(&clock, scenario.ctx());

    destroy(cap);
    destroy(stream);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EVestingOver)]
fun test_error_vesting_over() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(6);
    
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 6);
    stream.disburse(&clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 0);

    stream.destroy_empty();
    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EBalanceNotEmpty)]
fun test_error_destroy_non_empty_stream() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, stream) = vesting::create_stream_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    stream.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_withdraw_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let mut account2 = multisig::new_account(&extensions, b"Main".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    // proposal is submitted to other account
    let mut proposal = create_dummy_proposal(&mut scenario, &mut account2, &extensions);
    vesting::new_vesting(&mut proposal, 0, 1, OWNER, DummyProposal());
    account2.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account2, key, &clock);
    // try to disable from the account that didn't approve the proposal
    vesting::do_vesting(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        DummyProposal(),
        scenario.ctx()
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_withdraw_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    vesting::new_vesting(&mut proposal, 0, 1, OWNER, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong witness that didn't approve the proposal
    vesting::do_vesting(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        version::current(), 
        WrongProposal(),
        scenario.ctx()
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_withdraw_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut proposal = create_dummy_proposal(&mut scenario, &mut account, &extensions);
    vesting::new_vesting(&mut proposal, 0, 1, OWNER, DummyProposal());
    account.add_proposal(proposal, version::current(), DummyProposal());

    multisig::approve_proposal(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_proposal(&mut account, key, &clock);
    // try to disable with the wrong version TypeName that didn't approve the proposal
    vesting::do_vesting(
        &mut executable, 
        &mut account, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        wrong_version(), 
        DummyProposal(),
        scenario.ctx()
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}