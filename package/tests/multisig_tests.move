#[test_only]
module kraken::multisig_tests {
    use std::string;

    use sui::test_utils::assert_eq;
    
    use kraken::multisig;
    use kraken::test_utils::start_world;

    public struct Action has store { value: u64 }

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xa11e7;
    const BOB: address = @0x10;
    const HACKER: address = @0x7ac1e7;

    #[test]
    fun test_new() {
        let mut world = start_world();

        let sender = world.scenario().ctx().sender();
        let multisig = world.multisig();

        assert_eq(multisig.name(), string::utf8(b"kraken"));
        assert_eq(multisig.threshold(), 1);
        assert_eq(multisig.members(), vector[sender]);
        assert_eq(multisig.num_of_proposals(), 0);

        world.end();
    } 

    #[test]
    fun test_clean_proposals() {
        let mut world = start_world();

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        world.create_proposal(Action { value: 2 }, string::utf8(b"2"), 100, 2, string::utf8(b"test-2"));
        world.create_proposal(Action { value: 3 }, string::utf8(b"3"), 100, 3, string::utf8(b"test-3"));

        assert_eq(world.multisig().num_of_proposals(), 3);

        // does nothing
        world.clean_proposals();
        assert_eq(world.multisig().num_of_proposals(), 3);

        // increment epoch
        world.scenario().ctx().increment_epoch_number();
        world.scenario().ctx().increment_epoch_number();

        // Remove 2 proposals
        world.clean_proposals();
        assert_eq(world.multisig().num_of_proposals(), 1);

        world.scenario().ctx().increment_epoch_number();

        // remove the last proposal
        world.clean_proposals();
        assert_eq(world.multisig().num_of_proposals(), 0);

        world.end();
    }

    #[test]
    fun test_create_proposal() {
        let mut world = start_world();

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        world.create_proposal(Action { value: 1 }, string::utf8(b"2"), 101, 3, string::utf8(b"test-2"));

        assert_eq(world.multisig().num_of_proposals(), 2);

        let proposal1 = world.multisig().proposal(&string::utf8(b"1"));
        
        assert_eq(proposal1.description(), string::utf8(b"test-1"));
        assert_eq(proposal1.expiration_epoch(), 2);
        assert_eq(proposal1.execution_time(), 100);
        assert_eq(proposal1.approved(), vector[]);

        let proposal2 = world.multisig().proposal(&string::utf8(b"2"));

        assert_eq(proposal2.description(), string::utf8(b"test-2"));
        assert_eq(proposal2.expiration_epoch(), 3);
        assert_eq(proposal2.execution_time(), 101);
        assert_eq(proposal2.approved(), vector[]);

        world.end();
    }

    #[test]
    fun test_delete_proposal() {
        let mut world = start_world();

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        assert_eq(world.multisig().num_of_proposals(), 1);

        world.delete_proposal(string::utf8(b"1"));
        assert_eq(world.multisig().num_of_proposals(), 0);

        world.end();
    }

    #[test]
    fun test_approve_proposal() {
        let mut world = start_world();

        world.multisig().add_members(vector[ALICE, BOB]);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[]);

        world.approve_proposal(string::utf8(b"1"));

