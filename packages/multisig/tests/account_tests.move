#[test_only]
module kraken_multisig::account_tests;

use sui::test_utils::destroy;
use kraken_multisig::{
    multisig,
    members,
    multisig_test_utils::start_world,
    account::{Self, Account, Invite}
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xA11CE;

#[test]
fun test_join_multisig() {
    let mut world = start_world();

    account::new(b"Sam".to_string(), b"Sam.png".to_string(), world.scenario().ctx());

    world.scenario().next_tx(OWNER);
    let mut user_account = world.scenario().take_from_address<Account>(OWNER);
    let mut multisig2 = multisig::new(
        b"Multisig2".to_string(), 
        object::id(&user_account), 
        vector[@kraken_multisig, @0xCAFE], 
        vector[1, 1], 
        vector[b"KrakenMultisig".to_string(), b"KrakenActions".to_string()], 
        world.scenario().ctx()
    );
    assert!(user_account.username() == b"Sam".to_string());
    assert!(user_account.profile_picture() == b"Sam.png".to_string());
    assert!(user_account.multisig_ids() == vector[]);

    world.join_multisig(&mut user_account);
    user_account.join_multisig(&mut multisig2, world.scenario().ctx());
    assert!(user_account.multisig_ids() == vector[object::id(world.multisig()) ,object::id(&multisig2)]);

    destroy(user_account);
    destroy(multisig2);
    world.end();
}

#[test]
fun test_leave_multisig() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);
    account::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());

    world.scenario().next_tx(ALICE);
    let mut user_account = world.scenario().take_from_address<Account>(ALICE);
    let member = members::new_member(ALICE, 1, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(member);
    
    world.join_multisig(&mut user_account);
    assert!(user_account.multisig_ids() == vector[object::id(world.multisig())]);

    world.leave_multisig(&mut user_account);
    assert!(user_account.multisig_ids() == vector[]);
    
    user_account.destroy();
    world.end();
}

#[test]
fun test_accept_invite() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);
    account::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());

    world.scenario().next_tx(ALICE);
    let mut user_account = world.scenario().take_from_address<Account>(ALICE);
    let member = members::new_member(ALICE, 1, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(member);
    assert!(user_account.multisig_ids() == vector[]);
    world.send_invite(ALICE);

    world.scenario().next_tx(ALICE);
    let invite = world.scenario().take_from_address<Invite>(ALICE);
    assert!(invite.multisig_id() == object::id(world.multisig()));
    world.accept_invite(&mut user_account, invite);
    assert!(user_account.multisig_ids() == vector[object::id(world.multisig())]);
    
    destroy(user_account);
    world.end();
}

#[test]
fun test_refuse_invite() {
    let mut world = start_world();

    world.scenario().next_tx(ALICE);
    account::new(b"Alice".to_string(), b"Alice.png".to_string(), world.scenario().ctx());

    world.scenario().next_tx(ALICE);
    let user_account = world.scenario().take_from_address<Account>(ALICE);
    let member = members::new_member(ALICE, 1, option::none(), vector[]);
    world.multisig().members_mut_for_testing().add(member);
    assert!(user_account.multisig_ids() == vector[]);
    world.send_invite(ALICE);

    world.scenario().next_tx(ALICE);
    let invite = world.scenario().take_from_address<Invite>(ALICE);
    invite.refuse_invite();
    
    destroy(user_account);
    world.end();
}