#[test_only]
module kraken_multisig::multisig_test_utils;

use std::string::String;
use sui::{
    test_utils::destroy,
    transfer::Receiving,
    clock::{Self, Clock},
    coin::Coin,
    test_scenario::{Self as ts, Scenario, most_recent_id_for_address},
};
use kraken_multisig::{
    coin_operations,
    account::{Self, Account, Invite},
    multisig::{Self, Multisig},
    proposals::Proposal,
    executable::Executable,
};
use kraken_extensions::extensions::{Self, Extensions, AdminCap};

const OWNER: address = @0xBABE;

// hot potato holding the state
public struct World {
    scenario: Scenario,
    clock: Clock,
    account: Account,
    multisig: Multisig,
    extensions: Extensions
}

// === Utils ===

public fun start_world(): World {
    let mut scenario = ts::begin(OWNER);
    extensions::init_for_testing(scenario.ctx());
    account::init_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let account = account::new(b"sam".to_string(), b"move_god.png".to_string(), scenario.ctx());
    let cap = scenario.take_from_sender<AdminCap>();
    let mut extensions = scenario.take_shared<Extensions>();
    // initialize Clock, Multisig, Extensions
    let clock = clock::create_for_testing(scenario.ctx());
    extensions.add(&cap, b"KrakenMultisig".to_string(), @kraken_multisig, 1);
    extensions.add(&cap, b"KrakenActions".to_string(), @0xCAFE, 1);
    let multisig = multisig::new(
        &extensions,
        b"kraken".to_string(), 
        object::id(&account), 
        scenario.ctx()
    );

    scenario.next_tx(OWNER);
    destroy(cap);

    World { scenario, clock, account, multisig, extensions }
}

public fun end(world: World) {
    let World { 
        scenario, 
        clock, 
        multisig, 
        account, 
        extensions
    } = world;

    destroy(clock);
    destroy(account);
    destroy(multisig);
    destroy(extensions);
    scenario.end();
}

public fun multisig(world: &mut World): &mut Multisig {
    &mut world.multisig
}

public fun account(world: &mut World): &mut Account {
    &mut world.account
}

public fun extensions(world: &mut World): &mut Extensions {
    &mut world.extensions
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
    multisig::new(
        &world.extensions,
        b"kraken2".to_string(), 
        object::id(&world.account), 
        world.scenario.ctx()
    )
}

public fun create_proposal<I: drop>(
    world: &mut World, 
    auth_witness: I,
    auth_name: String,
    key: String, 
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
): &mut Proposal {
    world.multisig.create_proposal(
        auth_witness, 
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

// TODO:
// public fun delete_proposal(
//     world: &mut World, 
//     key: String
// ): Bag {
//     world.multisig.proposal(key).delete(world.scenario.ctx())
// }

public fun execute_proposal(
    world: &mut World, 
    key: String, 
): Executable {
    world.multisig.execute_proposal(key, &world.clock)
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