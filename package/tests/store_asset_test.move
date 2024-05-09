// TODO: update if uncomment

// #[test_only]
// module sui_multisig::store_asset_tests{
//     use std::debug::print;
//     use std::string::{Self, String};
//     use sui::coin::{Self, Coin};
//     use sui::test_scenario::{Self as ts, Scenario};

//     use sui_multisig::multisig::{Self, Multisig};
//     use sui_multisig::store_asset::{Self, Deposit, Withdraw};

//     const OWNER: address = @0xBABE;
//     const ALICE: address = @0xA11CE;
//     const BOB: address = @0xB0B;

//     // hot potato holding the state
//     public struct World {
//         scenario: Scenario,
//         multisig: Multisig,
//         ids: vector<ID>,
//     }

//     public struct COIN has drop {}

//     public struct Obj has key, store { id: UID }

//     // === Utils ===

//     fun start_world(): World {
//         let mut scenario = ts::begin(OWNER);
//         // initialize multisig
//         multisig::new(scenario.ctx());
//         scenario.next_tx(OWNER);

//         let mut multisig = scenario.take_shared<Multisig>();
//         let ms_addr = multisig.uid_mut().uid_to_inner().id_to_address();
//         let id = object::new(scenario.ctx());
//         let obj_id = id.uid_to_inner();
//         transfer::public_transfer(
//             Obj { id },
//             ms_addr
//         );
//         let coin = coin::mint_for_testing<COIN>(1000, scenario.ctx());
//         let coin_id = object::id(&coin);
//         transfer::public_transfer(
//             coin,
//             ms_addr
//         );
//         scenario.next_tx(OWNER);

//         World { scenario, multisig, ids: vector[obj_id, coin_id] }
//     }

//     fun end_world(world: World) {
//         let World { scenario, multisig, ids: _ } = world;
//         ts::return_shared(multisig);
//         scenario.end();
//     }

//     fun deposit(
//         world: &mut World,
//         name: vector<u8>,
//         objects: vector<ID>,
//     ): Deposit {
//         store_asset::propose_deposit(
//             &mut world.multisig,
//             string::utf8(name),
//             0,
//             string::utf8(b""),
//             objects,
//             world.scenario.ctx()
//         );
//         multisig::approve_proposal(
//             &mut world.multisig,
//             string::utf8(name),
//             world.scenario.ctx()
//         );
//         multisig::execute_proposal(
//             &mut world.multisig,
//             string::utf8(name),
//             world.scenario.ctx()
//         )
//     }

//     fun withdraw(
//         world: &mut World,
//         name: vector<u8>,
//         asset_types: vector<String>,
//         amounts: vector<u64>,
//         keys: vector<String>,
//     ): Withdraw {
//         store_asset::propose_withdraw(
//             &mut world.multisig,
//             string::utf8(name),
//             0,
//             string::utf8(b""),
//             asset_types,
//             amounts,
//             keys,
//             world.scenario.ctx()
//         );
//         multisig::approve_proposal(
//             &mut world.multisig,
//             string::utf8(name),
//             world.scenario.ctx()
//         );
//         multisig::execute_proposal(
//             &mut world.multisig,
//             string::utf8(name),
//             world.scenario.ctx()
//         )
//     }

//     // === test normal operations === 

//     #[test]
//     fun publish_package() {
//         let world = start_world();
//         end_world(world);
//     }

//     #[test]
//     fun deposit_fungible_and_non_fungible() {
//         let mut world = start_world();
//         let obj_id = world.ids[0];
//         let coin_id = world.ids[1];
//         let mut action = deposit(
//             &mut world, 
//             b"deposit", 
//             vector[obj_id, coin_id]
//         );
//         let obj_ticket = ts::receiving_ticket_by_id<Obj>(obj_id);
//         let coin_ticket = ts::receiving_ticket_by_id<Coin<COIN>>(coin_id);
//         store_asset::deposit_non_fungible(
//             &mut world.multisig, 
//             &mut action, 
//             obj_ticket,
//             string::utf8(b"1"),
//             world.scenario.ctx() 
//         );
//         store_asset::deposit_fungible(
//             &mut world.multisig, 
//             &mut action, 
//             coin_ticket,
//         );
//         store_asset::complete_deposit(action);
//         end_world(world);
//     }

//     #[test]
//     fun deposit_and_withdraw_non_fungible() {
//         let mut world = start_world();
//         let obj_id = world.ids[0];
//         // deposit Obj 
//         let mut action = deposit(
//             &mut world, 
//             b"deposit", 
//             vector[obj_id]
//         );
//         let obj_ticket = ts::receiving_ticket_by_id<Obj>(obj_id);
//         store_asset::deposit_non_fungible(
//             &mut world.multisig, 
//             &mut action, 
//             obj_ticket,
//             string::utf8(b"1"),
//             world.scenario.ctx() 
//         );
//         store_asset::complete_deposit(action);
//         // withdraw Obj
//         let mut action = withdraw(
//             &mut world,
//             b"withdraw",
//             vector[string::utf8(b"0000000000000000000000000000000000000000000000000000000000000000::store_asset_tests::Obj")],
//             vector[1],
//             vector[string::utf8(b"1")],
//         );
//         let obj = store_asset::withdraw_non_fungible<Obj>(&mut world.multisig, &mut action);
//         store_asset::complete_withdraw(action);
//         transfer::public_transfer(obj, OWNER);
//         end_world(world);
//     }

//     #[test]
//     fun deposit_and_withdraw_fungible() {
//         let mut world = start_world();
//         let coin_id = world.ids[1];
//         // deposit Coin
//         let mut action = deposit(
//             &mut world, 
//             b"deposit", 
//             vector[coin_id]
//         );
//         let coin_ticket = ts::receiving_ticket_by_id<Coin<COIN>>(coin_id);
//         store_asset::deposit_fungible(
//             &mut world.multisig, 
//             &mut action, 
//             coin_ticket,
//         );
//         store_asset::complete_deposit(action);
//         // withdraw Coin
//         let mut action = withdraw(
//             &mut world,
//             b"withdraw",
//             vector[string::utf8(b"0000000000000000000000000000000000000000000000000000000000000000::store_asset_tests::COIN")],
//             vector[1000],
//             vector[string::utf8(b"")],
//         );
//         let obj = store_asset::withdraw_fungible<COIN>(&mut world.multisig, &mut action, world.scenario.ctx());
//         store_asset::complete_withdraw(action);
//         transfer::public_transfer(obj, OWNER);
//         end_world(world);
//     }
// }

