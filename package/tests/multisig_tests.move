#[test_only]
module kraken::multisig_tests {
    use std::{
        string::utf8,
        type_name
    };

    use sui::test_utils::assert_eq;
    
    use kraken::multisig;
    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xa11e7;
    const BOB: address = @0x10;
    const HACKER: address = @0x7ac1e7;

    public struct Witness has drop {}

    public struct Witness2 has drop {}

    public struct Action has store {
        value: u64
    }

    public struct Action2 has store {
        value: u64
    }

    #[test]
    fun test_new() {
        let mut world = start_world();

        let sender = world.scenario().ctx().sender();
        let multisig = world.multisig();

        assert_eq(multisig.name(), utf8(b"kraken"));
        assert_eq(multisig.threshold(), 1);
        assert_eq(multisig.member_addresses(), vector[sender]);
        assert_eq(multisig.proposals_length(), 0);

        world.end();
    } 

    #[test]
    fun test_create_proposal() {
        let mut world = start_world();

        let proposal = world.create_proposal(
            Witness {},
            utf8(b"key"),
            5,
            2,
            utf8(b"proposal1"),
        );

        proposal.add_action(Action { value: 1 });
        proposal.add_action(Action { value: 2 });   

        assert_eq(proposal.approved(), vector[]);
        assert_eq(proposal.module_witness(), type_name::get<Witness>());
        assert_eq(proposal.description(), utf8(b"proposal1"));
        assert_eq(proposal.expiration_epoch(), 2);
        assert_eq(proposal.execution_time(), 5);
        assert_eq(proposal.approval_weight(), 0);
        assert_eq(proposal.actions_length(), 2);

        world.end();
    }

    #[test]
    fun test_approve_proposal() {
        let mut world = start_world();

        world.multisig().add_members(
            vector[ALICE, BOB],
            vector[2, 3]
        );

        let proposal = world.create_proposal(
            Witness {},
            utf8(b"key"),
            5,
            2,
            utf8(b"proposal1"),
        );

        proposal.add_action(Action { value: 1 });
        proposal.add_action(Action { value: 2 });   

        assert_eq(proposal.approved(), vector[]);
        assert_eq(proposal.module_witness(), type_name::get<Witness>());
        assert_eq(proposal.description(), utf8(b"proposal1"));
        assert_eq(proposal.expiration_epoch(), 2);
        assert_eq(proposal.execution_time(), 5);
        assert_eq(proposal.approval_weight(), 0);
        assert_eq(proposal.actions_length(), 2);

        world.scenario().next_tx(ALICE);

        world.approve_proposal(utf8(b"key"));

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.approval_weight(), 2);

        world.scenario().next_tx(BOB);

        world.approve_proposal(utf8(b"key"));

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.approval_weight(), 5);

        world.end();        
    }

    #[test]
    fun test_remove_approval() {
        let mut world = start_world();

        world.multisig().add_members(
            vector[ALICE, BOB],
            vector[2, 3]
        );

        let proposal = world.create_proposal(
            Witness {},
            utf8(b"key"),
            5,
            2,
            utf8(b"proposal1"),
        );

        proposal.add_action(Action { value: 1 });
        proposal.add_action(Action { value: 2 });   

        assert_eq(proposal.approved(), vector[]);
        assert_eq(proposal.module_witness(), type_name::get<Witness>());
        assert_eq(proposal.description(), utf8(b"proposal1"));
        assert_eq(proposal.expiration_epoch(), 2);
        assert_eq(proposal.execution_time(), 5);
        assert_eq(proposal.approval_weight(), 0);
        assert_eq(proposal.actions_length(), 2);

        world.scenario().next_tx(ALICE);

        world.approve_proposal(utf8(b"key"));

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.approval_weight(), 2);

        world.scenario().next_tx(BOB);

        world.approve_proposal(utf8(b"key"));

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.approval_weight(), 5);

        world.scenario().next_tx(BOB);

        world.remove_approval(utf8(b"key"));

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.approval_weight(), 2);        

        world.end();        
    }

    #[test]
    fun test_delete_proposal() {
        let mut world = start_world();

        world.create_proposal(
            Witness {},
            utf8(b"key"),
            5,
            2,
            utf8(b"proposal1"),
        );        

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);

        assert_eq(world.multisig().proposals_length(), 1);

        let actions = world.delete_proposal(utf8(b"key"));

        actions.destroy_empty();

        assert_eq(world.multisig().proposals_length(), 0);

        world.end();
    }

    #[test]
    fun test_setters() {
        let mut world = start_world();

        assert_eq(world.multisig().name(), utf8(b"kraken"));
        assert_eq(world.multisig().version(), 1);
        assert_eq(world.multisig().threshold(), 1);

        world.multisig().set_name(utf8(b"krakenV2"));
        world.multisig().set_version(2);
        world.multisig().set_threshold(3);

        assert_eq(world.multisig().name(), utf8(b"krakenV2"));
        assert_eq(world.multisig().version(), 2);
        assert_eq(world.multisig().threshold(), 3);

        world.end();        
    }

//     #[test]
//     #[expected_failure(abort_code = multisig::ECantBeExecutedYet)]
//     fun test_execute_proposal_error_cant_be_executed_yet() {
//         let mut world = start_world();

//         world.multisig().add_members(vector[ALICE, BOB]);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
//         world.multisig().set_threshold(2);
//         assert_eq(world.multisig().proposals_length(), 1);

//         world.approve_proposal(string::utf8(b"1"));
//         world.scenario().next_tx(ALICE);

//         world.approve_proposal(string::utf8(b"1"));

//         world.clock().set_for_testing(99);

//         let Action { value: _ } = world.execute_proposal(string::utf8(b"1")).unpack_action();

//         world.end();     
//     }           
}