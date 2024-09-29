#[test_only]
module account_actions::owned_tests;

use sui::{
    test_utils::destroy,
    test_scenario::receiving_ticket_by_id
};
use account_actions::{
    owned,
    actions_test_utils::start_world
};

const OWNER: address = @0xBABE;

public struct Object has key, store { id: UID }

public struct Witness has drop, copy {}

#[test]
fun test_withdraw_end_to_end() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.withdraw<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {});
    owned::destroy_withdraw(&mut executable, Witness {});
    executable.destroy(Witness {});
    assert!(object1.id.to_inner() == id1);

    destroy(object1);
    world.end();
}

#[test]
fun test_borrow_end_to_end() {
    let mut world = start_world();

    let key = b"owned tests".to_string();
    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {});
    assert!(object::id(&object1) == id1);
    world.put_back<Object, Witness>(&mut executable, object1, Witness {});

    owned::destroy_borrow(&mut executable, Witness {});
    executable.destroy(Witness {});
    world.end();
}

#[test, expected_failure(abort_code = owned::EWrongObject)]
fun test_withdraw_error_wrong_object() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let id2 = object::id(&object2);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);
    transfer::public_transfer(object2, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.withdraw<Object, Witness>(&mut executable, receiving_ticket_by_id(id2), Witness {});
    owned::destroy_withdraw(&mut executable, Witness {});
    executable.destroy(Witness {});
    
    destroy(object1);
    world.end();        
}

#[test, expected_failure(abort_code = owned::ERetrieveAllObjectsBefore)]
fun test_withdraw_error_retrieve_all_objects_before() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    owned::destroy_withdraw(&mut executable, Witness {});
    executable.destroy(Witness {});

    world.end();
}

#[test, expected_failure(abort_code = owned::EWrongObject)]
fun test_put_back_error_wrong_object() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {});
    assert!(object::id(&object1) == id1);
    world.put_back<Object, Witness>(&mut executable, object2, Witness {});
    world.put_back<Object, Witness>(&mut executable, object1, Witness {});

    owned::destroy_borrow(&mut executable, Witness {});
    executable.destroy(Witness {});
    world.end();
}

#[test, expected_failure(abort_code = owned::EReturnAllObjectsBefore)]
fun test_complete_borrow_error_return_all_objects_before() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let account_address = world.account().addr();
    transfer::public_transfer(object1, account_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Witness {}, b"".to_string(), key, b"".to_string(), 0, 0);
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Witness>(&mut executable, receiving_ticket_by_id(id1), Witness {});
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

