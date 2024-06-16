#[test_only]
module kraken::account_tests {
    use std::string;

    use sui::{
        test_utils::{assert_eq, destroy}
    };
    
    use kraken::{
        multisig,
        test_utils::start_world,
        account::{Self, Account, Invite}
    };

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;

    #[test]
    fun test_join_multisig() {
        let mut world = start_world();

        account::new(string::utf8(b"Sam"), string::utf8(b"Sam.png"), world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        let mut user_account = world.scenario().take_from_address<Account>(OWNER);
        let mut multisig2 = multisig::new(string::utf8(b"Multisig2"), object::id(&user_account), world.scenario().ctx());

        assert_eq(user_account.username(), string::utf8(b"Sam"));
        assert_eq(user_account.profile_picture(), string::utf8(b"Sam.png"));
        assert_eq(user_account.multisig_ids(), vector[]);

        world.join_multisig(&mut user_account);
        user_account.join_multisig(&mut multisig2, world.scenario().ctx());

        assert_eq(user_account.multisig_ids(), vector[object::id(world.multisig()) ,object::id(&multisig2)]);

        destroy(user_account);
        destroy(multisig2);
        world.end();
    }

    #[test]
    fun test_leave_multisig() {
        let mut world = start_world();

        world.scenario().next_tx(ALICE);

        account::new(string::utf8(b"Alice"), string::utf8(b"Alice.png"), world.scenario().ctx());

        world.scenario().next_tx(ALICE);

        let mut user_account = world.scenario().take_from_address<Account>(ALICE);

        world.multisig().add_members(vector[ALICE], vector[2]);
        world.join_multisig(&mut user_account);

        assert_eq(user_account.multisig_ids(), vector[object::id(world.multisig())]);

        world.leave_multisig(&mut user_account);

        assert_eq(user_account.multisig_ids(), vector[]);
        user_account.destroy();
        
        world.end();
    }

    #[test]
    fun test_accept_invite() {
        let mut world = start_world();

        world.scenario().next_tx(ALICE);

        account::new(string::utf8(b"Alice"), string::utf8(b"Alice.png"), world.scenario().ctx());

        world.scenario().next_tx(ALICE);

        let mut user_account = world.scenario().take_from_address<Account>(ALICE);

        world.multisig().add_members(vector[ALICE], vector[2]);

        assert_eq(user_account.multisig_ids(), vector[]);

        world.send_invite(ALICE);

        world.scenario().next_tx(ALICE);

        let invite = world.scenario().take_from_address<Invite>(ALICE);

        assert_eq(invite.multisig_id(), object::id(world.multisig()));

        world.accept_invite(&mut user_account, invite);

        assert_eq(user_account.multisig_ids(), vector[object::id(world.multisig())]);
        
        destroy(user_account);
        world.end();
    }

    #[test]
    fun test_refuse_invite() {
        let mut world = start_world();

        world.scenario().next_tx(ALICE);

        account::new(string::utf8(b"Alice"), string::utf8(b"Alice.png"), world.scenario().ctx());

        world.scenario().next_tx(ALICE);

        let user_account = world.scenario().take_from_address<Account>(ALICE);

        world.multisig().add_members(vector[ALICE], vector[2]);

        assert_eq(user_account.multisig_ids(), vector[]);

        world.send_invite(ALICE);

        world.scenario().next_tx(ALICE);

        let invite = world.scenario().take_from_address<Invite>(ALICE);

        invite.refuse_invite();
        
        destroy(user_account);
        world.end();
    }
}