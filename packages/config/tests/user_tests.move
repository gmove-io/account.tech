// #[test_only]
// module account_protocol::user_tests;

// use sui::test_utils::destroy;
// use account_protocol::{
//     account,
//     members,
//     account_test_utils::start_world,
//     user::{Self, User, Invite}
// };

// const OWNER: address = @0xBABE;
// const ALICE: address = @0xA11CE;

// #[test]
// fun test_join_account() {
//     let mut world = start_world();

//     world.scenario().next_tx(OWNER);
//     let mut user = user::new(b"Sam".to_string(), b"Sam.png".to_string(), world.scenario().ctx());
//     let mut account2 = world.new_account();
//     assert!(user.username() == b"Sam".to_string());
//     assert!(user.profile_picture() == b"Sam.png".to_string());
//     assert!(user.account_ids() == vector[]);

//     world.join_account(&mut user);
//     user.join_account(&mut account2, world.scenario().ctx());
//     assert!(user.account_ids() == vector[object::id(world.account()) ,object::id(&account2)]);

//     destroy(user);
//     destroy(account2);
//     world.end();
// }

// #[test]
// fun test_leave_account() {
//     let mut world = start_world();

//     world.scenario().next_tx(ALICE);
//     let mut user = user::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());
//     world.account().members_mut_for_testing().add(ALICE, 1, option::none(), vector[]);
    
//     world.join_account(&mut user);
//     assert!(user.account_ids() == vector[object::id(world.account())]);

//     world.leave_account(&mut user);
//     assert!(user.account_ids() == vector[]);
    
//     user.destroy();
//     world.end();
// }

// #[test]
// fun test_accept_invite() {
//     let mut world = start_world();

//     world.scenario().next_tx(ALICE);
//     let mut user = user::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());
//     world.account().members_mut_for_testing().add(ALICE, 1, option::none(), vector[]);
//     assert!(user.account_ids() == vector[]);
//     world.send_invite(ALICE);

//     world.scenario().next_tx(ALICE);
//     let invite = world.scenario().take_from_address<Invite>(ALICE);
//     assert!(invite.account_id() == object::id(world.account()));
//     world.accept_invite(&mut user, invite);
//     assert!(user.account_ids() == vector[object::id(world.account())]);
    
//     destroy(user);
//     world.end();
// }

// #[test]
// fun test_refuse_invite() {
//     let mut world = start_world();

//     world.scenario().next_tx(ALICE);
//     let user = user::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());
//     world.account().members_mut_for_testing().add(ALICE, 1, option::none(), vector[]);
//     assert!(user.account_ids() == vector[]);
//     world.send_invite(ALICE);

//     world.scenario().next_tx(ALICE);
//     let invite = world.scenario().take_from_address<Invite>(ALICE);
//     invite.refuse_invite();
    
//     destroy(user);
//     world.end();
// }