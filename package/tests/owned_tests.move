#[test_only]
module kraken::owned_tests{
    // use std::string;

    // use sui::clock::{Self, Clock};
    // use sui::test_scenario::{Self as ts, Scenario};

    // use kraken::owned::{Self, Borrow};
    // use kraken::multisig::{Self, Multisig};
    // use kraken::test_utils::{start_world, end_world};

    // const OWNER: address = @0xBABE;

    // // hot potato holding the state
    // public struct World {
    //     scenario: Scenario,
    //     clock: Clock,
    //     multisig: Multisig,
    //     ids: vector<ID>,
    // }

    // public struct Obj has key, store { id: UID }

    // fun borrow(
    //     world: &mut World,
    //     key: vector<u8>,
    //     objects: vector<ID>,
    // ): Borrow {
    //     owned::propose_borrow(
    //         &mut world.multisig,
    //         string::utf8(key),
    //         0,
    //         0,
    //         string::utf8(b""),
    //         objects,
    //         world.scenario.ctx()
    //     );
    //     multisig::approve_proposal(
    //         &mut world.multisig,
    //         string::utf8(key),
    //         world.scenario.ctx()
    //     );
    //     multisig::execute_proposal(
    //         &mut world.multisig,
    //         string::utf8(key),
    //         &world.clock,
    //         world.scenario.ctx()
    //     )
    // }

    // // === test normal operations === 



}

