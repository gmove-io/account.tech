/// Members can place nfts from their kiosk into the account's without approval.
/// Nfts can be proposed for transfer into any other Kiosk. Upon approval, the recipient must execute the transfer.
/// The functions take the caller's kiosk and the account's kiosk to execute.
/// Nfts can be listed for sale in the kiosk, and then purchased by anyone.
/// Members can withdraw the profits from the kiosk to the Account.

module account_actions::kiosk;

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
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};

// === Errors ===

#[error]
const EWrongReceiver: vector<u8> = b"Caller is not the approved recipient";
#[error]
const ETransferAllNftsBefore: vector<u8> = b"Transfer all nfts before destroying the action";
#[error]
const ENftsPricesNotSameLength: vector<u8> = b"Nfts prices vectors must have the same length";
#[error]
const EListAllNftsBefore: vector<u8> = b"List all nfts before destroying the action";
#[error]
const ENoLock: vector<u8> = b"No Kiosk found with this name";

// === Structs ===    

/// Dynamic Field key for the KioskOwnerLock
public struct KioskOwnerKey has copy, drop, store { name: String }
/// Dynamic Field wrapper restricting access to a KioskOwnerCap
public struct KioskOwnerLock has store {
    // the cap to lock
    kiosk_owner_cap: KioskOwnerCap,
}

/// [MEMBER] can place into a Kiosk
public struct Place() has drop;
/// [MEMBER] can delist from a Kiosk
public struct Delist() has drop;
/// [PROPOSAL] take nfts from a kiosk managed by a account
public struct TakeProposal() has drop;
/// [PROPOSAL] list nfts in a kiosk managed by a account
public struct ListProposal() has drop;

/// [ACTION] transfer nfts from the account's kiosk to another one
public struct TakeAction has store {
    // id of the nfts to transfer
    nft_ids: vector<ID>,
    // owner of the receiver kiosk
    recipient: address,
}
/// [ACTION] list nfts for purchase
public struct ListAction has store {
    // name of the account's kiosk
    name: String,
    // id of the nfts to list to the prices
    nfts_prices_map: VecMap<ID, u64>
}

// === [MEMBER] Public functions ===

/// Creates a new Kiosk and locks the KioskOwnerCap in the Account
/// Only a member can create a Kiosk
#[allow(lint(share_owned))]
public fun new<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    name: String, 
    ctx: &mut TxContext
) {
    auth.verify(account.addr());

    let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&kiosk_owner_cap, account.addr());

    let kiosk_owner_lock = KioskOwnerLock { kiosk_owner_cap };
    account.add_managed_asset(KioskOwnerKey { name }, kiosk_owner_lock);

    transfer::public_share_object(kiosk);
}

public fun has_lock<Config, Outcome>(
    account: &Account<Config, Outcome>,
    name: String
): bool {
    account.has_managed_asset(KioskOwnerKey { name })
}

public fun borrow_lock<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): &KioskOwnerLock {
    account.borrow_managed_asset(KioskOwnerKey { name })
}

public fun borrow_lock_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    name: String
): &mut KioskOwnerLock {
    account.borrow_managed_asset_mut(KioskOwnerKey { name })
}

/// Deposits from another Kiosk, no need for proposal.
/// Optional royalty and lock rules are automatically resolved for the type.
/// The rest of the rules must be confirmed via the frontend.
public fun place<Config, Outcome, Nft: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    account_kiosk: &mut Kiosk, 
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    name: String,
    nft_id: ID,
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    auth.verify_with_role<Place>(account.addr(), name);
    let lock_mut = borrow_lock_mut(account, name);

    sender_kiosk.list<Nft>(sender_cap, nft_id, 0);
    let (nft, mut request) = sender_kiosk.purchase<Nft>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<Nft, kiosk_lock_rule::Rule>()) {
        account_kiosk.lock(&lock_mut.kiosk_owner_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, account_kiosk);
    } else {
        account_kiosk.place(&lock_mut.kiosk_owner_cap, nft);
    };

    if (policy.has_rule<Nft, royalty_rule::Rule>()) {
        royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
    }; 

    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

/// Members with role can delist nfts
public fun delist<Config, Outcome, Nft: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    kiosk: &mut Kiosk, 
    name: String,
    nft: ID,
) {
    auth.verify_with_role<Delist>(account.addr(), name);
    let lock_mut = borrow_lock_mut(account, name);
    kiosk.delist<Nft>(&lock_mut.kiosk_owner_cap, nft);
}

