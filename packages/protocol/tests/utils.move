#[test_only]
module account_protocol::account_test_utils;

use std::string::String;
use sui::{
    test_utils::destroy,
    transfer::Receiving,
    clock::{Self, Clock},
    coin::Coin,
    test_scenario::{Self as ts, Scenario, most_recent_id_for_address},
};
use account_protocol::{
    coin_operations,
    user::{Self, User, Invite},
    account::{Self, Account},
    proposals::Proposal,
    executable::Executable,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

const OWNER: address = @0xBABE;

// hot potato holding the state
public struct World {
    scenario: Scenario,
    clock: Clock,
    user: User,
    account: Account,
    extensions: Extensions
}

// === Utils ===

public fun start_world(): World {
    let mut scenario = ts::begin(OWNER);
    extensions::init_for_testing(scenario.ctx());
    user::init_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let user = user::new(b"sam".to_string(), b"move_god.png".to_string(), scenario.ctx());
    let cap = scenario.take_from_sender<AdminCap>();
    let mut extensions = scenario.take_shared<Extensions>();
    // initialize Clock, Account, Extensions
    let clock = clock::create_for_testing(scenario.ctx());
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @0xCAFE, 1);
    let account = account::new(
        &extensions,
        b"kraken".to_string(), 
        object::id(&user), 
        scenario.ctx()
    );

    scenario.next_tx(OWNER);
    destroy(cap);

    World { scenario, clock, user, account, extensions }
}

public fun end(world: World) {
    let World { 
        scenario, 
        clock, 
        account, 
        user, 
        extensions
    } = world;

    destroy(clock);
    destroy(user);
    destroy(account);
    destroy(extensions);
    scenario.end();
}

public fun account(world: &mut World): &mut Account {
    &mut world.account
}

public fun user(world: &mut World): &mut User {
    &mut world.user
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

public fun last_id_for_account<T: key>(world: &World): ID {
    most_recent_id_for_address<T>(world.account.addr()).extract()
}

public fun role(module_name: vector<u8>): String {
    let mut role = @account_protocol.to_string();
    role.append_utf8(b"::");
    role.append_utf8(module_name);
    role.append_utf8(b"::Auth");
    role
}

// === Account ===

public fun new_account(world: &mut World): Account {
    account::new(
        &world.extensions,
        b"kraken2".to_string(), 
        object::id(&world.user), 
        world.scenario.ctx()
    )
}

public fun create_proposal<W: copy + drop>(
    world: &mut World, 
    auth_witness: W,
    auth_name: String,
    key: String, 
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
): Proposal {
    world.account.create_proposal(
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
    world.account.approve_proposal(key, world.scenario.ctx());
}

public fun remove_approval(
    world: &mut World, 
    key: String, 
) {
    world.account.remove_approval(key, world.scenario.ctx());
}

// TODO:
// public fun delete_proposal(
//     world: &mut World, 
//     key: String
// ): Bag {
//     world.account.proposal(key).delete(world.scenario.ctx())
// }

public fun execute_proposal(
    world: &mut World, 
    key: String, 
): Executable {
    world.account.execute_proposal(key, &world.clock)
}

public fun assert_is_member(
    world: &mut World, 
) {
    account::assert_is_member(&world.account, world.scenario.ctx());
}

// === Coin Operations ===

public fun merge_and_split<T: drop>(
    world: &mut World, 
    to_merge: vector<Receiving<Coin<T>>>,
    to_split: vector<u64> 
): vector<ID> {
    coin_operations::merge_and_split(&mut world.account, to_merge, to_split, world.scenario.ctx())
}

// === User ===

public fun join_account(
    world: &mut World, 
    user: &mut User
) {
    user::join_account(user, &mut world.account, world.scenario.ctx());
}

public fun leave_account(
    world: &mut World, 
    user: &mut User
) {
    user::leave_account(user, &mut world.account, world.scenario.ctx());
}

public fun send_invite(
    world: &mut World, 
    recipient: address
) {
    user::send_invite(&world.account, recipient, world.scenario.ctx());
}    

public fun accept_invite(
    world: &mut World,
    user: &mut User,
    invite: Invite
) {
    user::accept_invite(user, &mut world.account, invite, world.scenario.ctx());
} 