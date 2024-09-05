#[test_only]
module kraken::test_utils;

use std::string::String;
use sui::{
    bag::Bag,
    test_utils::destroy,
    package::UpgradeCap,
    transfer::Receiving,
    clock::{Self, Clock},
    coin::{Coin, TreasuryCap},
    kiosk::{Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
    test_scenario::{Self as ts, Scenario, most_recent_id_for_address},
};
use kraken::{
    owned,
    config,
    coin_operations,
    payments::{Self, Stream},
    currency,
    account::{Self, Account, Invite},
    upgrade_policies::{Self, UpgradeLock},
    transfers::{Self, DeliveryCap, Delivery},
    kiosk as k_kiosk,
    multisig::{Self, Multisig, Proposal, Executable},
};

const OWNER: address = @0xBABE;

// hot potato holding the state
public struct World {
    scenario: Scenario,
    clock: Clock,
    account: Account,
    multisig: Multisig,
    kiosk: Kiosk,
}

// === Utils ===

public fun start_world(): World {
    let mut scenario = ts::begin(OWNER);
    account::new(b"sam".to_string(), b"move_god.png".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let account = scenario.take_from_sender<Account>();
    // initialize Clock, Multisig and Kiosk
    let clock = clock::create_for_testing(scenario.ctx());
    let mut multisig = multisig::new(b"kraken".to_string(), object::id(&account), scenario.ctx());
    k_kiosk::new(&mut multisig, b"kiosk".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();

    World { scenario, clock, account, multisig, kiosk }
}

public fun end(world: World) {
    let World { 
        scenario, 
        clock, 
        multisig, 
        account, 
        kiosk,
        ..
    } = world;

    destroy(clock);
    destroy(kiosk);
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

public fun kiosk(world: &mut World): &mut Kiosk {
    &mut world.kiosk
}

public fun scenario(world: &mut World): &mut Scenario {
    &mut world.scenario
}

public fun last_id_for_multisig<T: key>(world: &World): ID {
    most_recent_id_for_address<T>(world.multisig.addr()).extract()
}

public fun role(module_name: vector<u8>): String {
    let mut role = @kraken.to_string();
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

// === Owned ===

public fun withdraw<O: key + store, I: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    receiving: Receiving<O>,
    issuer: I,
): O {
    owned::withdraw<O, I>(executable, &mut world.multisig, receiving, issuer)
}

public fun borrow<O: key + store, I: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    receiving: Receiving<O>,
    issuer: I,
): O {
    owned::borrow<O, I>(executable, &mut world.multisig, receiving, issuer)
}

public fun put_back<O: key + store, I: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    returned: O,
    issuer: I,
) {
    owned::put_back<O, I>(executable, &world.multisig, returned, issuer);
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

// === Config ===

public fun propose_name(
    world: &mut World,
    key: String,
    name: String
) {
    config::propose_name(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        name, 
        world.scenario.ctx()
    );
}

public fun propose_modify_rules(
    world: &mut World, 
    key: String,
    members_to_add: vector<address>, 
    members_to_remove: vector<address>,
    members_to_modify: vector<address>,
    weights_to_modify: vector<u64>,
    addresses_add_roles: vector<address>,
    roles_to_add: vector<vector<String>>,
    addresses_remove_roles: vector<address>,
    roles_to_remove: vector<vector<String>>,
    roles_for_thresholds: vector<String>, 
    thresholds_to_set: vector<u64>, 
) {
    config::propose_modify_rules(
        &mut world.multisig, 
        key,
        b"".to_string(), 
        0, 
        0, 
        members_to_add,
        members_to_remove,
        members_to_modify,
        weights_to_modify,
        addresses_add_roles,
        roles_to_add,
        addresses_remove_roles,
        roles_to_remove,
        roles_for_thresholds,
        thresholds_to_set,        
        world.scenario.ctx()
    );
}

public fun propose_members(
    world: &mut World, 
    key: String,
    members_to_add: vector<address>, 
    members_to_remove: vector<address>,
) {
    config::propose_modify_rules(
        &mut world.multisig, 
        key,
        b"".to_string(), 
        0, 
        0, 
        members_to_add,
        members_to_remove,
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],        
        world.scenario.ctx()
    );
}

public fun propose_weights(
    world: &mut World, 
    key: String,
    members_to_modify: vector<address>,
    weights_to_modify: vector<u64>,
) {
    config::propose_modify_rules(
        &mut world.multisig, 
        key,
        b"".to_string(), 
        0, 
        0, 
        vector[],
        vector[],
        members_to_modify,
        weights_to_modify,
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],        
        world.scenario.ctx()
    );
}

public fun propose_roles(
    world: &mut World, 
    key: String,
    addresses_add_roles: vector<address>,
    roles_to_add: vector<vector<String>>,
    addresses_remove_roles: vector<address>,
    roles_to_remove: vector<vector<String>>,
) {
    config::propose_modify_rules(
        &mut world.multisig, 
        key,
        b"".to_string(), 
        0, 
        0, 
        vector[],
        vector[],
        vector[],
        vector[],
        addresses_add_roles,
        roles_to_add,
        addresses_remove_roles,
        roles_to_remove,
        vector[],
        vector[],        
        world.scenario.ctx()
    );
}

public fun propose_thresholds(
    world: &mut World, 
    key: String,
    roles_for_thresholds: vector<String>, 
    thresholds_to_set: vector<u64>, 
) {
    config::propose_modify_rules(
        &mut world.multisig, 
        key,
        b"".to_string(), 
        0, 
        0, 
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        vector[],
        roles_for_thresholds,
        thresholds_to_set,        
        world.scenario.ctx()
    );
}

public fun propose_migrate(
    world: &mut World, 
    key: String,
    version: u64
) {
    config::propose_migrate(
        &mut world.multisig,
        key,
        b"".to_string(), 
        0, 
        0, 
        version,
        world.scenario.ctx()
    );
}

// === Kiosk ===

public fun place<T: key + store>(
    world: &mut World, 
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    name: String,
    nft_id: ID,
    policy: &mut TransferPolicy<T>,
): TransferRequest<T> {
    k_kiosk::place(
        &mut world.multisig,
        &mut world.kiosk,
        sender_kiosk,
        sender_cap,
        name,
        nft_id,
        policy,
        world.scenario.ctx()
    )
}

public fun propose_take(
    world: &mut World, 
    key: String,
    name: String,
    nft_ids: vector<ID>,
    recipient: address,
) {
    k_kiosk::propose_take(
        &mut world.multisig,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        nft_ids,
        recipient,
        world.scenario.ctx()
    )
}

public fun execute_take<T: key + store>(
    world: &mut World, 
    executable: &mut Executable,
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<T>
): TransferRequest<T> {
    k_kiosk::execute_take(
        executable,
        &mut world.multisig,
        &mut world.kiosk,
        recipient_kiosk,
        recipient_cap,
        policy,
        world.scenario.ctx()
    )
}

public fun propose_list(
    world: &mut World, 
    key: String,
    name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>
) {
    k_kiosk::propose_list(
        &mut world.multisig,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        nft_ids,
        prices,
        world.scenario.ctx()
    );
}

public fun execute_list<T: key + store>(
    world: &mut World,
    executable: &mut Executable,
) {
    k_kiosk::execute_list<T>(executable, &mut world.multisig, &mut world.kiosk);
}

// === Payments ===

public fun propose_pay(
    world: &mut World,
    key: String,
    coin: ID, // must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
) {
    payments::propose_pay(
        &mut world.multisig,
        key,
        b"".to_string(), 
        0, 
        0, 
        coin,
        amount,
        interval,
        recipient,
        world.scenario.ctx()
    );
}

public fun execute_pay<C: drop>(
    world: &mut World,
    executable: Executable, 
    receiving: Receiving<Coin<C>>
) {
    payments::execute_pay<C>(executable, &mut world.multisig, receiving, world.scenario.ctx());
}

public fun cancel_payment_stream<C: drop>(
    world: &mut World,
    stream: Stream<C>,
) {
    payments::cancel_payment_stream(stream, &world.multisig, world.scenario.ctx());
}

// === Transfers ===

public fun propose_send(
    world: &mut World, 
    key: String,
    objects: vector<ID>,
    recipients: vector<address>
) {
    transfers::propose_send(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        objects, 
        recipients, 
        world.scenario.ctx()
    );
}

public fun propose_delivery(
    world: &mut World, 
    key: String,
    objects: vector<ID>,
    recipient: address
) {
    transfers::propose_delivery(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        objects, 
        recipient, 
        world.scenario.ctx()
    );
}

public fun create_delivery(
    world: &mut World, 
): (Delivery, DeliveryCap) {
    transfers::create_delivery(&world.multisig, world.scenario.ctx())
}

public fun cancel_delivery(
    world: &mut World, 
    delivery: Delivery, 
) {
    transfers::cancel_delivery(&world.multisig, delivery, world.scenario.ctx());
}

public fun retrieve<T: key + store>(
    world: &mut World,
    delivery: &mut Delivery, 
) {
    transfers::retrieve<T>(delivery, &world.multisig, world.scenario.ctx());
}

// === Currency ===

public fun lock_treasury_cap<C: drop>(world: &mut World, cap: TreasuryCap<C>) {
    currency::lock_cap(&mut world.multisig, cap, world.scenario.ctx());
}

public fun propose_mint<C: drop>(
    world: &mut World, 
    key: String,    
    amount: u64
) {
    currency::propose_mint<C>(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        amount,
        world.scenario.ctx()
    );
}

public fun execute_mint<C: drop>(
    world: &mut World,
    executable: Executable,
) {
    currency::execute_mint<C>(executable, &mut world.multisig, world.scenario.ctx());
}

public fun propose_burn<C: drop>(
    world: &mut World, 
    key: String,
    coin_id: ID,
    amount: u64,
) {
    currency::propose_burn<C>(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        coin_id,
        amount,
        world.scenario.ctx()
    );
}

public fun propose_update<C: drop>(
    world: &mut World, 
    key: String,
    name: Option<String>,
    symbol: Option<String>,
    description_md: Option<String>,
    icon_url: Option<String>,
) {
    currency::propose_update<C>(
        &mut world.multisig,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        symbol,
        description_md,
        icon_url,
        world.scenario.ctx()
    );
}

// === Upgrade Policies ===

public fun lock_cap(
    world: &mut World,
    upgrade_lock: UpgradeLock,
    label: String,
) {
    upgrade_lock.lock_cap(&mut world.multisig, label, world.scenario.ctx());
}

public fun lock_cap_with_timelock(
    world: &mut World,
    label: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap
) {
    upgrade_policies::lock_cap_with_timelock(&mut world.multisig, label, delay_ms, upgrade_cap, world.scenario.ctx());
}

public fun propose_upgrade(
    world: &mut World, 
    key: String,
    name: String,
    digest: vector<u8>,
) {
    upgrade_policies::propose_upgrade(
        &mut world.multisig, 
        key, 
        b"".to_string(), 
        0, 
        name,
        digest, 
        &world.clock, 
        world.scenario.ctx()
    ); 
}

public fun propose_restrict(
    world: &mut World, 
    key: String,
    name: String,
    policy: u8,
) {
    upgrade_policies::propose_restrict(
        &mut world.multisig, 
        key, 
        b"".to_string(),
        0, 
        name, 
        policy, 
        &world.clock, 
        world.scenario.ctx()
    );
}