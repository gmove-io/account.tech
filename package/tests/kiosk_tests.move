#[test_only]
module kraken::kiosk_tests;

use std::string::utf8;

use sui::kiosk;
use sui::transfer_policy;
use sui::test_utils::{destroy, assert_eq};

use kiosk::{
    royalty_rule,
    kiosk_lock_rule
};

use kraken::{
    kiosk as k_kiosk,
    test_utils::start_world
};

const OWNER: address = @0xBABE;
const ALICE: address = @0xA11CE;

public struct NFT has key, store {
    id: UID
}

#[test]
fun test_place() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);

    sender_kiosk.place(&sender_cap, nft);

    assert_eq(sender_kiosk.has_item(nft_id), true);
    assert_eq(world.kiosk().has_item(nft_id), false);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);

    assert_eq(sender_kiosk.has_item(nft_id), false);
    assert_eq(world.kiosk().has_item(nft_id), true);
    
    k_kiosk::put_back_cap(kiosk_owner_lock);
    
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
fun test_propose_take() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft2 = new_nft(world.scenario().ctx());

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);
    let nft_id2 = object::id(&nft2);

    sender_kiosk.place(&sender_cap, nft);
    sender_kiosk.place(&sender_cap, nft2);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id2, &mut policy);        

    world.scenario().next_tx(OWNER);

    let key = utf8(b"key");

    assert_eq(world.kiosk().has_item(nft_id), true);
    assert_eq(world.kiosk().has_item(nft_id2), true);

    world.propose_take(
        key,
        7,
        2,
        utf8(b"take NFT"),
        vector[nft_id2],
        OWNER,
    );

    world.scenario().next_tx(OWNER);
    world.scenario().next_tx(OWNER);
    world.clock().increment_for_testing(7);

    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(key);

    world.execute_take(
        &mut executable,
        &kiosk_owner_lock,
        &mut sender_kiosk,
        &sender_cap,
        &mut policy
    );

    k_kiosk::complete_take(executable);

    assert_eq(world.kiosk().has_item(nft_id), true);
    assert_eq(world.kiosk().has_item(nft_id2), false);
    assert_eq(sender_kiosk.has_item(nft_id2), true);

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
fun test_propose_list() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);

    sender_kiosk.place(&sender_cap, nft);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);

    world.scenario().next_tx(OWNER);

    assert_eq(world.kiosk().is_listed(nft_id), false);

    let key_list = utf8(b"propose_list");

    world.propose_list(
        key_list,
        0,
        0,
        utf8(b"description"),
        vector[nft_id],
        vector[777],
    );

    world.approve_proposal(key_list);

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(key_list);

    world.execute_list<NFT>(&mut executable, &kiosk_owner_lock);

    assert_eq(world.kiosk().is_listed(nft_id), true);

    k_kiosk::complete_list(executable);
    
    destroy(kiosk_owner_lock);        
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}

#[test]
#[expected_failure(abort_code = k_kiosk::EWrongReceiver)]
fun test_take_error_wrong_receiver() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);

    sender_kiosk.place(&sender_cap, nft);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 

    world.scenario().next_tx(OWNER);

    let key = utf8(b"key");

    world.propose_take(
        key,
        7,
        2,
        utf8(b"take NFT"),
        vector[nft_id],
        ALICE,
    );

    world.scenario().next_tx(OWNER);
    world.scenario().next_tx(OWNER);
    world.clock().increment_for_testing(7);

    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(key);

    world.execute_take(
        &mut executable,
        &kiosk_owner_lock,
        &mut sender_kiosk,
        &sender_cap,
        &mut policy
    );

    k_kiosk::complete_take(executable);

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
#[expected_failure(abort_code = k_kiosk::ETransferAllNftsBefore)]
fun test_destroy_take_error_tranfer_all_nfts_before() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);

    sender_kiosk.place(&sender_cap, nft);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 

    world.scenario().next_tx(OWNER);

    let key = utf8(b"key");

    world.propose_take(
        key,
        7,
        2,
        utf8(b"take NFT"),
        vector[nft_id],
        OWNER,
    );

    world.scenario().next_tx(OWNER);
    world.scenario().next_tx(OWNER);
    world.clock().increment_for_testing(7);

    world.approve_proposal(key);

    world.scenario().next_tx(OWNER);

    let executable = world.execute_proposal(key);

    k_kiosk::complete_take(executable);

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
#[expected_failure(abort_code = k_kiosk::EWrongNftsPrices)]
fun test_new_list_error_wrong_nfts_prices() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);

    sender_kiosk.place(&sender_cap, nft);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);

    world.scenario().next_tx(OWNER);

    let key_list = utf8(b"propose_list");

    world.propose_list(
        key_list,
        0,
        0,
        utf8(b"description"),
        vector[nft_id],
        vector[777, 888],
    );

    world.approve_proposal(key_list);

    world.scenario().next_tx(OWNER);

    let mut executable = world.execute_proposal(key_list);

    world.execute_list<NFT>(&mut executable, &kiosk_owner_lock);

    k_kiosk::complete_list(executable);
    
    destroy(kiosk_owner_lock);        
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}

#[test]
#[expected_failure(abort_code = k_kiosk::EListAllNftsBefore)]
fun test_destroy_list_error_list_all_nfts_before() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_cap();

    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft2 = new_nft(world.scenario().ctx());

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    let nft_id = object::id(&nft);
    let nft_id2 = object::id(&nft2);

    sender_kiosk.place(&sender_cap, nft);
    sender_kiosk.place(&sender_cap, nft2);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id2, &mut policy);

    world.scenario().next_tx(OWNER);

    let key_list = utf8(b"propose_list");

    world.propose_list(
        key_list,
        0,
        0,
        utf8(b"description"),
        vector[nft_id, nft_id2],
        vector[777, 993],
    );

    world.approve_proposal(key_list);

    world.scenario().next_tx(OWNER);

    let executable = world.execute_proposal(key_list);

    k_kiosk::complete_list(executable);
    
    destroy(kiosk_owner_lock);        
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}

fun new_nft(ctx: &mut TxContext): NFT {
    NFT {
        id: object::new(ctx)
    }
}