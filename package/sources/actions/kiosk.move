/// Members can place nfts from their kiosk into the multisig's without approval.
/// Nfts can be transferred into any other Kiosk. Upon approval, the recipient must execute the transfer.
/// The functions take the caller's kiosk and the multisig's kiosk to execute.
/// Nfts can be listed for sale in the kiosk, and then purchased by anyone.
/// The multisig can withdraw the profits from the kiosk.

module kraken::kiosk;

// === Imports ===

use std::string::String;
use sui::{
    coin,
    transfer::Receiving,
    sui::SUI,
    kiosk::{Self, Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
    vec_map::{Self, VecMap},
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use kraken::multisig::{Multisig, Executable, Proposal};

// === Errors ===

const EWrongReceiver: u64 = 1;
const ETransferAllNftsBefore: u64 = 2;
const EWrongNftsPrices: u64 = 3;
const EListAllNftsBefore: u64 = 4;
const EWrongKiosk: u64 = 5;

// === Structs ===    

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// Wrapper restricting access to a KioskOwnerCap
// doesn't have store because non-transferrable
public struct KioskOwnerLock has key {
    id: UID,
    // name of the kiosk, used for roles
    name: String,
    // multisig owning the lock
    multisig_addr: address,
    // the cap to lock
    kiosk_owner_cap: KioskOwnerCap,
}

// [ACTION] transfer nfts from the multisig's kiosk to another one
public struct Take has store {
    // name of the kiosk
    name: String,
    // id of the nfts to transfer
    nft_ids: vector<ID>,
    // owner of the receiver kiosk
    recipient: address,
}

// [ACTION] list nfts for purchase
public struct List has store {
    // name of the kiosk
    name: String,
    // id of the nfts to list to the prices
    nfts_prices_map: VecMap<ID, u64>
}

// === [MEMBER] Public functions ===

// not composable because of the lock
#[allow(lint(share_owned))]
public fun new(multisig: &Multisig, name: String, ctx: &mut TxContext) {
    multisig.assert_is_member(ctx);
    let (mut kiosk, cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&cap, multisig.addr());

    let kiosk_owner_lock = KioskOwnerLock {
        id: object::new(ctx), 
        name,
        multisig_addr: multisig.addr(),
        kiosk_owner_cap: cap 
    };

    transfer::public_share_object(kiosk);
    transfer::transfer(
        kiosk_owner_lock, 
        multisig.addr()
    );
}

// borrow the lock that can only be put back in the multisig because no store
public fun borrow_lock(
    multisig: &mut Multisig, 
    kiosk_owner_lock: Receiving<KioskOwnerLock>,
    ctx: &mut TxContext
): KioskOwnerLock {
    multisig.assert_is_member(ctx);
    transfer::receive(multisig.uid_mut(), kiosk_owner_lock)
}

public fun put_back_lock(kiosk_owner_lock: KioskOwnerLock) {
    let addr = kiosk_owner_lock.multisig_addr;
    transfer::transfer(kiosk_owner_lock, addr);
}

// deposit from another Kiosk, no need for proposal
// only doable if there is maximum a royalty and lock rule for the type
public fun place<O: key + store>(
    multisig: &mut Multisig, 
    multisig_kiosk: &mut Kiosk, 
    lock: &KioskOwnerLock,
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    nft_id: ID,
    policy: &mut TransferPolicy<O>,
    ctx: &mut TxContext
): TransferRequest<O> {
    multisig.assert_is_member(ctx);

    sender_kiosk.list<O>(sender_cap, nft_id, 0);
    let (nft, mut request) = sender_kiosk.purchase<O>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<O, kiosk_lock_rule::Rule>()) {
        multisig_kiosk.lock(&lock.kiosk_owner_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, multisig_kiosk);
    } else {
        multisig_kiosk.place(&lock.kiosk_owner_cap, nft);
    };

    if (policy.has_rule<O, royalty_rule::Rule>()) {
        royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
    }; 

    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

// members can delist nfts
public fun delist<O: key + store>(
    multisig: &mut Multisig, 
    kiosk: &mut Kiosk, 
    lock: &KioskOwnerLock,
    nft: ID,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    kiosk.delist<O>(&lock.kiosk_owner_cap, nft);
}

// members can withdraw the profits to the multisig
public fun withdraw_profits(
    multisig: &mut Multisig,
    kiosk: &mut Kiosk,
    lock: &KioskOwnerLock,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let profits_mut = kiosk.profits_mut(&lock.kiosk_owner_cap);
    let profits_value = profits_mut.value();
    let profits = profits_mut.split(profits_value);

    transfer::public_transfer(
        coin::from_balance<SUI>(profits, ctx), 
        multisig.addr()
    );
}

// === [PROPOSAL] Public functions ===

// step 1: propose to transfer nfts to another kiosk
public fun propose_take(
    multisig: &mut Multisig,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    nft_ids: vector<ID>,
    recipient: address,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_take(proposal_mut, name, nft_ids, recipient);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
public fun execute_take<O: key + store>(
    executable: &mut Executable,
    multisig: &Multisig,
    multisig_kiosk: &mut Kiosk, 
    lock: &KioskOwnerLock,
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<O>,
    ctx: &mut TxContext
): TransferRequest<O> {
    take(executable, multisig, multisig_kiosk, lock, recipient_kiosk, recipient_cap, policy, Issuer {}, ctx)
}

// step 5: destroy the executable, must `put_back_cap()`
public fun complete_take(mut executable: Executable) {
    destroy_take(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to list nfts
public fun propose_list(
    multisig: &mut Multisig,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_list(proposal_mut, name, nft_ids, prices);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: list last nft in action
public fun execute_list<O: key + store>(
    executable: &mut Executable,
    multisig: &Multisig,
    kiosk: &mut Kiosk,
    lock: &KioskOwnerLock,
) {
    list<O, Issuer>(executable, multisig, kiosk, lock, Issuer {});
}

// step 5: destroy the executable, must `put_back_cap()`
public fun complete_list(mut executable: Executable) {
    destroy_list(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// === [ACTION] Public functions ===

public fun new_take(
    proposal: &mut Proposal, 
    name: String, 
    nft_ids: vector<ID>, 
    recipient: address
) {
    proposal.add_action(Take { name, nft_ids, recipient });
}

public fun take<O: key + store, I: copy + drop>(
    executable: &mut Executable,
    multisig: &Multisig,
    multisig_kiosk: &mut Kiosk, 
    lock: &KioskOwnerLock,
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<O>,
    issuer: I,
    ctx: &mut TxContext
): TransferRequest<O> {
    let take_mut: &mut Take = executable.action_mut(issuer, multisig.addr());
    assert!(take_mut.name == lock.name, EWrongKiosk);
    assert!(take_mut.recipient == ctx.sender(), EWrongReceiver);

    let nft_id = take_mut.nft_ids.pop_back();
    multisig_kiosk.list<O>(&lock.kiosk_owner_cap, nft_id, 0);
    let (nft, mut request) = multisig_kiosk.purchase<O>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<O, kiosk_lock_rule::Rule>()) {
        recipient_kiosk.lock(recipient_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, recipient_kiosk);
    } else {
        recipient_kiosk.place(recipient_cap, nft);
    };

    if (policy.has_rule<O, royalty_rule::Rule>()) {
        royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
    }; 

    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

public fun destroy_take<I: copy + drop>(executable: &mut Executable, issuer: I): address {
    let Take { name: _, nft_ids, recipient } = executable.remove_action(issuer);
    assert!(nft_ids.is_empty(), ETransferAllNftsBefore);
    recipient
}

public fun new_list(
    proposal: &mut Proposal, 
    name: String, 
    nft_ids: vector<ID>, 
    prices: vector<u64>
) {
    assert!(nft_ids.length() == prices.length(), EWrongNftsPrices);
    proposal.add_action(List { name, nfts_prices_map: vec_map::from_keys_values(nft_ids, prices) });
}

public fun list<O: key + store, I: copy + drop>(
    executable: &mut Executable,
    multisig: &Multisig,
    kiosk: &mut Kiosk,
    lock: &KioskOwnerLock,
    issuer: I,
) {
    let list_mut: &mut List = executable.action_mut(issuer, multisig.addr());
    assert!(list_mut.name == lock.name, EWrongKiosk);
    let (nft_id, price) = list_mut.nfts_prices_map.remove_entry_by_idx(0);
    kiosk.list<O>(&lock.kiosk_owner_cap, nft_id, price);
}

public fun destroy_list<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let List { name: _, nfts_prices_map } = executable.remove_action(issuer);
    assert!(nfts_prices_map.is_empty(), EListAllNftsBefore);
}
