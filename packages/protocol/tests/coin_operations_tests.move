// #[test_only]
// module account_protocol::coin_operations_tests;

// use sui::{
//     sui::SUI,
//     coin::{Self, Coin},
//     test_utils::destroy,
//     test_scenario::most_recent_receiving_ticket
// };
// use account_protocol::account_test_utils::start_world;

// const OWNER: address = @0xBABE;

// #[test]
// fun test_merge_and_split_2_coins() {
//     let mut world = start_world();

//     let coin_to_split = coin::mint_for_testing<SUI>(100, world.scenario().ctx());
//     let account_address = world.account().addr();
//     transfer::public_transfer(coin_to_split, account_address);
    
//     world.scenario().next_tx(OWNER);
//     let receiving_to_split = most_recent_receiving_ticket<Coin<SUI>>(&account_address.to_id());
//     let split_coin_ids = world.merge_and_split<SUI>(
//         vector[receiving_to_split],
//         vector[40, 30]
//     );

//     world.scenario().next_tx(OWNER);
//     let split_coin0 = world.scenario().take_from_address_by_id<Coin<SUI>>(
//         account_address, 
//         split_coin_ids[0]
//     );
//     let split_coin1 = world.scenario().take_from_address_by_id<Coin<SUI>>(
//         account_address, 
//         split_coin_ids[1]
//     );
//     assert!(split_coin0.value() == 40);
//     assert!(split_coin1.value() == 30);

//     destroy(split_coin0);
//     destroy(split_coin1);
//     world.end();          
// }  

// #[test]
// fun test_merge_2_coins_and_split() {
//     let mut world = start_world();
//     let account_address = world.account().addr();

//     let coin1 = coin::mint_for_testing<SUI>(60, world.scenario().ctx());
//     transfer::public_transfer(coin1, account_address);
//     world.scenario().next_tx(OWNER);
//     let receiving1 = most_recent_receiving_ticket<Coin<SUI>>(&account_address.to_id());

//     let coin2 = coin::mint_for_testing<SUI>(40, world.scenario().ctx());
//     transfer::public_transfer(coin2, account_address);
//     world.scenario().next_tx(OWNER);
//     let receiving2 = most_recent_receiving_ticket<Coin<SUI>>(&account_address.to_id());
    
//     let merge_coin_id = world.merge_and_split<SUI>(
//         vector[receiving1, receiving2],
//         vector[100]
//     );

//     world.scenario().next_tx(OWNER);
//     let merge_coin = world.scenario().take_from_address_by_id<Coin<SUI>>(
//         account_address, 
//         merge_coin_id[0]
//     );
//     assert!(merge_coin.value() == 100);

//     destroy(merge_coin);
//     world.end();          
// }  