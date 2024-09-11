#[test_only]
module kraken_multisig::coin_operations_tests;

use sui::{
    sui::SUI,
    coin::{Self, Coin},
    test_utils::destroy,
    test_scenario::most_recent_receiving_ticket
};
use kraken_multisig::multisig_test_utils::start_world;

const OWNER: address = @0xBABE;

#[test]
fun test_merge_and_split_2_coins() {
    let mut world = start_world();

    let coin_to_split = coin::mint_for_testing<SUI>(100, world.scenario().ctx());
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(coin_to_split, multisig_address);
    
    world.scenario().next_tx(OWNER);
    let receiving_to_split = most_recent_receiving_ticket<Coin<SUI>>(&multisig_address.to_id());
    let split_coin_ids = world.merge_and_split<SUI>(
        vector[receiving_to_split],
        vector[30, 40] // LIFO
    );

    world.scenario().next_tx(OWNER);
    let split_coin0 = world.scenario().take_from_address_by_id<Coin<SUI>>(
        multisig_address, 
        split_coin_ids[0]
    );
    let split_coin1 = world.scenario().take_from_address_by_id<Coin<SUI>>(
        multisig_address, 
        split_coin_ids[1]
    );
    assert!(split_coin0.value() == 40);
    assert!(split_coin1.value() == 30);

    destroy(split_coin0);
    destroy(split_coin1);
    world.end();          
}  

#[test]
fun test_merge_2_coins_and_split() {
    let mut world = start_world();
    let multisig_address = world.multisig().addr();

    let coin1 = coin::mint_for_testing<SUI>(60, world.scenario().ctx());
    transfer::public_transfer(coin1, multisig_address);
    world.scenario().next_tx(OWNER);
    let receiving1 = most_recent_receiving_ticket<Coin<SUI>>(&multisig_address.to_id());

    let coin2 = coin::mint_for_testing<SUI>(40, world.scenario().ctx());
    transfer::public_transfer(coin2, multisig_address);
    world.scenario().next_tx(OWNER);
    let receiving2 = most_recent_receiving_ticket<Coin<SUI>>(&multisig_address.to_id());
    
    let merge_coin_id = world.merge_and_split<SUI>(
        vector[receiving1, receiving2],
        vector[100] // LIFO
    );

    world.scenario().next_tx(OWNER);
    let merge_coin = world.scenario().take_from_address_by_id<Coin<SUI>>(
        multisig_address, 
        merge_coin_id[0]
    );
    assert!(merge_coin.value() == 100);

    destroy(merge_coin);
    world.end();          
}  