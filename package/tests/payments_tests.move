#[test_only]
module kraken::payments_tests;

use std::string::utf8;

use sui::sui::SUI;
use sui::coin::mint_for_testing;
use sui::test_utils::assert_eq;
use sui::test_scenario::receiving_ticket_by_id;

use kraken::test_utils::start_world;
use kraken::payments::{Self, Stream};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;

#[test]
fun test_pay_end_to_end() {
    let mut world = start_world();

    let coin = mint_for_testing<SUI>(20, world.scenario().ctx());

    let multisig_address = world.multisig().addr();
    let coin_id = object::id(&coin);

    transfer::public_transfer(coin, multisig_address);

    world.propose_pay(
        utf8(b"1"),
        30,
        1,
        utf8(b"pay 100 sui"),
        coin_id,
        10,
        2,
        ALICE
    );

    world.scenario().next_tx(OWNER);
    world.approve_proposal(utf8(b"1"));

    world.clock().set_for_testing(30);

    let executable = world.execute_proposal(utf8(b"1"));

    world.execute_pay<SUI>(executable, receiving_ticket_by_id(coin_id));

    world.scenario().next_tx(OWNER);

    let mut stream = world.scenario().take_shared<Stream<SUI>>();      

    assert_eq(stream.balance(), 20);
    assert_eq(stream.amount(), 10);
    assert_eq(stream.interval(), 2);
    assert_eq(stream.last_epoch(), 0);
    assert_eq(stream.recipient(), ALICE);

    world.scenario().next_tx(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());

    assert_eq(stream.balance(), 10);
    assert_eq(stream.amount(), 10);
    assert_eq(stream.interval(), 2);
    assert_eq(stream.last_epoch(), 3);
    assert_eq(stream.recipient(), ALICE);    

    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());

    assert_eq(stream.balance(), 0);
    assert_eq(stream.amount(), 10);
    assert_eq(stream.interval(), 2);
    assert_eq(stream.last_epoch(), 6);
    assert_eq(stream.recipient(), ALICE);

    stream.destroy_empty_stream();
    world.end();
}

#[test]
fun test_cancel_payment_stream() {
    let mut world = start_world();

    let coin = mint_for_testing<SUI>(20, world.scenario().ctx());

    let multisig_address = world.multisig().addr();
    let coin_id = object::id(&coin);

    transfer::public_transfer(coin, multisig_address);

    world.propose_pay(
        utf8(b"1"),
        30,
        1,
        utf8(b"pay 100 sui"),
        coin_id,
        10,
        2,
        ALICE
    );

    world.scenario().next_tx(OWNER);
    world.approve_proposal(utf8(b"1"));

    world.clock().set_for_testing(30);

    let executable = world.execute_proposal(utf8(b"1"));

    world.execute_pay<SUI>(executable, receiving_ticket_by_id(coin_id));

    world.scenario().next_tx(OWNER);

    let stream = world.scenario().take_shared<Stream<SUI>>();      

    world.cancel_payment_stream(stream);

    world.end();
}  

#[test]
#[expected_failure(abort_code = payments::ECompletePaymentBefore)]
fun test_destroy_empty_stream_error_complete_payment_before() {
    let mut world = start_world();

    let coin = mint_for_testing<SUI>(20, world.scenario().ctx());

    let multisig_address = world.multisig().addr();
    let coin_id = object::id(&coin);

    transfer::public_transfer(coin, multisig_address);

    world.propose_pay(
        utf8(b"1"),
        30,
        1,
        utf8(b"pay 100 sui"),
        coin_id,
        10,
        2,
        ALICE
    );

    world.scenario().next_tx(OWNER);
    world.approve_proposal(utf8(b"1"));

    world.clock().set_for_testing(30);

    let executable = world.execute_proposal(utf8(b"1"));

    world.execute_pay<SUI>(executable, receiving_ticket_by_id(coin_id));

    world.scenario().next_tx(OWNER);

    let mut stream = world.scenario().take_shared<Stream<SUI>>();      

    world.scenario().next_tx(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());
    
    stream.destroy_empty_stream();
    world.end();
} 

#[test]
#[expected_failure(abort_code = payments::EPayTooEarly)]
fun test_disburse_error_pay_too_early() {
    let mut world = start_world();

    let coin = mint_for_testing<SUI>(20, world.scenario().ctx());

    let multisig_address = world.multisig().addr();
    let coin_id = object::id(&coin);

    transfer::public_transfer(coin, multisig_address);

    world.propose_pay(
        utf8(b"1"),
        30,
        1,
        utf8(b"pay 100 sui"),
        coin_id,
        10,
        2,
        ALICE
    );

    world.scenario().next_tx(OWNER);
    world.approve_proposal(utf8(b"1"));

    world.clock().set_for_testing(30);

    let executable = world.execute_proposal(utf8(b"1"));

    world.execute_pay<SUI>(executable, receiving_ticket_by_id(coin_id));

    world.scenario().next_tx(OWNER);

    let mut stream = world.scenario().take_shared<Stream<SUI>>();      

    world.scenario().next_tx(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());
    
    stream.destroy_empty_stream();
    world.end();
}         