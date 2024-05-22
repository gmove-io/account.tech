#[test_only]
module kraken::owned_tests{
    use std::string;
    
    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::{receiving_ticket_by_id, take_from_address_by_id};

    use kraken::owned::{Self, Borrow};
    use kraken::test_utils::start_world;
    use kraken::multisig::{Self, Multisig};

    const OWNER: address = @0xBABE;

    public struct Object has key, store { id: UID }

    #[test]
    fun test_borrow_end_to_end() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_borrow(string::utf8(b"1"), 100, 2, string::utf8(b"test-1"), vector[id1, id2]);

        world.approve_proposal(string::utf8(b"1"));

        // Advance time and epoch
        world.clock().set_for_testing(101);
        world.scenario().next_tx(OWNER);
        world.scenario().next_tx(OWNER);
        world.scenario().next_tx(OWNER);

        let mut borrow = world.execute_proposal<Borrow>(string::utf8(b"1"));

        let object2 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id2));
        let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        borrow.put_back(world.multisig(), object1);
        borrow.put_back(world.multisig(), object2);

        world.scenario().next_tx(OWNER);

        let object1 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id1);
        let object2 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id2);

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        borrow.complete_borrow();
        
        destroy(object1);
        destroy(object2);
        world.end();
    }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}