/// Members can withdraw the profits to the account
public fun withdraw_profits<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
    name: String,
    ctx: &mut TxContext
) {
    auth.verify(account.addr());
    let lock_mut = borrow_lock_mut(account, name);

    let profits_mut = kiosk.profits_mut(&lock_mut.kiosk_owner_cap);
    let profits_value = profits_mut.value();
    let profits = profits_mut.split(profits_value);

    transfer::public_transfer(
        coin::from_balance<SUI>(profits, ctx), 
        account.addr()
    );
}

// === [PROPOSAL] Public functions ===

// step 1: propose to transfer nfts to another kiosk
public fun propose_take<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    nft_ids: vector<ID>,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, name), ENoLock);

    let mut proposal = account.create_proposal(
        auth, 
        outcome,
        TakeProposal(),
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_take(&mut proposal, nft_ids, recipient, TakeProposal());
    account.add_proposal(proposal, TakeProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
public fun execute_take<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    take(executable, account, account_kiosk, recipient_kiosk, recipient_cap, policy, TakeProposal(), ctx)
}

// step 5: destroy the executable
public fun complete_take(mut executable: Executable) {
    destroy_take(&mut executable, TakeProposal());
    executable.destroy(TakeProposal());
}

// step 1: propose to list nfts
public fun propose_list<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, name), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        ListProposal(),
        name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_list(&mut proposal, name, nft_ids, prices, ListProposal());
    account.add_proposal(proposal, ListProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: list last nft in action
public fun execute_list<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
) {
    list<Config, Outcome, Nft, ListProposal>(executable, account, kiosk, ListProposal());
}

// step 5: destroy the executable
public fun complete_list(mut executable: Executable) {
    destroy_list(&mut executable, ListProposal());
    executable.destroy(ListProposal());
}

// === [ACTION] Public functions ===

public fun new_take<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    nft_ids: vector<ID>, 
    recipient: address,
    witness: W,
) {
    proposal.add_action(TakeAction { nft_ids, recipient }, witness);
}

public fun take<Config, Outcome, Nft: key + store, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    witness: W,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    let name = executable.source().role_name();
    let take_mut: &mut TakeAction = executable.action_mut(account.addr(), witness);
    let lock_mut = borrow_lock_mut(account, name);
    assert!(take_mut.recipient == ctx.sender(), EWrongReceiver);

    let nft_id = take_mut.nft_ids.remove(0);
    account_kiosk.list<Nft>(&lock_mut.kiosk_owner_cap, nft_id, 0);
    let (nft, mut request) = account_kiosk.purchase<Nft>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<Nft, kiosk_lock_rule::Rule>()) {
        recipient_kiosk.lock(recipient_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, recipient_kiosk);
    } else {
        recipient_kiosk.place(recipient_cap, nft);
    };

    if (policy.has_rule<Nft, royalty_rule::Rule>()) {
        royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
    }; 

    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

public fun destroy_take<W: drop>(executable: &mut Executable, witness: W): address {
    let TakeAction { nft_ids, recipient, .. } = executable.remove_action(witness);
    assert!(nft_ids.is_empty(), ETransferAllNftsBefore);
    recipient
}

public fun delete_take_action<Outcome>(expired: &mut Expired<Outcome>) {
    let TakeAction { .. } = expired.remove_expired_action();
}

public fun new_list<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    name: String, 
    nft_ids: vector<ID>, 
    prices: vector<u64>,
    witness: W,
) {
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);
    proposal.add_action(
        ListAction { name, nfts_prices_map: vec_map::from_keys_values(nft_ids, prices) }, 
        witness
    );
}

public fun list<Config, Outcome, Nft: key + store, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
    witness: W,
) {
    let name = executable.source().role_name();
    let list_mut: &mut ListAction = executable.action_mut(account.addr(), witness);
    let lock_mut = borrow_lock_mut(account, name);

    let (nft_id, price) = list_mut.nfts_prices_map.remove_entry_by_idx(0);
    kiosk.list<Nft>(&lock_mut.kiosk_owner_cap, nft_id, price);
}

public fun destroy_list<W: drop>(executable: &mut Executable, witness: W) {
    let ListAction { nfts_prices_map, .. } = executable.remove_action(witness);
    assert!(nfts_prices_map.is_empty(), EListAllNftsBefore);
}

public fun delete_list_action<Outcome>(expired: &mut Expired<Outcome>) {
    let ListAction { .. } = expired.remove_expired_action();
}
