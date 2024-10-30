/// Members can place nfts from their kiosk into the account's without approval.
/// Nfts can be proposed for transfer into any other Kiosk. Upon approval, the recipient must execute the transfer.
/// The functions take the caller's kiosk and the account's kiosk to execute.
/// Nfts can be listed for sale in the kiosk, and then purchased by anyone.
/// Members can withdraw the profits from the kiosk to the Account.

module account_actions::kiosk;

// === Imports ===

use std::{
    string::String,
    type_name::TypeName,
};
use sui::{
    coin,
    sui::SUI,
    kiosk::{Self, Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};
use account_actions::version;

// === Errors ===

#[error]
const EWrongReceiver: vector<u8> = b"Caller is not the approved recipient";
#[error]
const ENftsPricesNotSameLength: vector<u8> = b"Nfts prices vectors must have the same length";
#[error]
const ENoLock: vector<u8> = b"No Kiosk found with this name";
#[error]
const EAlreadyExists: vector<u8> = b"There already is a Kiosk with this name";

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
public struct TakeProposal() has copy, drop;
/// [PROPOSAL] list nfts in a kiosk managed by a account
public struct ListProposal() has copy, drop;

/// [ACTION] transfer nfts from the account's kiosk to another one
public struct TakeAction has store {
    // id of the nfts to transfer
    nft_id: ID,
    // owner of the receiver kiosk
    recipient: address,
}
/// [ACTION] list nfts for purchase
public struct ListAction has store {
    // id of the nft to list
    nft_id: ID,
    // listing price of the nft
    price: u64
}

// === [MEMBER] Public functions ===

/// Creates a new Kiosk and locks the KioskOwnerCap in the Account
/// Only a member can create a Kiosk
#[allow(lint(share_owned))]
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    name: String, 
    ctx: &mut TxContext
) {
    auth.verify(account.addr());
    assert!(!has_lock<Config, Outcome>(account, name), EAlreadyExists);

    let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&kiosk_owner_cap, account.addr());

    let kiosk_owner_lock = KioskOwnerLock { kiosk_owner_cap };
    account.add_managed_asset(KioskOwnerKey { name }, kiosk_owner_lock, version::current());

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
    account.borrow_managed_asset(KioskOwnerKey { name }, version::current())
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
    policy: &mut TransferPolicy<Nft>,
    name: String,
    nft_id: ID,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    auth.verify_with_role<Place>(account.addr(), name);
    assert!(has_lock(account, name), ENoLock);

    let lock_mut: &mut KioskOwnerLock = account.borrow_managed_asset_mut(KioskOwnerKey { name }, version::current());

    sender_kiosk.list<Nft>(sender_cap, nft_id, 0);
    let (nft, mut request) = sender_kiosk.purchase<Nft>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<Nft, kiosk_lock_rule::Rule>()) {
        account_kiosk.lock(&lock_mut.kiosk_owner_cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, account_kiosk);
    } else {
        account_kiosk.place(&lock_mut.kiosk_owner_cap, nft);
    };

    if (policy.has_rule<Nft, royalty_rule::Rule>()) {
        // can't read royalty rule on-chain because transfer_policy::get_rule not implemented
        // so we can't throw an error if there is a minimum floor price set
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
    assert!(has_lock(account, name), ENoLock);

    let lock_mut: &mut KioskOwnerLock = account.borrow_managed_asset_mut(KioskOwnerKey { name }, version::current());
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
    assert!(has_lock(account, name), ENoLock);

    let lock_mut: &mut KioskOwnerLock = account.borrow_managed_asset_mut(KioskOwnerKey { name }, version::current());

    let profits_mut = kiosk.profits_mut(&lock_mut.kiosk_owner_cap);
    let profits_value = profits_mut.value();
    let profits = profits_mut.split(profits_value);

    account.keep(coin::from_balance<SUI>(profits, ctx));
}

/// Closes the kiosk if empty
public fun close<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    kiosk: Kiosk,
    ctx: &mut TxContext
) {
    auth.verify(account.addr());
    assert!(has_lock(account, name), ENoLock);

    let KioskOwnerLock { kiosk_owner_cap } = 
        account.remove_managed_asset(KioskOwnerKey { name }, version::current());
    let profits = kiosk.close_and_withdraw(kiosk_owner_cap, ctx);
    
    account.keep(profits);
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
    kiosk_name: String,
    nft_ids: vector<ID>,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, kiosk_name), ENoLock);

    let mut proposal = account.create_proposal(
        auth, 
        outcome,
        version::current(),
        TakeProposal(),
        kiosk_name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    nft_ids.do!(|nft_id| new_take(&mut proposal, nft_id, recipient, TakeProposal()));
    account.add_proposal(proposal, version::current(), TakeProposal());
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
    do_take(executable, account, account_kiosk, recipient_kiosk, recipient_cap, policy, version::current(), TakeProposal(), ctx)
}

// step 5: destroy the executable
public fun complete_take(executable: Executable) {
    executable.destroy(version::current(), TakeProposal());
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
    kiosk_name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, kiosk_name), ENoLock);
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        ListProposal(),
        kiosk_name,
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    nft_ids.zip_do!(prices, |nft_id, price| new_list(&mut proposal, nft_id, price, ListProposal()));
    account.add_proposal(proposal, version::current(), ListProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: list last nft in action
public fun execute_list<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
) {
    do_list<Config, Outcome, Nft, ListProposal>(executable, account, kiosk, version::current(), ListProposal());
}

// step 5: destroy the executable
public fun complete_list(executable: Executable) {
    executable.destroy(version::current(), ListProposal());
}

// === [ACTION] Public functions ===

public fun new_take<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    nft_id: ID, 
    recipient: address,
    witness: W,
) {
    proposal.add_action(TakeAction { nft_id, recipient }, witness);
}

public fun do_take<Config, Outcome, Nft: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    version: TypeName,
    witness: W,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    let name = executable.issuer().role_name();
    let TakeAction { nft_id, recipient } = executable.action(account.addr(), version, witness);
    let lock_mut: &mut KioskOwnerLock = account.borrow_managed_asset_mut(KioskOwnerKey { name }, version);
    assert!(recipient == ctx.sender(), EWrongReceiver);

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

public fun delete_take_action<Outcome>(expired: &mut Expired<Outcome>) {
    let TakeAction { .. } = expired.remove_expired_action();
}

public fun new_list<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    nft_id: ID, 
    price: u64,
    witness: W,
) {
    proposal.add_action(ListAction { nft_id, price }, witness);
}

public fun do_list<Config, Outcome, Nft: key + store, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,  
    version: TypeName,
    witness: W,
) {
    let name = executable.issuer().role_name();
    let ListAction { nft_id, price } = executable.action(account.addr(), version, witness);
    let lock_mut: &mut KioskOwnerLock = account.borrow_managed_asset_mut(KioskOwnerKey { name }, version);

    kiosk.list<Nft>(&lock_mut.kiosk_owner_cap, nft_id, price);
}

public fun delete_list_action<Outcome>(expired: &mut Expired<Outcome>) {
    let ListAction { .. } = expired.remove_expired_action();
}
