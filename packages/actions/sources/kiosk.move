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
};
use kiosk::{kiosk_lock_rule, royalty_rule, personal_kiosk_rule};
use account_protocol::{
    account::Account,
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

public struct Witness() has drop;

/// Dynamic Object Field key for the KioskOwnerCap
public struct KioskOwnerKey has copy, drop, store { name: String }

/// [ACTION] struct transferring nfts from the account's kiosk to another one
public struct TakeAction has drop, store {
    // id of the nfts to transfer
    nft_ids: vector<ID>,
    // owner of the receiver kiosk
    recipient: address,
}
/// [ACTION] struct listing nfts for purchase
public struct ListAction has drop, store {
    // id of the nft to list
    nft_ids: vector<ID>,
    // listing price of the nft
    prices: vector<u64>
}

// === [COMMAND] Public functions ===

/// Creates a new Kiosk and locks the KioskOwnerCap in the Account
/// Only a member can create a Kiosk
#[allow(lint(share_owned))]
public fun open<Config>(
    auth: Auth,
    account: &mut Account<Config>, 
    name: String, 
    ctx: &mut TxContext
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(!has_lock<Config>(account, name), EAlreadyExists);

    let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&kiosk_owner_cap, account.addr());

    account.add_managed_object(KioskOwnerKey { name }, kiosk_owner_cap, version::current());
    transfer::public_share_object(kiosk);
}

public fun has_lock<Config>(
    account: &Account<Config>,
    name: String
): bool {
    account.has_managed_object(KioskOwnerKey { name })
}

/// Deposits from another Kiosk, no need for proposal.
/// Optional royalty and lock rules are automatically resolved for the type.
/// The rest of the rules must be confirmed via the frontend.
public fun place<Config, Nft: key + store>(
    auth: Auth,
    account: &mut Account<Config>, 
    account_kiosk: &mut Kiosk, 
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    name: String,
    nft_id: ID,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(has_lock(account, name), ENoLock);

    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());

    sender_kiosk.list<Nft>(sender_cap, nft_id, 0);
    let (nft, mut request) = sender_kiosk.purchase<Nft>(nft_id, coin::zero<SUI>(ctx));

    if (policy.has_rule<Nft, kiosk_lock_rule::Rule>()) {
        account_kiosk.lock(cap, policy, nft);
        kiosk_lock_rule::prove(&mut request, account_kiosk);
    } else {
        account_kiosk.place(cap, nft);
    };

    if (policy.has_rule<Nft, royalty_rule::Rule>()) {
        // can't read royalty rule on-chain because transfer_policy::get_rule not implemented
        // so we can't throw an error if there is a minimum floor price set
        royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
    }; 

    if (policy.has_rule<Nft, personal_kiosk_rule::Rule>()) {
        personal_kiosk_rule::prove(account_kiosk, &mut request);
    };
    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

/// Members with role can delist nfts
public fun delist<Config, Nft: key + store>(
    auth: Auth,
    account: &mut Account<Config>, 
    kiosk: &mut Kiosk, 
    name: String,
    nft_id: ID,
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(has_lock(account, name), ENoLock);

    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());
    kiosk.delist<Nft>(cap, nft_id);
}

/// Members can withdraw the profits to the account
public fun withdraw_profits<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    kiosk: &mut Kiosk,
    name: String,
    ctx: &mut TxContext
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(has_lock(account, name), ENoLock);

    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());

    let profits_mut = kiosk.profits_mut(cap);
    let profits_value = profits_mut.value();
    let profits = profits_mut.split(profits_value);

    account.keep(coin::from_balance<SUI>(profits, ctx));
}

/// Closes the kiosk if empty
public fun close<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String,
    kiosk: Kiosk,
    ctx: &mut TxContext
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(has_lock(account, name), ENoLock);

    let cap: KioskOwnerCap = account.remove_managed_object(KioskOwnerKey { name }, version::current());
    let profits = kiosk.close_and_withdraw(cap, ctx);
    
    account.keep(profits);
}

// === [PROPOSAL] Public functions ===

// step 1: propose to transfer nfts to another kiosk
public fun request_take<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    kiosk_name: String,
    nft_ids: vector<ID>,
    recipient: address,
    outcome: Outcome,
) {
    assert!(has_lock(account, kiosk_name), ENoLock);

    let action = TakeAction { nft_ids, recipient };

    account.create_intent(
        auth, 
        key,
        description,
        execution_time,
        expiration_time,
        action,
        outcome,
        version::current(),
        Witness(),
        kiosk_name,
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
public fun execute_take<Config, Nft: key + store>(
    executable: &mut Executable<TakeAction>,
    account: &mut Account<Config>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    let name = executable.issuer().opt_name();
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    let nft_id = action_mut.nft_ids.remove(0);
    
    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());
    assert!(action_mut.recipient == ctx.sender(), EWrongReceiver);

    account_kiosk.list<Nft>(cap, nft_id, 0);
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

    if (policy.has_rule<Nft, personal_kiosk_rule::Rule>()) {
        personal_kiosk_rule::prove(account_kiosk, &mut request);
    };
    // the request can be filled with arbitrary rules and must be confirmed afterwards
    request
}

// step 5: destroy the executable
public fun complete_take(executable: Executable<TakeAction>) {
    executable.destroy(version::current(), Witness());
}

// step 1: propose to list nfts
public fun request_list<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    kiosk_name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    outcome: Outcome,
) {
    assert!(has_lock(account, kiosk_name), ENoLock);
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);

    let action = ListAction { nft_ids, prices };

    account.create_intent(
        auth,
        key,
        description,
        execution_time,
        expiration_time,
        action,
        outcome,
        version::current(),
        Witness(),
        kiosk_name,
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: list last nft in action
public fun execute_list<Config, Nft: key + store>(
    executable: &mut Executable<ListAction>,
    account: &mut Account<Config>,
    kiosk: &mut Kiosk,
) {
    let name = executable.issuer().opt_name();
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());

    kiosk.list<Nft>(cap, action_mut.nft_ids.remove(0), action_mut.prices.remove(0));
}

// step 5: destroy the executable
public fun complete_list(executable: Executable<ListAction>) {
    executable.destroy(version::current(), Witness());
}