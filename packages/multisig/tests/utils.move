#[test_only]
module kraken_multisig::test_utils;

use std::string::String;
use sui::{
    bag::Bag,
    test_utils::destroy,
    transfer::Receiving,
    clock::{Self, Clock},
    coin::Coin,
    test_scenario::{Self as ts, Scenario, most_recent_id_for_address},
};
use kraken_multisig::{
    coin_operations,
    account::{Self, Account, Invite},
    multisig::{Self, Multisig, Proposal, Executable},
};

const OWNER: address = @0xBABE;

// hot potato holding the state
public struct World {
    scenario: Scenario,
    clock: Clock,
    account: Account,
    multisig: Multisig,
}

// === Utils ===

public fun start_world(): World {
    let mut scenario = ts::begin(OWNER);
    account::new(b"sam".to_string(), b"move_god.png".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let account = scenario.take_from_sender<Account>();
    // initialize Clock, Multisig and Kiosk
    let clock = clock::create_for_testing(scenario.ctx());
    let multisig = multisig::new(b"kraken".to_string(), object::id(&account), scenario.ctx());

    scenario.next_tx(OWNER);

    World { scenario, clock, account, multisig }
}

public fun end(world: World) {
    let World { 
        scenario, 
        clock, 
        multisig, 
        account, 
    } = world;

    destroy(clock);
    destroy(account);
    destroy(multisig);
    scenario.end();
}

public fun multisig(world: &mut World): &mut Multisig {
    &mut world.multisig
}

public fun clock(world: &mut World): &mut Clock {
    &mut world.clock
}

public fun scenario(world: &mut World): &mut Scenario {
    &mut world.scenario
}

public fun last_id_for_multisig<T: key>(world: &World): ID {
    most_recent_id_for_address<T>(world.multisig.addr()).extract()
}

public fun role(module_name: vector<u8>): String {
    let mut role = @kraken_multisig.to_string();
    role.append_utf8(b"::");
    role.append_utf8(module_name);
    role.append_utf8(b"::Auth");
    role
}

// === Multisig ===

public fun new_multisig(world: &mut World): Multisig {
    multisig::new(b"kraken2".to_string(), object::id(&world.account), world.scenario.ctx())
}

public fun create_proposal<I: drop>(
    world: &mut World, 
    auth_issuer: I,
    auth_name: String,
    key: String, 
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
): &mut Proposal {
    world.multisig.create_proposal(
        auth_issuer, 
        auth_name,
        key,
        description, 
        execution_time, 
        expiration_epoch, 
        world.scenario.ctx()
    )
}

public fun approve_proposal(
    world: &mut World, 
    key: String, 
) {
    world.multisig.approve_proposal(key, world.scenario.ctx());
}

public fun remove_approval(
    world: &mut World, 
    key: String, 
) {
    world.multisig.remove_approval(key, world.scenario.ctx());
}

public fun delete_proposal(
    world: &mut World, 
    key: String
): Bag {
    world.multisig.delete_proposal(key, world.scenario.ctx())
}

public fun execute_proposal(
    world: &mut World, 
    key: String, 
): Executable {
    world.multisig.execute_proposal(key, &world.clock, world.scenario.ctx())
}

public fun register_account_id(
    world: &mut World, 
    id: ID,
) {
    world.multisig.register_account_id(id, world.scenario.ctx());
}     

public fun unregister_account_id(
    world: &mut World, 
) {
    world.multisig.unregister_account_id(world.scenario.ctx());
}  

public fun assert_is_member(
    world: &mut World, 
) {
    multisig::assert_is_member(&world.multisig, world.scenario.ctx());
}

// === Coin Operations ===

public fun merge_and_split<T: drop>(
    world: &mut World, 
    to_merge: vector<Receiving<Coin<T>>>,
    to_split: vector<u64> 
): vector<ID> {
    coin_operations::merge_and_split(&mut world.multisig, to_merge, to_split, world.scenario.ctx())
}

// === Account ===

public fun join_multisig(
    world: &mut World, 
    account: &mut Account
) {
    account::join_multisig(account, &mut world.multisig, world.scenario.ctx());
}

public fun leave_multisig(
    world: &mut World, 
    account: &mut Account
) {
    account::leave_multisig(account, &mut world.multisig, world.scenario.ctx());
}

public fun send_invite(
    world: &mut World, 
    recipient: address
) {
    account::send_invite(&world.multisig, recipient, world.scenario.ctx());
}    

public fun accept_invite(
    world: &mut World, 
    account: &mut Account,
    invite: Invite
) {
    account::accept_invite(account, &mut world.multisig, invite, world.scenario.ctx());
} 