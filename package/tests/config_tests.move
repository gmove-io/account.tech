#[test_only]
module kraken::manage_tests{
    use std::debug::print;
    use std::string::{Self, String};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self as ts, Scenario};

    use kraken::multisig::{Self, Multisig};
    use kraken::config::{Self, Configure};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // hot potato holding the state
    public struct World {
        scenario: Scenario,
        clock: Clock,
        multisig: Multisig,
    }

    // === Utils ===

    fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        // initialize multisig and clock
        multisig::new(string::utf8(b"kraken"), scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        clock.share_for_testing();
        scenario.next_tx(OWNER);

        let multisig = scenario.take_shared<Multisig>();
        let clock = scenario.take_shared<Clock>();
        World { scenario, clock, multisig }
    }

    fun end_world(world: World) {
        let World { scenario, clock, multisig } = world;
        ts::return_shared(multisig);
        ts::return_shared(clock);
        scenario.end();
    }

    fun manage_multisig(
        world: &mut World,
        mut approvals: u64,
        key: vector<u8>,
        name: Option<String>,
        threshold: Option<u64>,
        to_add: vector<address>,
        to_remove: vector<address>,
    ) {
        let users = vector[OWNER, ALICE, BOB];
        config::propose(
            &mut world.multisig,
            string::utf8(key),
            0,
            0,
            string::utf8(b""),
            name,
            threshold,
            to_add,
            to_remove,
            world.scenario.ctx()
        );
        // approves as many times as necessary
        while (approvals > 0) {
            multisig::approve_proposal(
                &mut world.multisig,
                string::utf8(key),
                world.scenario.ctx()
            );
            approvals = approvals - 1;
            world.scenario.next_tx(users[approvals]);
        };
        config::execute(
            &mut world.multisig,
            string::utf8(key),
            &world.clock,
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
            1,
            b"add_members_increase_threshold",
            option::none(),
            option::some(2),
            vector[ALICE, BOB],
            vector[],
        );
        multisig::assert_multisig_data_numbers(&world.multisig, 2, 3, 0);
        end_world(world);
    }

    #[test]
    fun add_members_then_remove_members() {
        let mut world = start_world();
        // add 2 members and increase threshold
        manage_multisig(
            &mut world,
            1,
            b"add_members_increase_threshold",
            option::none(),
            option::some(3),
            vector[ALICE, BOB],
            vector[],
        );
        multisig::assert_multisig_data_numbers(&world.multisig, 3, 3, 0);
        manage_multisig(
            &mut world,
            3,
            b"remove_members_same_threshold",
            option::none(),
            option::some(2),
            vector[],
            vector[BOB],
        );
        multisig::assert_multisig_data_numbers(&world.multisig, 2, 2, 0);
        end_world(world);
    }

}

