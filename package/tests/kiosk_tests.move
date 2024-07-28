#[test_only]
module kraken::kiosk_tests;

use sui::{
    kiosk,
    transfer_policy,
    test_utils::destroy
};
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
fun place_in_kiosk() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());
    
    let nft = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    assert!(sender_kiosk.has_item(nft_id));
    assert!(!world.kiosk().has_item(nft_id));

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);
    assert!(!sender_kiosk.has_item(nft_id));
    assert!(world.kiosk().has_item(nft_id));
    
    k_kiosk::put_back_lock(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
fun test_propose_take() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft2 = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);
    let nft_id2 = object::id(&nft2);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    sender_kiosk.place(&sender_cap, nft2);

    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id2, &mut policy);        

    world.scenario().next_tx(OWNER);
    assert!(world.kiosk().has_item(nft_id));
    assert!(world.kiosk().has_item(nft_id2));

    let key = b"take proposal".to_string();
    world.propose_take(key, b"".to_string(), vector[nft_id2], OWNER);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    world.execute_take(
        &mut executable,
        &kiosk_owner_lock,
        &mut sender_kiosk,
        &sender_cap,
        &mut policy
    );
    k_kiosk::complete_take(executable);

    assert!(world.kiosk().has_item(nft_id));
    assert!(!world.kiosk().has_item(nft_id2));
    assert!(sender_kiosk.has_item(nft_id2));

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test]
fun list_end_to_end() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);

    world.scenario().next_tx(OWNER);
    assert!(!world.kiosk().is_listed(nft_id));

    let key = b"list proposal".to_string();
    world.propose_list(key, b"".to_string(), vector[nft_id], vector[777]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    world.execute_list<NFT>(&mut executable, &kiosk_owner_lock);
    k_kiosk::complete_list(executable);

    assert!(world.kiosk().is_listed(nft_id));
    
    destroy(kiosk_owner_lock);        
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}

#[test, expected_failure(abort_code = k_kiosk::EWrongReceiver)]
fun take_error_wrong_receiver() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 

    world.scenario().next_tx(OWNER);
    let key = b"take proposal".to_string();
    world.propose_take(key, b"".to_string(), vector[nft_id], ALICE);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    world.execute_take(
        &mut executable,
        &kiosk_owner_lock,
        &mut sender_kiosk,
        &sender_cap,
        &mut policy
    );
    k_kiosk::complete_take(executable);

    assert!(sender_kiosk.has_item(nft_id));

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test, expected_failure(abort_code = k_kiosk::ETransferAllNftsBefore)]
fun destroy_take_error_tranfer_all_nfts_before() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy); 

    world.scenario().next_tx(OWNER);
    let key = b"take proposal".to_string();
    world.propose_take(key, b"".to_string(), vector[nft_id], OWNER);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
    k_kiosk::complete_take(executable);

    destroy(kiosk_owner_lock);
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}   

#[test, expected_failure(abort_code = k_kiosk::EWrongNftsPrices)]
fun new_list_error_wrong_nfts_prices() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);

    world.scenario().next_tx(OWNER);
    let key = b"list proposal".to_string();
    world.propose_list(key, b"".to_string(), vector[nft_id], vector[777, 888]);
    world.approve_proposal(key);

    let mut executable = world.execute_proposal(key);
    world.execute_list<NFT>(&mut executable, &kiosk_owner_lock);
    k_kiosk::complete_list(executable);
    
    destroy(kiosk_owner_lock);        
    destroy(policy);
    destroy(policy_cap);
    destroy(sender_kiosk);
    destroy(sender_cap);
    world.end();
}

#[test, expected_failure(abort_code = k_kiosk::EListAllNftsBefore)]
fun destroy_list_error_list_all_nfts_before() {
    let mut world = start_world();

    let kiosk_owner_lock = world.borrow_lock();
    let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

    let nft = new_nft(world.scenario().ctx());
    let nft2 = new_nft(world.scenario().ctx());
    let nft_id = object::id(&nft);
    let nft_id2 = object::id(&nft2);

    let (mut policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());
    royalty_rule::add(&mut policy, &policy_cap, 500, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);

    sender_kiosk.place(&sender_cap, nft);
    sender_kiosk.place(&sender_cap, nft2);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id, &mut policy);
    world.place(&kiosk_owner_lock, &mut sender_kiosk, &sender_cap, nft_id2, &mut policy);

    world.scenario().next_tx(OWNER);
    let key = b"list proposal".to_string();
    world.propose_list(key, b"".to_string(), vector[nft_id, nft_id2], vector[777, 993]);
    world.approve_proposal(key);

    let executable = world.execute_proposal(key);
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