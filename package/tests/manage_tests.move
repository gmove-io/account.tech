#[test_only]
module sui_multisig::manage_tests{
    use std::debug::print;
    use std::ascii::{Self, String};
    use sui::test_scenario::{Self as ts, Scenario};

    use sui_multisig::multisig::{Self, Multisig};
    use sui_multisig::manage::{Self, Manage};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // hot potato holding the state
    public struct World {
        scenario: Scenario,
        multisig: Multisig,
    }

    // utils

    fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        let scen = &mut scenario;

        // initialize multisig
        multisig::new(scen.ctx());
        scen.next_tx(OWNER);

        let multisig = scenario.take_shared<Multisig>();
        World { scenario, multisig }
    }

    fun forward_world(world: &mut World, user: address) {
        world.scenario.next_tx(user);
    }

    fun end_world(world: World) {
        let World { scenario, multisig } = world;
        ts::return_shared(multisig);
        scenario.end();
    }

    fun manage_multisig(
        world: &mut World,
        name: vector<u8>,
        id_add: bool,
        threshold: u64,
        addresses: vector<address>,
    ) {
        manage::propose(
            &mut world.multisig,
            ascii::string(name),
            0,
            ascii::string(b""),
            id_add,
            threshold,
            addresses,
            world.scenario.ctx()
        );
        multisig::approve_proposal(
            &mut world.multisig,
            ascii::string(name),
            world.scenario.ctx()
        );
        manage::execute(
            &mut world.multisig,
            ascii::string(name),
            world.scenario.ctx()
        );
    }

    // === test normal operations === 

    #[test]
    fun publish_package() {
        let world = start_world();
        end_world(world);
    }

    #[test]
    fun add_members_increase_threshold() {
        let mut world = start_world();
        manage_multisig(
            &mut world,
            b"add_members_increase_threshold",
            true,
            2,
            vector[ALICE, BOB],
        );
        multisig::assert_multisig_data_numbers(&world.multisig, 2, 3, 0);
        end_world(world);
    }

}

