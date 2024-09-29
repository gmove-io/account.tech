#[test_only]
module account_actions::upgrade_policies_tests;

use sui::package;
use account_actions::{
    upgrade_policies,
    actions_test_utils::start_world
};

const OWNER: address = @0xBABE;

public struct Rule has store {
    value: u64
}

#[test]
fun test_upgrade_end_to_end() {
    let mut world = start_world();
    let key = b"upgrade proposal".to_string();
    let name = b"lock".to_string();
    let rule_key = b"rule_key";

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    
    let mut upgrade_lock = upgrade_policies::new_lock(upgrade_cap, world.scenario().ctx());
    upgrade_lock.add_rule(rule_key, Rule { value: 7 });
    assert!(upgrade_lock.has_rule(rule_key));
    world.lock_cap(upgrade_lock, name);

    world.scenario().next_tx(OWNER);
    let digest = vector[0, 1, 0, 1];
    
    world.propose_upgrade(key, name, digest);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let ticket = upgrade_policies::execute_upgrade(&mut executable, world.account());
    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(executable, world.account(), receipt);

    package_id.delete();
    world.end();
}    

#[test]
fun test_restrict_end_to_end() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();
    let name = b"lock".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(name, 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    world.propose_restrict(key, name, package::additive_policy());
    let proposal = world.account().proposal(key);
    assert!(proposal.execution_time() == 108);
    world.clock().increment_for_testing(109);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.account());

    package_id.delete();
    world.end();
}  

#[test, expected_failure(abort_code = upgrade_policies::EPolicyShouldRestrict)]
fun test_restrict_error_policy_should_restrict() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();
    let name = b"lock".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(name, 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    world.propose_restrict(key, name, package::compatible_policy());
    let proposal = world.account().proposal(key);
    assert!(proposal.execution_time() == 108);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.account());

    package_id.delete();
    world.end();
}  

#[test, expected_failure(abort_code = upgrade_policies::EInvalidPolicy)]
fun test_restrict_error_invalid_policy() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();
    let name = b"lock".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(name, 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    world.propose_restrict(key, name, 7);
    let proposal = world.account().proposal(key);
    assert!(proposal.execution_time() == 108);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.account());

    package_id.delete();
    world.end();
}   