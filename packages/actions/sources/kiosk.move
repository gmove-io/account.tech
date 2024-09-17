/// Members can place nfts from their kiosk into the multisig's without approval.
/// Nfts can be transferred into any other Kiosk. Upon approval, the recipient must execute the transfer.
/// The functions take the caller's kiosk and the multisig's kiosk to execute.
/// Nfts can be listed for sale in the kiosk, and then purchased by anyone.
/// The multisig can withdraw the profits from the kiosk.

module kraken_actions::kiosk;

// === Imports ===

use std::string::String;
use sui::{
    coin,
    sui::SUI,
    kiosk::{Self, Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
    vec_map::{Self, VecMap},
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};

// === Errors ===

const EWrongReceiver: u64 = 1;
const ETransferAllNftsBefore: u64 = 2;
const EWrongNftsPrices: u64 = 3;
const EListAllNftsBefore: u64 = 4;

// === Structs ===    

// df key for the KioskOwnerLock
public struct KioskOwnerKey has copy, drop, store { name: String }

// Wrapper restricting access to a KioskOwnerCap
public struct KioskOwnerLock has store {
    // the cap to lock
    kiosk_owner_cap: KioskOwnerCap,
}

// [MEMBER] can create a Kiosk and lock the KioskOwnerCap in the Multisig to restrict taking and listing operations
public struct ManageKiosk has copy, drop {}
// [PROPOSAL] take nfts from a kiosk managed by a multisig
public struct TakeProposal has copy, drop {}
// [PROPOSAL] list nfts in a kiosk managed by a multisig
public struct ListProposal has copy, drop {}

// [ACTION] transfer nfts from the multisig's kiosk to another one
public struct TakeAction has store {
    // id of the nfts to transfer
    nft_ids: vector<ID>,
    // owner of the receiver kiosk
    recipient: address,
}

// [ACTION] list nfts for purchase
public struct ListAction has store {
    // name of the kiosk
    name: String,
    // id of the nfts to list to the prices
    nfts_prices_map: VecMap<ID, u64>
}

// === [MEMBER] Public functions ===

// not composable because of the lock
#[allow(lint(share_owned))]
public fun new(multisig: &mut Multisig, name: String, ctx: &mut TxContext) {
    multisig.assert_is_member(ctx);
    let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&kiosk_owner_cap, multisig.addr());

    let kiosk_owner_lock = KioskOwnerLock { kiosk_owner_cap };
    multisig.add_managed_asset(ManageKiosk {}, KioskOwnerKey { name }, kiosk_owner_lock);

    transfer::public_share_object(kiosk);
}

public fun borrow_lock(multisig: &Multisig, name: String): &KioskOwnerLock {
    multisig.borrow_managed_asset(ManageKiosk {}, KioskOwnerKey { name })
}

public fun borrow_lock_mut(multisig: &mut Multisig, name: String): &mut KioskOwnerLock {
    multisig.borrow_managed_asset_mut(ManageKiosk {}, KioskOwnerKey { name })
}

// deposit from another Kiosk, no need for proposal
// only doable if there is maximum a royalty and lock rule for the type
public fun place<O: key + store>(
    multisig: &mut Multisig, 
    multisig_kiosk: &mut Kiosk, 
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    name: String,
    nft_id: ID,
    policy: &mut TransferPolicy<O>,
    ctx: &mut TxContext
): TransferRequest<O> {
    multisig.assert_is_member(ctx);
    let lock_mut = borrow_lock_mut(multisig, name);

    sender_kiosk.list<O>(sender_cap, nft_id, 0);
    let (nft, mut request) = sender_kiosk.purchase<O>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<O, kiosk_lock_rule::Rule>()) {
        multisig_kiosk.lock(&lock_mut.kiosk_owner_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, multisig_kiosk);
    } else {
        multisig_kiosk.place(&lock_mut.kiosk_owner_cap, nft);
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
    name: String,
    nft: ID,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let lock_mut = borrow_lock_mut(multisig, name);
    kiosk.delist<O>(&lock_mut.kiosk_owner_cap, nft);
}

// members can withdraw the profits to the multisig
public fun withdraw_profits(
    multisig: &mut Multisig,
    kiosk: &mut Kiosk,
    name: String,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let lock_mut = borrow_lock_mut(multisig, name);

    let profits_mut = kiosk.profits_mut(&lock_mut.kiosk_owner_cap);
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
        TakeProposal {},
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_take(proposal_mut, nft_ids, recipient);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
public fun execute_take<O: key + store>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    multisig_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<O>,
    ctx: &mut TxContext
): TransferRequest<O> {
    take(executable, multisig, multisig_kiosk, recipient_kiosk, recipient_cap, policy, TakeProposal {}, ctx)
}

// step 5: destroy the executable, must `put_back_cap()`
public fun complete_take(mut executable: Executable) {
    destroy_take(&mut executable, TakeProposal {});
    executable.destroy(TakeProposal {});
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
        ListProposal {},
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
    multisig: &mut Multisig,
    kiosk: &mut Kiosk,
) {
    list<O, ListProposal>(executable, multisig, kiosk, ListProposal {});
}

// step 5: destroy the executable, must `put_back_cap()`
public fun complete_list(mut executable: Executable) {
    destroy_list(&mut executable, ListProposal {});
    executable.destroy(ListProposal {});
}

// === [ACTION] Public functions ===

public fun new_take(
    proposal: &mut Proposal, 
    nft_ids: vector<ID>, 
    recipient: address
) {
    proposal.add_action(TakeAction { nft_ids, recipient });
}

public fun take<O: key + store, W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    multisig_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<O>,
    witness: W,
    ctx: &mut TxContext
): TransferRequest<O> {
    let name = executable.auth().name();
    let take_mut: &mut TakeAction = executable.action_mut(witness, multisig.addr());
    let lock_mut = borrow_lock_mut(multisig, name);
    assert!(take_mut.recipient == ctx.sender(), EWrongReceiver);

    let nft_id = take_mut.nft_ids.remove(0);
    multisig_kiosk.list<O>(&lock_mut.kiosk_owner_cap, nft_id, 0);
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

public fun destroy_take<W: copy + drop>(executable: &mut Executable, witness: W): address {
    let TakeAction { nft_ids, recipient, .. } = executable.remove_action(witness);
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
    proposal.add_action(ListAction { name, nfts_prices_map: vec_map::from_keys_values(nft_ids, prices) });
}

public fun list<O: key + store, W: copy + drop>(
    executable: &mut Executable,
    multisig: &mut Multisig,
    kiosk: &mut Kiosk,
    witness: W,
) {
    let name = executable.auth().name();
    let list_mut: &mut ListAction = executable.action_mut(witness, multisig.addr());
    let lock_mut = borrow_lock_mut(multisig, name);

    let (nft_id, price) = list_mut.nfts_prices_map.remove_entry_by_idx(0);
    kiosk.list<O>(&lock_mut.kiosk_owner_cap, nft_id, price);
}

public fun destroy_list<W: copy + drop>(executable: &mut Executable, witness: W) {
    let ListAction { nfts_prices_map, .. } = executable.remove_action(witness);
    assert!(nfts_prices_map.is_empty(), EListAllNftsBefore);
}
