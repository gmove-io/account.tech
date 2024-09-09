#[test_only]
module kraken_actions::payments_tests;

use sui::{
    transfer::Receiving,
    sui::SUI,
    coin::{Coin, mint_for_testing},
    test_scenario::most_recent_receiving_ticket,
};
use kraken_actions::{
    payments::{Self, Stream},
    actions_test_utils::{start_world, World}
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xa11e7;

#[test]
fun pay_end_to_end() {
    let mut world = start_world();
    let key = b"pay proposal".to_string();

    let receiving_coin = mint_transfer_and_return_receiving(&mut world);

    world.propose_pay(key, receiving_coin.receiving_object_id(), 10, 2, ALICE);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    world.execute_pay<SUI>(executable, receiving_coin);

    world.scenario().next_tx(OWNER);
    let mut stream = world.scenario().take_shared<Stream<SUI>>();      

    assert!(stream.balance() == 20);
    assert!(stream.amount() == 10);
    assert!(stream.interval() == 2);
    assert!(stream.last_epoch() == 0);
    assert!(stream.recipient() == ALICE);

    world.scenario().next_tx(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());

    assert!(stream.balance() == 10);
    assert!(stream.amount() == 10);
    assert!(stream.interval() == 2);
    assert!(stream.last_epoch() == 3);
    assert!(stream.recipient() == ALICE);    

    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());

    assert!(stream.balance() == 0);
    assert!(stream.amount() == 10);
    assert!(stream.interval() == 2);
    assert!(stream.last_epoch() == 6);
    assert!(stream.recipient() == ALICE);

    stream.destroy_empty_stream();
    world.end();
}

#[test]
fun cancel_payment_stream() {
    let mut world = start_world();
    let key = b"pay proposal".to_string();

    let receiving_coin = mint_transfer_and_return_receiving(&mut world);

    world.propose_pay(key, receiving_coin.receiving_object_id(), 10, 2, ALICE);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    world.execute_pay<SUI>(executable, receiving_coin);

    world.scenario().next_tx(OWNER);
    let stream = world.scenario().take_shared<Stream<SUI>>();      
    world.cancel_payment_stream(stream);

    world.end();
}  

#[test, expected_failure(abort_code = payments::ECompletePaymentBefore)]
fun destroy_empty_stream_error_complete_payment_before() {
    let mut world = start_world();
    let key = b"pay proposal".to_string();

    let receiving_coin = mint_transfer_and_return_receiving(&mut world);

    world.propose_pay(key, receiving_coin.receiving_object_id(), 10, 2, ALICE);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    world.execute_pay<SUI>(executable, receiving_coin);

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

#[test, expected_failure(abort_code = payments::EPayTooEarly)]
fun disburse_error_pay_too_early() {
    let mut world = start_world();
    let key = b"pay proposal".to_string();

    let receiving_coin = mint_transfer_and_return_receiving(&mut world);

    world.propose_pay(key, receiving_coin.receiving_object_id(), 10, 2, ALICE);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    world.execute_pay<SUI>(executable, receiving_coin);

    world.scenario().next_tx(OWNER);
    let mut stream = world.scenario().take_shared<Stream<SUI>>();      

    world.scenario().next_tx(OWNER);
    world.scenario().next_epoch(OWNER);
    world.scenario().next_epoch(OWNER);

    stream.disburse(world.scenario().ctx());
    
    stream.destroy_empty_stream();
    world.end();
}         

fun mint_transfer_and_return_receiving(world: &mut World): Receiving<Coin<SUI>> {
    let coin = mint_for_testing<SUI>(20, world.scenario().ctx());
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(coin, multisig_address);
    world.scenario().next_tx(OWNER);
    most_recent_receiving_ticket<Coin<SUI>>(&multisig_address.to_id())
}