        world.scenario().next_tx(ALICE);

        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER]);  

        world.approve_proposal(string::utf8(b"1"));    

        world.scenario().next_tx(BOB); 

        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER, ALICE]);  

        world.approve_proposal(string::utf8(b"1"));

        world.scenario().next_tx(BOB); 

        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER, ALICE, BOB]);          

        world.end();
    }

    #[test]
    fun test_remove_approval() {
        let mut world = start_world();

        world.multisig().add_members(vector[ALICE, BOB]);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

        world.approve_proposal(string::utf8(b"1"));
        world.scenario().next_tx(ALICE);

        world.approve_proposal(string::utf8(b"1"));
        world.scenario().next_tx(BOB);

        world.approve_proposal(string::utf8(b"1"));

        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER, ALICE, BOB]);

        world.remove_approval(string::utf8(b"1"));      
        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER, ALICE]);

        world.scenario().next_tx(ALICE);
         world.remove_approval(string::utf8(b"1")); 
        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[OWNER]);

        world.scenario().next_tx(OWNER);
        world.remove_approval(string::utf8(b"1")); 
        let proposal = world.multisig().proposal(&string::utf8(b"1"));
        assert_eq(proposal.approved(), vector[]);

        world.end();        
    }

    #[test]
    fun test_execute_proposal() {
        let mut world = start_world();

        world.multisig().add_members(vector[ALICE, BOB]);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        world.multisig().set_threshold(2);
        assert_eq(world.multisig().num_of_proposals(), 1);

        world.approve_proposal(string::utf8(b"1"));
        world.scenario().next_tx(ALICE);

        world.approve_proposal(string::utf8(b"1"));

        world.clock().set_for_testing(101);

        let Action { value } = world.execute_proposal(string::utf8(b"1"));
        assert_eq(world.multisig().num_of_proposals(), 0);

        assert_eq(value, 1);

        world.end();        
    }

    #[test]
    fun test_set_functions() {
        let mut world = start_world();

        assert_eq(world.multisig().name(), string::utf8(b"kraken"));

        world.multisig().set_name(string::utf8(b"kraken-2"));
        assert_eq(world.multisig().name(), string::utf8(b"kraken-2"));

        assert_eq(world.multisig().threshold(), 1);
        world.multisig().set_threshold(11);
        assert_eq(world.multisig().threshold(), 11);

        let sender = world.scenario().ctx().sender();
        assert_eq(world.multisig().members(), vector[sender]);

        world.multisig().add_members(vector[ALICE]);
        assert_eq(world.multisig().members(), vector[sender, ALICE]);

        world.multisig().remove_members(vector[ALICE]);
        assert_eq(world.multisig().members(), vector[sender]);

        world.end();
    }    

    #[test]
    #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
    fun test_create_proposal_error_caller_is_not_member() {
        let mut world = start_world();

        world.scenario().next_tx(HACKER);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

        world.end();        
    }

    #[test]
    #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
    fun test_delete_proposal_error_caller_is_not_member() {
        let mut world = start_world();

        world.scenario().next_tx(HACKER);

        world.delete_proposal(string::utf8(b"1"));

        world.end();        
    } 

    #[test]
    #[expected_failure(abort_code = multisig::EProposalNotEmpty)]
    fun test_delete_proposal_error_proposal_not_empty() {
        let mut world = start_world();

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

        world.approve_proposal(string::utf8(b"1"));

        world.delete_proposal(string::utf8(b"1"));

        world.end();        
    }           

    #[test]
    #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
    fun test_approve_proposal_error_caller_is_not_member() {
        let mut world = start_world();

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));

        world.scenario().next_tx(HACKER);

        world.approve_proposal(string::utf8(b"1"));

        world.end();     
    } 

    #[test]
    #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
    fun test_remove_approval_error_caller_is_not_member() {
        let mut world = start_world();

        world.scenario().next_tx(HACKER);

        world.remove_approval(string::utf8(b"1"));

        world.end();     
    } 

    #[test]
    #[expected_failure(abort_code = multisig::ECallerIsNotMember)]
    fun test_execute_proposal_error_caller_is_not_member() {
        let mut world = start_world();

        world.scenario().next_tx(HACKER);

        let Action { value: _ } = world.execute_proposal(string::utf8(b"1"));

        world.end();     
    }     

    #[test]
    #[expected_failure(abort_code = multisig::EThresholdNotReached)]
    fun test_execute_proposal_error_thresolh_not_reached() {
        let mut world = start_world();

        world.multisig().add_members(vector[ALICE, BOB]);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        world.multisig().set_threshold(3);
        assert_eq(world.multisig().num_of_proposals(), 1);

        world.approve_proposal(string::utf8(b"1"));
        world.scenario().next_tx(ALICE);

        world.approve_proposal(string::utf8(b"1"));

        world.clock().set_for_testing(101);

        let Action { value: _ } = world.execute_proposal(string::utf8(b"1"));

        world.end();     
    }

    #[test]
    #[expected_failure(abort_code = multisig::ECantBeExecutedYet)]
    fun test_execute_proposal_error_cant_be_executed_yet() {
        let mut world = start_world();

        world.multisig().add_members(vector[ALICE, BOB]);

        world.create_proposal(Action { value: 1 }, string::utf8(b"1"), 100, 2, string::utf8(b"test-1"));
        world.multisig().set_threshold(2);
        assert_eq(world.multisig().num_of_proposals(), 1);

        world.approve_proposal(string::utf8(b"1"));
        world.scenario().next_tx(ALICE);

        world.approve_proposal(string::utf8(b"1"));

        world.clock().set_for_testing(99);

        let Action { value: _ } = world.execute_proposal(string::utf8(b"1"));

        world.end();     
    }           
}