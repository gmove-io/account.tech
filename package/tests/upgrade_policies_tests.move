#[test_only]
module kraken::upgrade_policies_tests {
    use std::string::utf8;

    use sui::package;

    use sui::test_utils::assert_eq;
    use sui::test_scenario::{receiving_ticket_by_id};

    use kraken::{
        upgrade_policies::{Self, UpgradeLock},
        test_utils::start_world
    };

    const OWNER: address = @0xBABE;

    public struct Rule has store {
        value: u64
    }

    #[test]
    fun test_upgrade_end_to_end() {
        let mut world = start_world();

        let rule_key = b"rule_key";
        let package_id = object::new(world.scenario().ctx());

        let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   

        let mut upgrade_lock = world.lock_cap(utf8(b"lock"), upgrade_cap);

        let lock_id = object::id(&upgrade_lock);

        upgrade_lock.add_rule(rule_key, Rule { value: 7 });

        assert_eq(upgrade_lock.has_rule(rule_key), true);

        upgrade_lock.put_back_cap();

        world.scenario().next_tx(OWNER);

        let digest = vector[0, 1, 0, 1];

        let mut lock = world.borrow_upgrade_cap_lock(receiving_ticket_by_id(lock_id));

        world.propose_upgrade(utf8(b"key"), 0, utf8(b"description"), digest, &lock);

        world.approve_proposal(utf8(b"key"));

        let executable = world.execute_proposal(utf8(b"key"));

        let ticket = upgrade_policies::execute_upgrade(executable, &mut lock);

        let receipt = ticket.test_upgrade();

        upgrade_policies::confirm_upgrade(&mut lock, receipt);

        lock.put_back_cap();

        package_id.delete();
        world.end();
    }    

    #[test]
    fun test_restrict_end_to_end() {
        let mut world = start_world();

        let package_id = object::new(world.scenario().ctx());

        let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   

        world.lock_cap_with_timelock(utf8(b"lock"), 108, upgrade_cap);

        world.scenario().next_tx(OWNER);

        let lock_id = world.last_id_for_multisig<UpgradeLock>();

        let lock = world.borrow_upgrade_cap_lock(receiving_ticket_by_id(lock_id));

        world.propose_restrict(utf8(b"key"), 0, utf8(b"description"), package::additive_policy(), &lock);

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.execution_time(), 108);

        world.approve_proposal(utf8(b"key"));

        world.scenario().next_tx(OWNER);
        world.clock().increment_for_testing(109);
        
        let executable = world.execute_proposal(utf8(b"key"));

        upgrade_policies::execute_restrict(executable, world.multisig(), lock);

        package_id.delete();
        world.end();
    }  

    #[test]
    #[expected_failure(abort_code = upgrade_policies::EPolicyShouldRestrict)]
    fun test_restrict_error_policy_should_restrict() {
        let mut world = start_world();

        let package_id = object::new(world.scenario().ctx());

        let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   

        world.lock_cap_with_timelock(utf8(b"lock"), 108, upgrade_cap);

        world.scenario().next_tx(OWNER);

        let lock_id = world.last_id_for_multisig<UpgradeLock>();

        let lock = world.borrow_upgrade_cap_lock(receiving_ticket_by_id(lock_id));

        world.propose_restrict(utf8(b"key"), 0, utf8(b"description"), package::compatible_policy(), &lock);

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.execution_time(), 108);

        world.approve_proposal(utf8(b"key"));

        world.scenario().next_tx(OWNER);
        world.clock().increment_for_testing(109);
        
        let executable = world.execute_proposal(utf8(b"key"));

        upgrade_policies::execute_restrict(executable, world.multisig(), lock);

        package_id.delete();
        world.end();
    }  

    #[test]
    #[expected_failure(abort_code = upgrade_policies::EInvalidPolicy)]
    fun test_restrict_error_invalid_policy() {
        let mut world = start_world();

        let package_id = object::new(world.scenario().ctx());

        let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   

        world.lock_cap_with_timelock(utf8(b"lock"), 108, upgrade_cap);

        world.scenario().next_tx(OWNER);

        let lock_id = world.last_id_for_multisig<UpgradeLock>();

        let lock = world.borrow_upgrade_cap_lock(receiving_ticket_by_id(lock_id));

        world.propose_restrict(utf8(b"key"), 0, utf8(b"description"), 7, &lock);

        let proposal = world.multisig().proposal(&utf8(b"key"));

        assert_eq(proposal.execution_time(), 108);

        world.approve_proposal(utf8(b"key"));

        world.scenario().next_tx(OWNER);
        world.clock().increment_for_testing(109);
        
        let executable = world.execute_proposal(utf8(b"key"));

        upgrade_policies::execute_restrict(executable, world.multisig(), lock);

        package_id.delete();
        world.end();
    }   
}