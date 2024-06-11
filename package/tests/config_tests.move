// #[test_only]
// module kraken::config_tests{
//     use std::string;

//     use sui::test_utils::assert_eq;

//     use kraken::config;
//     use kraken::test_utils::start_world;

//     const OWNER: address = @0xBABE;
//     const ALICE: address = @0xA11CE;
//     const BOB: address = @0xB0B;

//     #[test]
//     fun test_end_to_end() {
//         let mut world = start_world();

//         let sender = world.scenario().ctx().sender();
//         let multisig = world.multisig();

//         assert_eq(multisig.name(), string::utf8(b"kraken"));
//         assert_eq(multisig.threshold(), 1);
//         assert_eq(multisig.members(), vector[sender]);
//         assert_eq(multisig.num_of_proposals(), 0);

//         world.propose_modify(
//             string::utf8(b"modify"), 
//             100, 
//             2, 
//             string::utf8(b"update parameters"), 
//             option::some(string::utf8(b"kraken-2")),
//             option::some(2),
//             vector[ALICE, BOB],
//             vector[OWNER]
//         );

//         world.approve_proposal(string::utf8(b"modify"));
//         world.scenario().next_tx(OWNER);
//         world.scenario().next_tx(OWNER);
//         world.scenario().next_tx(OWNER);
//         world.clock().set_for_testing(101);

//         world.execute_modify(string::utf8(b"modify"));

//         let multisig = world.multisig();

//         assert_eq(multisig.name(), string::utf8(b"kraken-2"));
//         assert_eq(multisig.threshold(), 2);
//         assert_eq(multisig.members(), vector[BOB, ALICE]);
//         assert_eq(multisig.num_of_proposals(), 0);        

//         world.end();        
//     }

//     #[test]
//     #[expected_failure(abort_code = config::EAlreadyMember)]
//     fun test_propose_modify_error_already_member() {
//         let mut world = start_world();

//         world.propose_modify(
//             string::utf8(b"modify"), 
//             100, 
//             2, 
//             string::utf8(b"update parameters"), 
//             option::some(string::utf8(b"kraken-2")),
//             option::some(2),
//             vector[OWNER],
//             vector[OWNER]
//         );      

//         world.end();         
//     }

//     #[test]
//     #[expected_failure(abort_code = config::ENotMember)]
//     fun test_propose_modify_error_not_member() {
//         let mut world = start_world();

//         world.propose_modify(
//             string::utf8(b"modify"), 
//             100, 
//             2, 
//             string::utf8(b"update parameters"), 
//             option::some(string::utf8(b"kraken-2")),
//             option::some(2),
//             vector[BOB],
//             vector[ALICE]
//         );      

//         world.end();         
//     } 

//     #[test]
//     #[expected_failure(abort_code = config::EThresholdNull)]
//     fun test_propose_modify_error_threshold_null() {
//         let mut world = start_world();

//         world.propose_modify(
//             string::utf8(b"modify"), 
//             100, 
//             2, 
//             string::utf8(b"update parameters"), 
//             option::some(string::utf8(b"kraken-2")),
//             option::some(0),
//             vector[],
//             vector[]
//         );      

//         world.end();         
//     }   


//     #[test]
//     #[expected_failure(abort_code = config::EThresholdTooHigh)]
//     fun test_propose_modify_error_threshold_too_high() {
//         let mut world = start_world();

//         world.propose_modify(
//             string::utf8(b"modify"), 
//             100, 
//             2, 
//             string::utf8(b"update parameters"), 
//             option::some(string::utf8(b"kraken-2")),
//             option::some(4),
//             vector[ALICE, BOB],
//             vector[]
//         );      

//         world.end();         
//     }           
// }