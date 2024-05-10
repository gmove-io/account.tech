#[test_only]
module sui_multisig::owned_tests{
    use std::debug::print;
    use std::string::{Self, String};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self as ts, Scenario};

    use sui_multisig::multisig::{Self, Multisig};
    use sui_multisig::owned::{Self, Access};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // hot potato holding the state
    public struct World {
        scenario: Scenario,
        clock: Clock,
        multisig: Multisig,
        ids: vector<ID>,
    }

    public struct Obj has key, store { id: UID }

    // === Utils ===

    fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        // initialize multisig and clock
        multisig::new(scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());
        clock.share_for_testing();
        scenario.next_tx(OWNER);

        let clock = scenario.take_shared<Clock>();
        let mut multisig = scenario.take_shared<Multisig>();
        let id = object::new(scenario.ctx());
        let inner_id = id.uid_to_inner();
        transfer::public_transfer(
            Obj { id },
            multisig.addr()
        );
        scenario.next_tx(OWNER);

        World { scenario, clock, multisig, ids: vector[inner_id] }
    }

    fun end_world(world: World) {
        let World { scenario, clock, multisig, ids: _ } = world;
        ts::return_shared(clock);
        ts::return_shared(multisig);
        scenario.end();
    }

    fun receive_owned(
        world: &mut World,
        name: vector<u8>,
        to_borrow: vector<ID>,
        to_withdraw: vector<ID>,
    ): Access {
        owned::propose(
            &mut world.multisig,
            string::utf8(name),
            0,
            0,
            string::utf8(b""),
            to_borrow,
            to_withdraw,
            world.scenario.ctx()
        );
        multisig::approve_proposal(
            &mut world.multisig,
            string::utf8(name),
            world.scenario.ctx()
        );
        multisig::execute_proposal(
            &mut world.multisig,
            string::utf8(name),
            &world.clock,
            world.scenario.ctx()
        )
    }

    // === test normal operations === 

    #[test]
    fun publish_package() {
        let world = start_world();
        end_world(world);
    }

    #[test]
    fun withdraw_and_send_object() {
        let mut world = start_world();
        let id = world.ids[0];
        let mut action = receive_owned(
            &mut world, 
            b"withdraw", 
            vector[],
            vector[id]
        );
        let ticket = ts::receiving_ticket_by_id<Obj>(id);
        let owned = owned::pop_owned(&mut action);
        let obj = owned::take(&mut world.multisig, owned, ticket);
        owned::complete(action);
        transfer::public_transfer(obj, OWNER);
        end_world(world);
    }

    #[test]
    fun borrow_and_return_object() {
        let mut world = start_world();
        let id = world.ids[0];
        let mut action = receive_owned(
            &mut world, 
            b"borrow", 
            vector[id],
            vector[]
        );
        let ticket = ts::receiving_ticket_by_id<Obj>(id);
        let owned = owned::pop_owned(&mut action);
        let (obj, promise) = owned::borrow(&mut world.multisig, owned, ticket);
        owned::put_back(obj, promise);
        owned::complete(action);
        end_world(world);
    }

}

