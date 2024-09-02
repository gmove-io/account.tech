#[test_only]
module kraken::upgrade_policies_tests;

use sui::{
    package,
    test_scenario::most_recent_receiving_ticket,
};
use kraken::{
    upgrade_policies,
    test_utils::start_world
};

const OWNER: address = @0xBABE;

public struct Rule has store {
    value: u64
}

#[test]
fun upgrade_end_to_end() {
    let mut world = start_world();
    let key = b"upgrade proposal".to_string();

    let rule_key = b"rule_key";
    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    
    let mut upgrade_lock = world.lock_cap(b"lock".to_string(), upgrade_cap);
    upgrade_lock.add_rule(rule_key, Rule { value: 7 });
    assert!(upgrade_lock.has_rule(rule_key));
    upgrade_lock.put_back_lock();

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    let digest = vector[0, 1, 0, 1];
    let mut lock = world.borrow_upgrade_lock(receiving_lock);
    
    world.propose_upgrade(key, digest, &lock);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    let ticket = upgrade_policies::execute_upgrade(executable, world.multisig(), &mut lock);
    let receipt = ticket.test_upgrade();
    upgrade_policies::confirm_upgrade(&mut lock, receipt);
    lock.put_back_lock();

    package_id.delete();
    world.end();
}    

#[test]
fun restrict_end_to_end() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(b"lock".to_string(), 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    let lock = world.borrow_upgrade_lock(receiving_lock);

    world.propose_restrict(key, package::additive_policy(), &lock);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.execution_time() == 108);
    world.clock().increment_for_testing(109);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.multisig(), lock);

    package_id.delete();
    world.end();
}  

#[test, expected_failure(abort_code = upgrade_policies::EPolicyShouldRestrict)]
fun restrict_error_policy_should_restrict() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(b"lock".to_string(), 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    let lock = world.borrow_upgrade_lock(receiving_lock);

    world.propose_restrict(key, package::compatible_policy(), &lock);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.execution_time() == 108);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.multisig(), lock);

    package_id.delete();
    world.end();
}  

#[test, expected_failure(abort_code = upgrade_policies::EInvalidPolicy)]
fun restrict_error_invalid_policy() {
    let mut world = start_world();
    let key = b"restrict proposal".to_string();

    let package_id = object::new(world.scenario().ctx());
    let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());   
    world.lock_cap_with_timelock(b"lock".to_string(), 108, upgrade_cap);

    world.scenario().next_tx(OWNER);
    let receiving_lock = most_recent_receiving_ticket(&world.multisig().addr().to_id());
    let lock = world.borrow_upgrade_lock(receiving_lock);

    world.propose_restrict(key, 7, &lock);
    let proposal = world.multisig().proposal(&key);
    assert!(proposal.execution_time() == 108);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    upgrade_policies::execute_restrict(executable, world.multisig(), lock);

    package_id.delete();
    world.end();
}   