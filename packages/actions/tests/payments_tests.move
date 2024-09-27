// TODO: move or fix (no more proposal in this module)

// #[test_only]
// module kraken_actions::payments_tests;

// use std::type_name;
// use sui::{
//     sui::SUI,
//     coin::{Coin, mint_for_testing, create_treasury_cap_for_testing},
//     test_scenario::most_recent_receiving_ticket,
// };
// use kraken_actions::{
//     payments::{Self, Stream},
//     actions_test_utils::{start_world, World},
// };

// const OWNER: address = @0xBABE;
// const ALICE: address = @0xa11e7;

// #[test]
// fun test_pay_owned_end_to_end() {
//     let mut world = start_world();

//     pay_owned(&mut world);

//     world.scenario().next_tx(OWNER);
//     let mut stream = world.scenario().take_shared<Stream<SUI>>();      

//     assert!(stream.balance() == 20);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 0);
//     assert!(stream.recipient() == ALICE);

//     world.scenario().next_tx(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 10);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 3);
//     assert!(stream.recipient() == ALICE);    

//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 0);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 6);
//     assert!(stream.recipient() == ALICE);

//     stream.destroy_empty_stream();
//     world.end();
// }

// #[test]
// fun test_pay_treasury_end_to_end() {
//     let mut world = start_world();
//     let key = b"pay proposal".to_string();
//     let name = b"treasury".to_string();
//     let coin_type = type_name::get<SUI>().into_string().to_string();

//     // open treasury and deposit coin
//     world.propose_open(key, name);
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);
//     world.execute_open(executable);
//     world.deposit<SUI>(name, 20);

//     world.propose_pay_treasury(key, name, coin_type, 20, 10, 2, ALICE);
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);
//     world.execute_pay<SUI>(executable, option::none());

//     world.scenario().next_tx(OWNER);
//     let mut stream = world.scenario().take_shared<Stream<SUI>>();      

//     assert!(stream.balance() == 20);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 0);
//     assert!(stream.recipient() == ALICE);

//     world.scenario().next_tx(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 10);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 3);
//     assert!(stream.recipient() == ALICE);    

//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 0);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 6);
//     assert!(stream.recipient() == ALICE);

//     stream.destroy_empty_stream();
//     world.end();
// }

// #[test]
// fun test_pay_minted_end_to_end() {
//     let mut world = start_world();
//     let key = b"pay proposal".to_string();

//     // create treasury cap and lock it
//     let cap = create_treasury_cap_for_testing<SUI>(world.scenario().ctx());
//     world.lock_treasury_cap<SUI>(cap);

//     world.propose_pay_minted<SUI>(key, 20, 10, 2, ALICE);
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);
//     world.execute_pay<SUI>(executable, option::none());

//     world.scenario().next_tx(OWNER);
//     let mut stream = world.scenario().take_shared<Stream<SUI>>();      

//     assert!(stream.balance() == 20);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 0);
//     assert!(stream.recipient() == ALICE);

//     world.scenario().next_tx(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 10);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 3);
//     assert!(stream.recipient() == ALICE);    

//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());

//     assert!(stream.balance() == 0);
//     assert!(stream.amount() == 10);
//     assert!(stream.interval() == 2);
//     assert!(stream.last_epoch() == 6);
//     assert!(stream.recipient() == ALICE);

//     stream.destroy_empty_stream();
//     world.end();
// }

// #[test]
// fun test_cancel_payment_stream() {
//     let mut world = start_world();
    
//     pay_owned(&mut world);

//     world.scenario().next_tx(OWNER);
//     let stream = world.scenario().take_shared<Stream<SUI>>();      
//     world.cancel_payment_stream(stream);

//     world.end();
// }  

// #[test, expected_failure(abort_code = payments::ECompletePaymentBefore)]
// fun test_destroy_empty_stream_error_complete_payment_before() {
//     let mut world = start_world();
    
//     pay_owned(&mut world);

//     world.scenario().next_tx(OWNER);
//     let mut stream = world.scenario().take_shared<Stream<SUI>>();      

//     world.scenario().next_tx(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());
    
//     stream.destroy_empty_stream();
//     world.end();
// } 

// #[test, expected_failure(abort_code = payments::EPayTooEarly)]
// fun test_disburse_error_pay_too_early() {
//     let mut world = start_world();
    
//     pay_owned(&mut world);

//     world.scenario().next_tx(OWNER);
//     let mut stream = world.scenario().take_shared<Stream<SUI>>();      

//     world.scenario().next_tx(OWNER);
//     world.scenario().next_epoch(OWNER);
//     world.scenario().next_epoch(OWNER);

//     stream.disburse(world.scenario().ctx());
    
//     stream.destroy_empty_stream();
//     world.end();
// }         

// // helper functions

// fun pay_owned(world: &mut World) {
//     let key = b"pay proposal".to_string();
//     let coin = mint_for_testing<SUI>(20, world.scenario().ctx());
//     let account_address = world.account().addr();
//     transfer::public_transfer(coin, account_address);

//     world.scenario().next_tx(OWNER);
//     let receiving_coin = most_recent_receiving_ticket<Coin<SUI>>(&account_address.to_id());
    
//     world.propose_pay_owned(key, receiving_coin.receiving_object_id(), 10, 2, ALICE);
//     world.approve_proposal(key);
//     let executable = world.execute_proposal(key);
//     world.execute_pay<SUI>(executable, option::some(receiving_coin));
// }