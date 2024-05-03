#[test_only]
module sui_multisig::access_owned_tests{
    use std::debug::print;
    use std::ascii::{Self, String};
    use sui::test_scenario::{Self as ts, Scenario};

    use sui_multisig::multisig::{Self, Multisig};
    use sui_multisig::access_owned::{Self, Access};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // hot potato holding the state
    public struct World {
        scenario: Scenario,
        multisig: Multisig,
        ids: vector<ID>,
    }

    public struct Obj has key, store { id: UID }

    // === Utils ===

    fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        // initialize multisig
        multisig::new(scenario.ctx());
        scenario.next_tx(OWNER);

        let mut multisig = scenario.take_shared<Multisig>();
        let ms_addr = multisig.uid_mut().uid_to_inner().id_to_address();
        let id = object::new(scenario.ctx());
        let inner_id = id.uid_to_inner();
        transfer::public_transfer(
            Obj { id },
            ms_addr
        );
        scenario.next_tx(OWNER);

        World { scenario, multisig, ids: vector[inner_id] }
    }

    fun end_world(world: World) {
        let World { scenario, multisig, ids: _ } = world;
        ts::return_shared(multisig);
        scenario.end();
    }

    fun receive_owned(
        world: &mut World,
        name: vector<u8>,
        to_borrow: vector<ID>,
        to_withdraw: vector<ID>,
    ): Access {
        access_owned::propose(
            &mut world.multisig,
            ascii::string(name),
            0,
            ascii::string(b""),
            to_borrow,
            to_withdraw,
            world.scenario.ctx()
        );
        multisig::approve_proposal(
            &mut world.multisig,
            ascii::string(name),
            world.scenario.ctx()
        );
        multisig::execute_proposal(
            &mut world.multisig,
            ascii::string(name),
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
        let owned = access_owned::pop_owned(&mut action);
        let obj = access_owned::withdraw(&mut world.multisig, owned, ticket);
        access_owned::complete(action);
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
        let owned = access_owned::pop_owned(&mut action);
        let (obj, promise) = access_owned::borrow(&mut world.multisig, owned, ticket);
        access_owned::put_back(obj, promise);
        access_owned::complete(action);
        end_world(world);
    }

}

