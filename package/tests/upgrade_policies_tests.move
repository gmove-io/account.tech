#[test_only]
module kraken::upgrade_policies_tests {
    use std::string::utf8;

    use sui::package;

    use sui::test_utils::{destroy, assert_eq};
    use sui::test_scenario::{receiving_ticket_by_id, take_from_address_by_id, return_to_address};

    use kraken::test_utils::start_world;
    use kraken::upgrade_policies::{Self, UpgradeLock};

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

    // !IMPORTANT There is a bug on receiving_ticket_by_id. So the test below fails!
    // #[test]
    // fun test_new_policy_end_to_end() {
    //     let mut world = start_world();

    //     let package_id = object::new(world.scenario().ctx());

    //     let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());

    //     let lock_id = world.lock_cap(utf8(b"upgrade_cap 1"), 50, upgrade_cap);

    //     world.scenario().next_tx(OWNER);

    //     world.propose_policy(utf8(b"1"), 100, 2, utf8(b"make additive"), 128, receiving_ticket_by_id(lock_id));

    //     world.clock().set_for_testing(151);
    //     world.scenario().next_epoch(OWNER);
    //     world.scenario().next_epoch(OWNER);
    //     world.scenario().next_tx(OWNER);

    //     world.approve_proposal(utf8(b"1"));

    //     world.scenario().next_tx(OWNER);

    //     let action = world.execute_proposal<Policy>(utf8(b"1")); 

    //     upgrade_policies::execute_policy(
    //         action, 
    //         world.multisig(), 
    //         receiving_ticket_by_id(lock_id)
    //     );  

    //     world.scenario().next_tx(OWNER);   

    //     let multisig_address = world.multisig().addr(); 

    //     let lock = take_from_address_by_id<UpgradeLock>(world.scenario(), multisig_address, lock_id);  

    //     assert_eq(lock.upgrade_cap().policy(), package::additive_policy()); 

    //     destroy(lock);
    //     destroy(package_id);        
    //     world.end();
    // }     
}