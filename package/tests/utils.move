#[test_only]
module kraken::test_utils {
    use std::string::{Self, String};

    use sui::coin::Coin;
    use sui::test_utils::destroy;
    use sui::transfer::Receiving;
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self as ts, Scenario};
    
    use kraken::owned;
    use kraken::config;
    use kraken::coin_operations;
    use kraken::multisig::{Self, Multisig}; 

    const OWNER: address = @0xBABE;

    // hot potato holding the state
    public struct World {
        scenario: Scenario,
        clock: Clock,
        multisig: Multisig,
    }

    public struct Obj has key, store { id: UID }

    // === Utils ===

    public fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        // initialize multisig and clock
        let multisig = multisig::new(string::utf8(b"kraken"), scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        World { scenario, clock, multisig }
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

    public fun create_proposal<T: store>(
        world: &mut World, 
        action: T,
        key: String, 
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String
    ) {
        world.multisig.create_proposal(action, key, execution_time, expiration_epoch, description, world.scenario.ctx());
    }

    public fun clean_proposals(world: &mut World) {
        world.multisig.clean_proposals(world.scenario.ctx());
    }

    public fun delete_proposal(
        world: &mut World, 
        key: String
    ) {
        world.multisig.delete_proposal(key, world.scenario.ctx());
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

    public fun execute_proposal<T: store>(
        world: &mut World, 
        key: String, 
    ): T {
        world.multisig.execute_proposal<T>(key, &world.clock, world.scenario.ctx())
    }

    public fun propose_borrow(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
    ) {
        owned::propose_borrow(&mut world.multisig, key, execution_time, expiration_epoch, description, objects, world.scenario.ctx());
    }

    public fun propose_modify(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        threshold: Option<u64>, 
        to_add: vector<address>, 
        to_remove: vector<address>, 
    ) {
        config::propose_modify(
            &mut world.multisig, 
            key, 
            execution_time, 
            expiration_epoch, 
            description, 
            name, 
            threshold, 
            to_add, 
            to_remove, 
            world.scenario.ctx()
        );
    }

    public fun execute_modify(
        world: &mut World,
        name: String, 
    ) {
        config::execute_modify(&mut world.multisig, name, &world.clock, world.scenario.ctx());
    }

    public fun merge_coins<T: drop>(
        world: &mut World, 
        to_keep: Receiving<Coin<T>>,
        to_merge: vector<Receiving<Coin<T>>>, 
    ) {
        coin_operations::merge_coins(&mut world.multisig, to_keep, to_merge, world.scenario.ctx());
    }

    public fun split_coins<T: drop>(
        world: &mut World,  
        to_split: Receiving<Coin<T>>,
        amounts: vector<u64>, 
    ): vector<ID> {
        coin_operations::split_coins(&mut world.multisig, to_split, amounts, world.scenario.ctx())
    }

    public fun end(world: World) {
        let World { scenario, clock, multisig } = world;
        destroy(clock);
        destroy(multisig);
        scenario.end();
    }
}