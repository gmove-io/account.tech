// #[test_only]
// module account_protocol::thresholds_tests;

// use sui::test_utils::destroy;
// use account_protocol::{
//     account,
//     auth,
//     members,
//     thresholds,
//     account_test_utils::start_world
// };

// const OWNER: address = @0xBABE;
// const ALICE: address = @0xa11e7;
// const BOB: address = @0x10;

// public struct Witness has copy, drop {}

// public struct Witness2 has copy, drop {}

// public struct Action has store {
//     value: u64
// }

// #[test, expected_failure(abort_code = thresholds::EThresholdNotReached)]
// fun test_execute_proposal_error_threshold_not_reached() {
//     let mut world = start_world();
//     let key = b"key".to_string();

//     world.account().members_mut_for_testing().add(ALICE, 2, option::none(), vector[]);
//     world.account().members_mut_for_testing().add(BOB, 3, option::none(), vector[]);

//     let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
//     world.account().add_proposal(proposal, Witness {});
//     let executable = world.execute_proposal(key);

//     destroy(executable);
//     world.end();
// } 