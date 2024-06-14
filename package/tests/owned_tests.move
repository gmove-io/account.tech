#[test_only]
module kraken::owned_tests{    
    use std::string::utf8;
    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::{receiving_ticket_by_id, take_from_address_by_id};

    use kraken::owned;
    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;

    public struct Object has key, store { id: UID }

    public struct Witness has drop {}

    #[test]
    fun test_withdraw_end_to_end() {
        let mut world = start_world();

        let key = utf8(b"owned tests");
        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let withdraw = owned::new_withdraw(vector[id1]);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"withdraw test"));
        proposal.push_action(withdraw);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.withdraw<Witness, Object>(&mut executable, Witness {}, receiving_ticket_by_id(id1), 0);

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

        let borrow = owned::new_borrow(vector[id1]);

        let proposal = world.create_proposal(Witness {}, utf8(b"owned tests"), 5, 2, utf8(b"borrow test"));
        proposal.push_action(borrow);

        world.scenario().next_epoch(OWNER);
        world.scenario().next_epoch(OWNER);
        world.clock().increment_for_testing(5);

        world.approve_proposal(key);

        let mut executable = world.execute_proposal(key);

        let object1 = world.borrow<Witness, Object>(&mut executable, Witness {}, receiving_ticket_by_id(id1), 0);

        assert_eq(object::id(&object1), id1);

        world.put_back<Witness, Object>(&mut executable, Witness {}, object1, 0);

        owned::destroy_borrow(&mut executable, Witness {});

        executable.destroy(Witness {});

        world.end();
    }

    // #[test]
    // #[expected_failure(abort_code = owned::EWrongObject)]
    // fun test_withdraw_error_wrong_object() {
    //     let mut world = start_world();

    //     let object1 = new_object(world.scenario().ctx());
    //     let object2 = new_object(world.scenario().ctx());

    //     let id1 = object::id(&object1);
    //     let id2 = object::id(&object2);

    //     let multisig_address = world.multisig().addr();

    //     transfer::public_transfer(object2, multisig_address);

    //     world.scenario().next_tx(OWNER);

    //     let mut borrow = owned::new_borrow(vector[id1]);
        
    //     // Objects must be taken LIFO
    //     let object2 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id2));
        
    //     destroy(object1);
    //     destroy(object2);
    //     destroy(borrow);
    //     world.end();        
    // }

    // #[test]
    // #[expected_failure(abort_code = owned::EWrongObject)]
    // fun test_put_back_error_wrong_object() {
    //     let mut world = start_world();

    //     let object1 = new_object(world.scenario().ctx());
    //     let object2 = new_object(world.scenario().ctx());

    //     let id1 = object::id(&object1);

    //     let multisig_address = world.multisig().addr();

    //     transfer::public_transfer(object1, multisig_address);

    //     world.scenario().next_tx(OWNER);

    //     let mut borrow = owned::new_borrow(vector[id1]);
        
    //     // Objects must be taken LIFO
    //     let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

    //     borrow.put_back(world.multisig(), object1);
    //     borrow.put_back(world.multisig(), object2);

    //     world.scenario().next_tx(OWNER);

    //     borrow.complete_borrow();
        
    //     world.end();
    // }

    // #[test]
    // #[expected_failure(abort_code = owned::ERetrieveAllObjectsBefore)]
    // fun test_complete_borrow_error_retrieve_all_objects_before() {
    //     let mut world = start_world();

    //     let object1 = new_object(world.scenario().ctx());

    //     let id1 = object::id(&object1);

    //     let multisig_address = world.multisig().addr();

    //     transfer::public_transfer(object1, multisig_address);


    //     world.scenario().next_tx(OWNER);

    //     let borrow = owned::new_borrow(vector[id1]);

    //     borrow.complete_borrow();
    //     world.end();
    // }

    // #[test]
    // #[expected_failure(abort_code = owned::EReturnAllObjectsBefore)]
    // fun test_complete_borrow_error_return_all_objects_before() {
    //     let mut world = start_world();

    //     let object1 = new_object(world.scenario().ctx());

    //     let id1 = object::id(&object1);

    //     let multisig_address = world.multisig().addr();

    //     transfer::public_transfer(object1, multisig_address);

    //     world.scenario().next_tx(OWNER);

    //     let mut borrow = owned::new_borrow(vector[id1]);

    //     let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

    //     borrow.complete_borrow();
    //     destroy(object1);
    //     world.end();
    // }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}

