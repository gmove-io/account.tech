#[test_only]
module kraken::upgrade_policies_tests {
    use std::debug::print;
    use std::string::utf8;

    use sui::package;

    use sui::test_utils::destroy;
    use sui::test_scenario::receiving_ticket_by_id;

    use kraken::test_utils::start_world;
    use kraken::upgrade_policies::{Self, Upgrade, UpgradeLock};

    const OWNER: address = @0xBABE;

    #[test]
    fun test_upgrade_end_to_end() {
        let mut world = start_world();

        let package_id = object::new(world.scenario().ctx());

        let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());

        let lock_id = world.lock_cap(utf8(b"upgrade_cap 1"), 50, upgrade_cap);

        world.scenario().next_tx(OWNER);

        upgrade_policies::receive_send(world.multisig(), receiving_ticket_by_id(lock_id));

        world.scenario().next_tx(OWNER);

        upgrade_policies::receive_send(world.multisig(), receiving_ticket_by_id(lock_id));

        // print(&lock_id);


        // let digest = vector[0, 1, 0, 1];

        // world.propose_upgrade(utf8(b"1"), 100, utf8(b"fix a bug"), digest, receiving_ticket_by_id(lock_id));

        // // world.scenario().next_tx(OWNER);
        // // world.clock().set_for_testing(151);
        
        // world.approve_proposal(utf8(b"1"));

        // let mut action = world.execute_proposal<Upgrade>(utf8(b"1")); 

        // let receiving = receiving_ticket_by_id<UpgradeLock>(lock_id);

        // print(&receiving);

        // let upgrade_ticket = upgrade_policies::execute_upgrade(
        //     action, 
        //     world.multisig(), 
        //     receiving
        // );        

        // upgrade_policies::complete_upgrade(
        //     world.multisig(), 
        //     receiving_ticket_by_id(lock_id), 
        //     upgrade_ticket.test_upgrade()
        // );  

        destroy(package_id);        

        world.end();
    }    
}