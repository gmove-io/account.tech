// #[test_only]
// module kraken::move_call_tests{    
//     use std::string;

//     use sui::test_utils::destroy;

//     use kraken::test_utils::start_world;
//     use kraken::move_call::{Self, MoveCall};

//     const OWNER: address = @0xBABE;

//     #[test]
//     fun test_move_call() {
//         let mut world = start_world();

//         let ctx = tx_context::dummy();

//         world.propose_move_call(
//             string::utf8(b"1"), 
//             100, 
//             2, 
//             string::utf8(b"move_call"), 
//             *ctx.digest(), 
//             vector[], 
//             vector[], 
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(string::utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal<MoveCall>(string::utf8(b"1"));

//         let (withdraw, borrow) = move_call::execute_move_call(action, &ctx);

//         destroy(withdraw);
//         destroy(borrow);
//         world.end();
//     }

//     #[test]
//     #[expected_failure(abort_code = move_call::EDigestDoesntMatch)]    
//     fun test_move_call_error_digest_doesnt_match() {
//         let mut world = start_world();

//         let ctx = tx_context::dummy();

//         world.propose_move_call(
//             string::utf8(b"1"), 
//             100, 
//             2, 
//             string::utf8(b"move_call"), 
//             *ctx.digest(), 
//             vector[], 
//             vector[], 
//         );

//         world.scenario().next_tx(OWNER);

//         world.approve_proposal(string::utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let action = world.execute_proposal<MoveCall>(string::utf8(b"1"));

//         let (withdraw, borrow) = move_call::execute_move_call(action, world.scenario().ctx());

//         destroy(withdraw);
//         destroy(borrow);
//         world.end();
//     }    
// }