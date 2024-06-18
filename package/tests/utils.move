#[test_only]
module kraken::test_utils {
    use std::string::{Self, String};

    use sui::{
        bag::Bag,
        coin::Coin,
        test_utils::destroy,
        package::UpgradeCap,
        transfer::Receiving,
        clock::{Self, Clock},
        kiosk::{Kiosk, KioskOwnerCap},
        transfer_policy::{TransferRequest, TransferPolicy},
        test_scenario::{Self as ts, Scenario, receiving_ticket_by_id},
    };

    use kraken::{
        owned,
        config,
        kiosk::{Self as k_kiosk, KioskOwnerLock},
        account::{Self, Account, Invite},
        coin_operations,
        multisig::{Self, Multisig, Proposal, Executable},
        payments::{Self, Stream, Pay},
        upgrade_policies::{Self, UpgradeLock},
        transfers::{Self, Send, Delivery, Deliver}
    };

    const OWNER: address = @0xBABE;

    // hot potato holding the state
    public struct World {
        account: Account,
        scenario: Scenario,
        clock: Clock,
        multisig: Multisig,
        kiosk: Kiosk,
        kiosk_owner_lock_id: ID
    }

    public struct Obj has key, store { id: UID }

    // === Utils ===

    public fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        account::new(string::utf8(b"sam"), string::utf8(b"move_god.png"), scenario.ctx());

        scenario.next_tx(OWNER);

        let account = scenario.take_from_sender<Account>();

        // initialize multisig and clock
        let multisig = multisig::new(string::utf8(b"kraken"), object::id(&account), scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        let kiosk_owner_lock_id = k_kiosk::new(&multisig, scenario.ctx());

        scenario.next_tx(OWNER);

        let kiosk = scenario.take_shared<Kiosk>();

        World { scenario, clock, multisig, account, kiosk, kiosk_owner_lock_id }
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

    public fun withdraw<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        receiving: Receiving<Object>,
        witness: Witness,
        idx: u64
    ): Object {
        owned::withdraw<Object, Witness>(executable, &mut world.multisig, receiving, witness, idx)
    }

    public fun put_back<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        returned: Object,
        witness: Witness,
        idx: u64
    ) {
        owned::put_back<Object, Witness>(executable, &world.multisig, returned, witness, idx);
    }

    public fun borrow<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        receiving: Receiving<Object>,
        witness: Witness,
        idx: u64
    ): Object {
        owned::borrow<Object, Witness>(executable, &mut world.multisig, receiving, witness, idx)
    }

    public fun create_proposal<Witness: drop>(
        world: &mut World, 
        witness: Witness,
        key: String, 
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String
    ): &mut Proposal {
        world.multisig.create_proposal(
            witness, 
            key,
            execution_time, 
            expiration_epoch, 
            description, 
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

    public fun merge_and_split<T: drop>(
        world: &mut World, 
        to_merge: vector<Receiving<Coin<T>>>,
        to_split: vector<u64> 
    ): vector<ID> {
        coin_operations::merge_and_split(&mut world.multisig, to_merge, to_split, world.scenario.ctx())
    }

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

    public fun propose_modify(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        threshold: Option<u64>, 
        to_remove: vector<address>, 
        to_add: vector<address>, 
        weights: vector<u64>
    ) {
        config::propose_modify(
            &mut world.multisig, 
            key, 
            execution_time, 
            expiration_epoch, 
            description, 
            name, 
            threshold, 
            to_remove, 
            to_add, 
            weights,
            world.scenario.ctx()
        );
    }

    public fun propose_migrate(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        version: u64
    ) {
        config::propose_migrate(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            version,
            world.scenario.ctx()
        );
    }

    public fun borrow_cap(world: &mut World): KioskOwnerLock {
        k_kiosk::borrow_cap(&mut world.multisig, receiving_ticket_by_id(world.kiosk_owner_lock_id), world.scenario.ctx())
    }

    public fun place<T: key + store>(
        world: &mut World, 
        lock: &KioskOwnerLock,
        sender_kiosk: &mut Kiosk, 
        sender_cap: &KioskOwnerCap, 
        nft_id: ID,
        policy: &mut TransferPolicy<T>,
    ) {
        k_kiosk::place(
            &mut world.multisig,
            &mut world.kiosk,
            lock,
            sender_kiosk,
            sender_cap,
            nft_id,
            policy,
            world.scenario.ctx()
        )
    }

    public fun propose_take(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        recipient: address,
    ) {
        k_kiosk::propose_take(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            nft_ids,
            recipient,
            world.scenario.ctx()
        )
    }

    public fun execute_take<T: key + store>(
        world: &mut World, 
        executable: &mut Executable,
        lock: &KioskOwnerLock,
        recipient_kiosk: &mut Kiosk, 
        recipient_cap: &KioskOwnerCap, 
        policy: &mut TransferPolicy<T>
    ) {
        k_kiosk::execute_take(
            executable,
            &mut world.kiosk,
            lock,
            recipient_kiosk,
            recipient_cap,
            policy,
            world.scenario.ctx()
        );
    }

    public fun propose_list(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        prices: vector<u64>
    ) {
        k_kiosk::propose_list(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            nft_ids,
            prices,
            world.scenario.ctx()
        );
    }

    public fun execute_list<T: key + store>(
        world: &mut World,
        executable: &mut Executable,
        lock: &KioskOwnerLock,
    ) {
        k_kiosk::execute_list<T>(executable, &mut world.kiosk, lock);
    }

    public fun propose_pay(
        world: &mut World,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin: ID, // must have the total amount to be paid
        amount: u64, // amount to be paid at each interval
        interval: u64, // number of epochs between each payment
        recipient: address,
    ) {
        payments::propose_pay(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
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

    public fun end(world: World) {
        let World { 
            scenario, 
            clock, 
            multisig, 
            account, 
            kiosk,
            kiosk_owner_lock_id: _ 
        } = world;

        destroy(clock);
        destroy(kiosk);
        destroy(account);
        destroy(multisig);
        scenario.end();
    }
}