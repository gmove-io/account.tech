#[test_only]
module kraken::owned_tests{    
    use std::string::utf8;
    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::{receiving_ticket_by_id};

    use kraken::owned;
    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;

    public struct Object has key, store { id: UID }

    public struct Witness has drop, copy {}

    #[test]
    fun test_withdraw_end_to_end() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"withdraw test"));
        
        owned::new_withdraw(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.withdraw<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {}, 0);

        owned::destroy_withdraw(&mut executable, Witness {});
        executable.destroy(Witness {});

        assert_eq(object1.id.to_inner(), id1);

        destroy(object1);
        world.end();
    }

    #[test]
    fun test_borrow_end_to_end() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"borrow test"));
        owned::new_borrow(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {}, 0);

        assert_eq(object::id(&object1), id1);

        world.put_back<Object, Witness>(&mut executable, object1, Witness {}, 1);

        owned::destroy_borrow(&mut executable, Witness {});

        executable.destroy(Witness {});

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = owned::EWrongObject)]
    fun test_withdraw_error_wrong_object() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let key = utf8(b"owned tests");
        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, key, 5, 2, utf8(b"withdraw test"));
        owned::new_withdraw(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.withdraw<Object, Witness>(&mut executable, receiving_ticket_by_id(id2), Witness {}, 0);

        owned::destroy_withdraw(&mut executable, Witness {});
        executable.destroy(Witness {});
        
        destroy(object1);
        world.end();        
    }

    #[test]
    #[expected_failure(abort_code = owned::ERetrieveAllObjectsBefore)]
    fun test_withdraw_error_retrieve_all_objects_before() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"withdraw test"));
        owned::new_withdraw(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        owned::destroy_withdraw(&mut executable, Witness {});
        executable.destroy(Witness {});

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = owned::EWrongObject)]
    fun test_put_back_error_wrong_object() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"borrow test"));
        owned::new_borrow(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {}, 0);

        assert_eq(object::id(&object1), id1);

        world.put_back<Object, Witness>(&mut executable, object2, Witness {}, 1);
        world.put_back<Object, Witness>(&mut executable, object1, Witness {}, 1);

        owned::destroy_borrow(&mut executable, Witness {});

        executable.destroy(Witness {});

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = owned::EReturnAllObjectsBefore)]
    fun test_complete_borrow_error_return_all_objects_before() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"borrow test"));
        owned::new_borrow(proposal, vector[id1]);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {}, 0);

        owned::destroy_borrow(&mut executable, Witness {});

        executable.destroy(Witness {});

        destroy(object1);
        world.end();
    }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}

