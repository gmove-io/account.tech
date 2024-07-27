#[test_only]
module kraken::owned_tests;

use sui::{
    test_utils::destroy,
    test_scenario::receiving_ticket_by_id
};
use kraken::{
    owned,
    test_utils::start_world
};

const OWNER: address = @0xBABE;

public struct Object has key, store { id: UID }

public struct Auth has drop, copy {}

#[test]
fun withdraw_end_to_end() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.withdraw<Object, Auth>(&mut executable, receiving_ticket_by_id(id1), Auth {}, 0);
    owned::destroy_withdraw(&mut executable, Auth {});
    executable.destroy(Auth {});
    assert!(object1.id.to_inner() == id1);

    destroy(object1);
    world.end();
}

#[test]
fun borrow_end_to_end() {
    let mut world = start_world();

    let key = b"owned tests".to_string();
    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Auth>(&mut executable, receiving_ticket_by_id(id1), Auth {}, 0);
    assert!(object::id(&object1) == id1);
    world.put_back<Object, Auth>(&mut executable, object1, Auth {}, 1);

    owned::destroy_borrow(&mut executable, Auth {});
    executable.destroy(Auth {});
    world.end();
}

#[test, expected_failure(abort_code = owned::EWrongObject)]
fun withdraw_error_wrong_object() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let id2 = object::id(&object2);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);
    transfer::public_transfer(object2, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.withdraw<Object, Auth>(&mut executable, receiving_ticket_by_id(id2), Auth {}, 0);
    owned::destroy_withdraw(&mut executable, Auth {});
    executable.destroy(Auth {});
    
    destroy(object1);
    world.end();        
}

#[test, expected_failure(abort_code = owned::ERetrieveAllObjectsBefore)]
fun withdraw_error_retrieve_all_objects_before() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_withdraw(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    owned::destroy_withdraw(&mut executable, Auth {});
    executable.destroy(Auth {});

    world.end();
}

#[test, expected_failure(abort_code = owned::EWrongObject)]
fun put_back_error_wrong_object() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let object2 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Auth>(&mut executable, receiving_ticket_by_id(id1), Auth {}, 0);
    assert!(object::id(&object1) == id1);
    world.put_back<Object, Auth>(&mut executable, object2, Auth {}, 1);
    world.put_back<Object, Auth>(&mut executable, object1, Auth {}, 1);

    owned::destroy_borrow(&mut executable, Auth {});
    executable.destroy(Auth {});
    world.end();
}

#[test, expected_failure(abort_code = owned::EReturnAllObjectsBefore)]
fun complete_borrow_error_return_all_objects_before() {
    let mut world = start_world();
    let key = b"owned tests".to_string();

    let object1 = new_object(world.scenario().ctx());
    let id1 = object::id(&object1);
    let multisig_address = world.multisig().addr();
    transfer::public_transfer(object1, multisig_address);

    world.scenario().next_tx(OWNER);
    let proposal = world.create_proposal(Auth {}, key, 0, 0, b"".to_string());
    owned::new_borrow(proposal, vector[id1]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    let object1 = world.borrow<Object, Auth>(&mut executable, receiving_ticket_by_id(id1), Auth {}, 0);
    owned::destroy_borrow(&mut executable, Auth {});

    executable.destroy(Auth {});
    destroy(object1);
    world.end();
}

fun new_object(ctx: &mut TxContext): Object {
    Object {
        id: object::new(ctx)
    }
}

