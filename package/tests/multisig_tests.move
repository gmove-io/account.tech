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

//     #[test]
//     fun test_create_proposal() {
//         let mut world = start_world();

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
//         world.create_proposal(Action { value: 1 }, string::utf8(b"2"), 101, 3, string::utf8(b"test-2"));

//         assert_eq(world.multisig().proposals_length(), 2);

//         let proposal1 = world.multisig().proposal(&string::utf8(b"1"));
        
//         assert_eq(proposal1.description(), string::utf8(b"test-1"));
//         assert_eq(proposal1.expiration_epoch(), 2);
//         assert_eq(proposal1.execution_time(), 100);
//         assert_eq(proposal1.approved(), vector[]);

//         let proposal2 = world.multisig().proposal(&string::utf8(b"2"));

//         assert_eq(proposal2.description(), string::utf8(b"test-2"));
//         assert_eq(proposal2.expiration_epoch(), 3);
//         assert_eq(proposal2.execution_time(), 101);
//         assert_eq(proposal2.approved(), vector[]);

//         world.end();
//     }

//     #[test]
//     fun test_delete_proposal() {
//         let mut world = start_world();

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
//         assert_eq(world.multisig().proposals_length(), 1);

//         world.delete_proposal(string::utf8(b"1"));
//         assert_eq(world.multisig().proposals_length(), 0);

//         world.end();
//     }

//     #[test]
//     fun test_approve_proposal() {
//         let mut world = start_world();

//         world.multisig().add_members(vector[ALICE, BOB]);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[]);

//         world.approve_proposal(string::utf8(b"1"));

//         world.scenario().next_tx(ALICE);

//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER]);  

//         world.approve_proposal(string::utf8(b"1"));    

//         world.scenario().next_tx(BOB); 

//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER, ALICE]);  

//         world.approve_proposal(string::utf8(b"1"));

//         world.scenario().next_tx(BOB); 

//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER, ALICE, BOB]);          

//         world.end();
//     }

//     #[test]
//     fun test_remove_approval() {
//         let mut world = start_world();

//         world.multisig().add_members(vector[ALICE, BOB]);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

//         world.approve_proposal(string::utf8(b"1"));
//         world.scenario().next_tx(ALICE);

//         world.approve_proposal(string::utf8(b"1"));
//         world.scenario().next_tx(BOB);

//         world.approve_proposal(string::utf8(b"1"));

//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER, ALICE, BOB]);

//         world.remove_approval(string::utf8(b"1"));      
//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER, ALICE]);

//         world.scenario().next_tx(ALICE);
//          world.remove_approval(string::utf8(b"1")); 
//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[OWNER]);

//         world.scenario().next_tx(OWNER);
//         world.remove_approval(string::utf8(b"1")); 
//         let proposal = world.multisig().proposal(&string::utf8(b"1"));
//         assert_eq(proposal.approved(), vector[]);

//         world.end();        
//     }

//     #[test]
//     fun test_execute_proposal() {
//         let mut world = start_world();

//         world.multisig().add_members(vector[ALICE, BOB]);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
//         world.multisig().set_threshold(2);
//         assert_eq(world.multisig().proposals_length(), 1);

//         world.approve_proposal(string::utf8(b"1"));
//         world.scenario().next_tx(ALICE);

//         world.approve_proposal(string::utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let Action { value } = world.execute_proposal(string::utf8(b"1")).unpack_action();
//         assert_eq(world.multisig().proposals_length(), 0);

//         assert_eq(value, 1);

//         world.end();        
//     }

//     #[test]
//     fun test_set_functions() {
//         let mut world = start_world();

//         assert_eq(world.multisig().name(), string::utf8(b"kraken"));

//         world.multisig().set_name(string::utf8(b"kraken-2"));
//         assert_eq(world.multisig().name(), string::utf8(b"kraken-2"));

//         assert_eq(world.multisig().threshold(), 1);
//         world.multisig().set_threshold(11);
//         assert_eq(world.multisig().threshold(), 11);

//         let sender = world.scenario().ctx().sender();
//         assert_eq(world.multisig().members(), vector[sender]);

//         world.multisig().add_members(vector[ALICE]);
//         assert_eq(world.multisig().members(), vector[sender, ALICE]);

//         world.multisig().remove_members(vector[ALICE]);
//         assert_eq(world.multisig().members(), vector[sender]);

//         world.end();
//     }    

//     #[test]
//     #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
//     fun test_create_proposal_error_caller_is_not_member() {
//         let mut world = start_world();

//         world.scenario().next_tx(HACKER);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

//         world.end();        
//     }

//     #[test]
//     #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
//     fun test_delete_proposal_error_caller_is_not_member() {
//         let mut world = start_world();

//         world.scenario().next_tx(HACKER);

//         world.delete_proposal(string::utf8(b"1"));

//         world.end();        
//     } 

//     #[test]
//     #[expected_failure(abort_code = multisig::EProposalNotEmpty)]
//     fun test_delete_proposal_error_proposal_not_empty() {
//         let mut world = start_world();

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

//         world.approve_proposal(string::utf8(b"1"));

//         world.delete_proposal(string::utf8(b"1"));

//         world.end();        
//     }           

//     #[test]
//     #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
//     fun test_approve_proposal_error_caller_is_not_member() {
//         let mut world = start_world();

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

//         world.scenario().next_tx(HACKER);

//         world.approve_proposal(string::utf8(b"1"));

//         world.end();     
//     } 

//     #[test]
//     #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
//     fun test_remove_approval_error_caller_is_not_member() {
//         let mut world = start_world();

//         world.scenario().next_tx(HACKER);

//         world.remove_approval(string::utf8(b"1"));

//         world.end();     
//     } 

//     #[test]
//     #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
//     fun test_execute_proposal_error_caller_is_not_member() {
//         let mut world = start_world();

//         world.scenario().next_tx(HACKER);

//         let Action { value: _ } = world.execute_proposal(string::utf8(b"1")).unpack_action();

//         world.end();     
//     }     

//     #[test]
//     #[expected_failure(abort_code = multisig::EThresholdNotReached)]
//     fun test_execute_proposal_error_thresolh_not_reached() {
//         let mut world = start_world();

//         world.multisig().add_members(vector[ALICE, BOB]);

//         world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
//         world.multisig().set_threshold(3);
//         assert_eq(world.multisig().proposals_length(), 1);

//         world.approve_proposal(string::utf8(b"1"));
//         world.scenario().next_tx(ALICE);

//         world.approve_proposal(string::utf8(b"1"));

//         world.clock().set_for_testing(101);

//         let Action { value: _ } = world.execute_proposal(string::utf8(b"1")).unpack_action();

//         world.end();     
//     }

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