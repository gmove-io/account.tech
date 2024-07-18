#[test_only]
module kraken::config_tests{
    use std::string::utf8;
    use std::debug::print;

    use sui::test_utils::assert_eq;

    use kraken::config;
    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    #[test]
    fun test_name_end_to_end() {
        let mut world = start_world();
        let key = utf8(b"name proposal");

        world.propose_name(
            key,
            1,
            2,
            utf8(b"description"),
            utf8(b"new name"),
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);    
        config::execute_name(executable, world.multisig());

        assert_eq(world.multisig().name(), utf8(b"new name"));
        world.end();     
    }

    #[test]
    #[allow(implicit_const_copy)]
    fun test_modify_end_to_end() {
        let mut world = start_world();

        let sender = world.scenario().ctx().sender();
        let multisig = world.multisig();
        let key = utf8(b"modify proposal");

        assert_eq(multisig.name(), utf8(b"kraken"));
        assert_eq(multisig.threshold(), 1);
        assert_eq(multisig.member_addresses(), vector[sender]);
        assert_eq(multisig.proposals_length(), 0);
        assert_eq(multisig.total_weight(), 1);

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(3),
            vector[ALICE, BOB],
            vector[OWNER],
            vector[ALICE],
            vector[2]
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        let multisig = world.multisig();

        assert_eq(multisig.threshold(), 3);
        assert_eq(multisig.member_addresses(), vector[BOB, ALICE]);
        assert_eq(multisig.total_weight(), 3); 
        assert_eq(multisig.member_weight(&ALICE), 2); 
        assert_eq(multisig.member_weight(&BOB), 1);      

        world.end();        
    }

    #[test]
    #[allow(implicit_const_copy)]
    fun test_roles_end_to_end() {
        let mut world = start_world();

        let sender = world.scenario().ctx().sender();
        let key = utf8(b"roles proposal");

        assert_eq(world.multisig().member_roles(&sender), vector[]);

        // add role 
        let mut role = @kraken.to_string();
        role.append_utf8(b"::config::Witness");
        world.propose_roles(
            key,
            1,
            2,
            utf8(b"description"),
            vector[OWNER],
            vector[vector[role]],
            vector[],
            vector[]
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);
        let executable = world.execute_proposal(key);
        config::execute_roles(executable, world.multisig());
        assert_eq(world.multisig().member_roles(&sender), vector[role]);

        // execute action with role
        world.propose_name(
            key,
            1,
            2,
            utf8(b"description"),
            utf8(b"new name"),
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);    
        config::execute_name(executable, world.multisig());
        assert_eq(world.multisig().name(), utf8(b"new name"));

        // remove role 
        let mut role = @kraken.to_string();
        role.append_utf8(b"::config::Witness");
        world.propose_roles(
            key,
            1,
            2,
            utf8(b"description"),
            vector[],
            vector[],
            vector[OWNER],
            vector[vector[role]],
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);
        let executable = world.execute_proposal(key);
        config::execute_roles(executable, world.multisig());
        assert_eq(world.multisig().member_roles(&sender), vector[]);

        world.end();        
    }

    #[test]
    fun test_migrate_end_to_end() {
        let mut world = start_world();

        let key = utf8(b"migrate proposal");

        assert_eq(world.multisig().version(), 1);

        world.propose_migrate(
            key,
            1,
            2,
            utf8(b"description"),
            2
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);    

        config::execute_migrate(executable, world.multisig());

        assert_eq(world.multisig().version(), 2);

        world.end();     
    }
    
    #[test]
    #[expected_failure(abort_code = config::EAlreadyMember)]
    fun test_verify_new_config_error_added_already_member() {
        let mut world = start_world();
        let key = utf8(b"modify proposal");

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(2),
            vector[OWNER],
            vector[],
            vector[],
            vector[],
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        world.end();         
    }   

    #[test]
    #[expected_failure(abort_code = config::ENotMember)]
    fun test_verify_new_config_error_removed_not_member() {
        let mut world = start_world();
        let key = utf8(b"modify proposal");

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(2),
            vector[],
            vector[ALICE],
            vector[],
            vector[]
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        world.end();         
    }

    #[test]
    #[expected_failure(abort_code = config::ENotMember)]
    fun test_verify_new_config_error_modified_not_member() {
        let mut world = start_world();
        let key = utf8(b"modify proposal");

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(2),
            vector[],
            vector[],
            vector[ALICE],
            vector[2]
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        world.end();         
    }

    #[test]
    #[expected_failure(abort_code = config::EThresholdTooHigh)]
    fun test_verify_new_config_error_threshold_too_high() {
        let mut world = start_world();
        let key = utf8(b"modify proposal");

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(4),
            vector[ALICE, BOB],
            vector[OWNER],
            vector[ALICE],
            vector[2]
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        world.end();         
    }

    #[test]
    #[expected_failure(abort_code = config::EThresholdNull)]
    fun test_verify_new_config_error_threshold_null() {
        let mut world = start_world();
        let key = utf8(b"modify proposal");

        world.propose_modify_rules(
            key,
            1,
            2,
            utf8(b"description"),
            option::some(0),
            vector[],
            vector[],
            vector[],
            vector[],
        );

        world.approve_proposal(key);

        world.scenario().next_tx(OWNER);
        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(2);

        let executable = world.execute_proposal(key);

        config::execute_modify_rules(executable, world.multisig());

        world.end();         
    }  
}