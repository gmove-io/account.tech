// #[test_only]
// module kraken::payments_tests { 
//     use std::string::utf8;

//     use sui::sui::SUI;
//     use sui::coin::{mint_for_testing, Coin};
//     use sui::test_utils::{assert_eq, destroy};
//     use sui::test_scenario::{receiving_ticket_by_id, take_from_address, take_from_sender, take_shared};

//     use kraken::test_utils::start_world;
//     use kraken::payments::{Self, Stream};

//     const OWNER: address = @0xBABE;
//     const ALICE: address = @0xa11e7;

//     #[test]
//     fun test_pay() {
//         let mut world = start_world();

//         let coin = mint_for_testing<SUI>(30, world.scenario().ctx());

//         let multisig_address = world.multisig().addr();
//         let coin_id = object::id(&coin);

//         transfer::public_transfer(coin, multisig_address);

//         world.propose_pay(
//             utf8(b"1"),
//             30,
//             1,
//             utf8(b"pay 100 sui"),
//             coin_id,
//             10,
//             2,
//             ALICE
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal(utf8(b"1"));

//         world.create_stream<SUI>(action, receiving_ticket_by_id(coin_id));     

//         world.scenario().next_tx(OWNER);

//         let mut stream = take_shared<Stream<SUI>>(world.scenario());

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         world.scenario().next_tx(ALICE);

//         assert_eq(take_from_sender<Coin<SUI>>(world.scenario()).burn_for_testing(), 10);

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
        
//         stream.pay(world.scenario().ctx());

//         world.scenario().next_tx(ALICE);

//         assert_eq(take_from_sender<Coin<SUI>>(world.scenario()).burn_for_testing(), 10);

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         world.scenario().next_tx(ALICE);

//         assert_eq(take_from_sender<Coin<SUI>>(world.scenario()).burn_for_testing(), 10); 

//         stream.complete_stream();       

//         world.end();
//     }

//     #[test]
//     fun test_cancel_payment() {
//         let mut world = start_world();

//         let coin = mint_for_testing<SUI>(30, world.scenario().ctx());

//         let multisig_address = world.multisig().addr();
//         let coin_id = object::id(&coin);

//         transfer::public_transfer(coin, multisig_address);

//         world.propose_pay(
//             utf8(b"1"),
//             30,
//             1,
//             utf8(b"pay 100 sui"),
//             coin_id,
//             10,
//             2,
//             ALICE
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal(utf8(b"1"));

//         world.create_stream<SUI>(action, receiving_ticket_by_id(coin_id));     

//         world.scenario().next_tx(OWNER);

//         let mut stream = take_shared<Stream<SUI>>(world.scenario());

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         world.scenario().next_tx(ALICE);

//         assert_eq(take_from_sender<Coin<SUI>>(world.scenario()).burn_for_testing(), 10);

//         world.scenario().next_epoch(OWNER);

//         world.cancel_payment(stream);      

//         world.scenario().next_tx(OWNER);

//         assert_eq(take_from_address<Coin<SUI>>(world.scenario(), multisig_address).burn_for_testing(), 20);

//         world.end();
//     }

//     #[test]
//     #[expected_failure(abort_code = payments::EPayTooEarly)]
//     fun test_pay_error_pay_too_early() {
//         let mut world = start_world();

//         let coin = mint_for_testing<SUI>(30, world.scenario().ctx());

//         let multisig_address = world.multisig().addr();
//         let coin_id = object::id(&coin);

//         transfer::public_transfer(coin, multisig_address);

//         world.propose_pay(
//             utf8(b"1"),
//             30,
//             1,
//             utf8(b"pay 100 sui"),
//             coin_id,
//             10,
//             2,
//             ALICE
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal(utf8(b"1"));

//         world.create_stream<SUI>(action, receiving_ticket_by_id(coin_id));     

//         world.scenario().next_tx(OWNER);

//         let mut stream = take_shared<Stream<SUI>>(world.scenario());

//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         destroy(stream);
//         world.end();
//     }  

//     #[test]
//     #[expected_failure(abort_code = payments::ECompletePaymentBefore)]
//     fun test_complete_stream_error_complete_payment_before() {
//         let mut world = start_world();

//         let coin = mint_for_testing<SUI>(30, world.scenario().ctx());

//         let multisig_address = world.multisig().addr();
//         let coin_id = object::id(&coin);

//         transfer::public_transfer(coin, multisig_address);

//         world.propose_pay(
//             utf8(b"1"),
//             30,
//             1,
//             utf8(b"pay 100 sui"),
//             coin_id,
//             10,
//             2,
//             ALICE
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal(utf8(b"1"));

//         world.create_stream<SUI>(action, receiving_ticket_by_id(coin_id));     

//         world.scenario().next_tx(OWNER);

//         let mut stream = take_shared<Stream<SUI>>(world.scenario());

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         world.scenario().next_epoch(ALICE);

//         stream.complete_stream(); 

//         world.end();
//     }    

//     #[test]
//     #[expected_failure]
//     fun test_cancel_payment_error_not_a_member() {
//         let mut world = start_world();

//         let coin = mint_for_testing<SUI>(30, world.scenario().ctx());

//         let multisig_address = world.multisig().addr();
//         let coin_id = object::id(&coin);

//         transfer::public_transfer(coin, multisig_address);

//         world.propose_pay(
//             utf8(b"1"),
//             30,
//             1,
//             utf8(b"pay 100 sui"),
//             coin_id,
//             10,
//             2,
//             ALICE
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal(utf8(b"1"));

//         world.create_stream<SUI>(action, receiving_ticket_by_id(coin_id));     

//         world.scenario().next_tx(OWNER);

//         let mut stream = take_shared<Stream<SUI>>(world.scenario());

//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);
//         world.scenario().next_epoch(ALICE);

//         stream.pay(world.scenario().ctx());

//         world.scenario().next_epoch(ALICE);

//         world.cancel_payment(stream);   

//         world.end();
//     }         
// }