#[test_only]
module kraken::test_utils {
    use std::string::{Self, String};

    use sui::{
        coin::Coin,
        test_utils::destroy,
        package::UpgradeCap,
        transfer::Receiving,
        clock::{Self, Clock},
        kiosk::{Kiosk, KioskOwnerCap},
        transfer_policy::TransferRequest,
        test_scenario::{Self as ts, Scenario}
    };

    use kraken::{
        owned,
        config,
        kiosk as k_kiosk,
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

        World { scenario, clock, multisig, account }
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

    // public fun clean_proposals(world: &mut World) {
    //     world.multisig.clean_proposals(world.scenario.ctx());
    // }

    // public fun delete_proposal(
    //     world: &mut World, 
    //     key: String
    // ) {
    //     world.multisig.delete_proposal(key, world.scenario.ctx());
    // }


    // public fun propose_modify(
    //     world: &mut World, 
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     name: Option<String>,
    //     threshold: Option<u64>, 
    //     to_add: vector<address>, 
    //     to_remove: vector<address>, 
    // ) {
    //     config::propose_modify(
    //         &mut world.multisig, 
    //         key, 
    //         execution_time, 
    //         expiration_epoch, 
    //         description, 
    //         name, 
    //         threshold, 
    //         to_add, 
    //         to_remove, 
    //         world.scenario.ctx()
    //     );
    // }

    // public fun execute_modify(
    //     world: &mut World,
    //     name: String, 
    // ) {
    //     config::execute_modify(&mut world.multisig, name, &world.clock, world.scenario.ctx());
    // }

    // public fun send_invite(world: &mut World, recipient: address) {
    //     account::send_invite(&mut world.multisig, recipient, world.scenario.ctx());
    // }

    // public fun propose_move_call(
    //     world: &mut World, 
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     digest: vector<u8>,
    //     to_borrow: vector<ID>,
    //     to_withdraw: vector<ID>,
    // ) {
    //     move_call::propose_move_call(&mut world.multisig, key, execution_time, expiration_epoch, description, digest, to_borrow, to_withdraw, world.scenario.ctx());
    // }

    // public fun propose_pay(
    //     world: &mut World,  
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     coin: ID, // must have the total amount to be paid
    //     amount: u64, // amount to be paid at each interval
    //     interval: u64, // number of epochs between each payment
    //     recipient: address
    // ) {
    //     payments::propose_pay(
    //         &mut world.multisig,
    //         key,
    //         execution_time,
    //         expiration_epoch,
    //         description,
    //         coin,
    //         amount,
    //         interval,
    //         recipient,
    //         world.scenario.ctx()
    //     );
    // }

    // public fun create_stream<C: drop>(
    //     world: &mut World, 
    //     action: Action<Pay>, 
    //     received: Receiving<Coin<C>>,
    // ) {
    //     payments::create_stream(action, &mut world.multisig, received, world.scenario.ctx());
    // }

    // public fun cancel_payment<C: drop>(
    //     world: &mut World,
    //     stream: Stream<C>
    // ) {
    //     stream.cancel_payment(&mut world.multisig, world.scenario.ctx());
    // }

    // public fun propose_send(
    //     world: &mut World,  
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     objects: vector<ID>,
    //     recipients: vector<address>
    // ) {
    //     transfers::propose_send(
    //         &mut world.multisig, 
    //         key, 
    //         execution_time, 
    //         expiration_epoch, 
    //         description, 
    //         objects, 
    //         recipients, 
    //         world.scenario.ctx()
    //     );
    // }

    // public fun send<T: key + store>(
    //     world: &mut World, 
    //     action: &mut Action<Send>,  
    //     received: Receiving<T>
    // ) {
    //     transfers::send(action, &mut world.multisig, received);
    // }

    // public fun propose_delivery(
    //     world: &mut World, 
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     objects: vector<ID>,
    //     recipient: address
    // ) {
    //     transfers::propose_delivery(
    //         &mut world.multisig, 
    //         key, 
    //         execution_time, 
    //         expiration_epoch, 
    //         description, 
    //         objects, 
    //         recipient,
    //         world.scenario.ctx()
    //     );
    // }

    // public fun add_to_delivery<T: key + store>(
    //     world: &mut World, 
    //     delivery: &mut Delivery, 
    //     action: &mut Action<Deliver>, 
    //     received: Receiving<T>
    // ) {
    //     transfers::add_to_delivery(delivery, action, &mut world.multisig, received);
    // }

    // public fun retrieve<T: key + store>(
    //     world: &mut World,
    //     delivery: &mut Delivery
    // ) {
    //     transfers::retrieve<T>(delivery, &world.multisig, world.scenario.ctx());
    // }

    // public fun cancel_delivery(
    //     world: &mut World, 
    //     delivery: Delivery, 
    // ) {
    //     transfers::cancel_delivery(&mut world.multisig, delivery, world.scenario.ctx());
    // }


    // public fun lock_cap(
    //     world: &mut World, 
    //     label: String,
    //     time_lock: u64,
    //     upgrade_cap: UpgradeCap
    // ): ID {
    //     upgrade_policies::lock_cap(&mut world.multisig, label, time_lock, upgrade_cap, world.scenario.ctx())        
    // }

    // public fun propose_upgrade(
    //     world: &mut World, 
    //     key: String,
    //     expiration_epoch: u64,
    //     description: String,
    //     digest: vector<u8>,
    //     upgrade_lock: Receiving<UpgradeLock>
    // ) {
    //     upgrade_policies::propose_upgrade(
    //         &mut world.multisig, 
    //         key, 
    //         expiration_epoch, 
    //         description, 
    //         digest, 
    //         upgrade_lock,
    //         &world.clock,
    //         world.scenario.ctx()
    //     );
    // }

    // public fun propose_policy(
    //     world: &mut World,  
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     policy: u8,
    //     upgrade_lock: Receiving<UpgradeLock>
    // ) {
    //     upgrade_policies::propose_policy(
    //         &mut world.multisig,
    //         key,
    //         execution_time,
    //         expiration_epoch,
    //         description,
    //         policy,
    //         upgrade_lock,
    //         world.scenario.ctx()  
    //     );
    // }

    // public fun new_kiosk(world: &mut World): (Kiosk, KioskOwnerCap) {
    //     k_kiosk::new(&mut world.multisig, world.scenario.ctx())
    // }

    // public fun transfer_from<T: key + store>(
    //     world: &mut World, 
    //     multisig_kiosk: &mut Kiosk, 
    //     multisig_cap: Receiving<KioskOwnerCap>,
    //     sender_kiosk: &mut Kiosk, 
    //     sender_cap: &KioskOwnerCap, 
    //     nft_id: ID
    // ): TransferRequest<T> {
    //     k_kiosk::transfer_from(
    //         &mut world.multisig, 
    //         multisig_kiosk, 
    //         multisig_cap, 
    //         sender_kiosk, 
    //         sender_cap, 
    //         nft_id, 
    //         world.scenario.ctx()
    //     )
    // }

    // public fun propose_transfer_to(
    //     world: &mut World, 
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     cap_id: ID,
    //     nfts: vector<ID>,
    //     recipient: address
    // ) {
    //     k_kiosk::propose_transfer_to(
    //         &mut world.multisig, 
    //         key,
    //         execution_time,
    //         expiration_epoch,
    //         description,
    //         cap_id,
    //         nfts,
    //         recipient,
    //         world.scenario.ctx()
    //     )        
    // }

    // public fun propose_list(
    //     world: &mut World,
    //     key: String,
    //     execution_time: u64,
    //     expiration_epoch: u64,
    //     description: String,
    //     cap_id: ID,
    //     nfts: vector<ID>,
    //     prices: vector<u64>
    // ) {
    //     k_kiosk::propose_list(
    //         &mut world.multisig,
    //         key,
    //         execution_time,
    //         expiration_epoch,
    //         description,
    //         cap_id,
    //         nfts,
    //         prices,
    //         world.scenario.ctx()
    //     );
    // }

    // public fun delist<T: key + store>(
    //     world: &mut World, 
    //     kiosk: &mut Kiosk, 
    //     cap: Receiving<KioskOwnerCap>,
    //     nft: ID
    // ) {
    //     k_kiosk::delist<T>(
    //         &mut world.multisig,
    //         kiosk,
    //         cap,
    //         nft,
    //         world.scenario.ctx()
    //     );
    // }

    // public fun withdraw_profits(
    //     world: &mut World, 
    //     kiosk: &mut Kiosk,
    //     cap: &KioskOwnerCap,
    // ) {
    //     k_kiosk::withdraw_profits(&mut world.multisig, kiosk, cap, world.scenario.ctx());
    // }

    public fun end(world: World) {
        let World { scenario, clock, multisig, account } = world;
        destroy(clock);
        destroy(account);
        destroy(multisig);
        scenario.end();
    }
}