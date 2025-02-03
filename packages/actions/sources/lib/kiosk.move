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
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

#[error]
const EWrongReceiver: vector<u8> = b"Caller is not the approved recipient";
#[error]
const ENoLock: vector<u8> = b"No Kiosk found with this name";
#[error]
const EAlreadyExists: vector<u8> = b"There already is a Kiosk with this name";

// === Structs ===    

/// Dynamic Object Field key for the KioskOwnerCap
public struct KioskOwnerKey has copy, drop, store { name: String }

/// [ACTION] struct transferring nfts from the account's kiosk to another one
public struct TakeAction has store {
    // name of the Kiosk
    name: String,
    // id of the nfts to transfer
    nft_id: ID,
    // owner of the receiver kiosk
    recipient: address,
}
/// [ACTION] struct listing nfts for purchase
public struct ListAction has store {
    // name of the Kiosk
    name: String,
    // id of the nft to list
    nft_id: ID,
    // listing price of the nft
    price: u64
}

// === [COMMAND] Public functions ===

/// Creates a new Kiosk and locks the KioskOwnerCap in the Account
/// Only a member can create a Kiosk
#[allow(lint(share_owned))]
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    name: String, 
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(!has_lock<Config, Outcome>(account, name), EAlreadyExists);

    let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);
    kiosk.set_owner_custom(&kiosk_owner_cap, account.addr());

    account.add_managed_object(KioskOwnerKey { name }, kiosk_owner_cap, version::current());
    transfer::public_share_object(kiosk);
}

public fun has_lock<Config, Outcome>(
    account: &Account<Config, Outcome>,
    name: String
): bool {
    account.has_managed_object(KioskOwnerKey { name })
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
    account.verify(auth);
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
public fun delist<Config, Outcome, Nft: key + store>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    kiosk: &mut Kiosk, 
    name: String,
    nft_id: ID,
) {
    account.verify(auth);
    assert!(has_lock(account, name), ENoLock);

    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());
    kiosk.delist<Nft>(cap, nft_id);
}

/// Members can withdraw the profits to the account
public fun withdraw_profits<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
    name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(has_lock(account, name), ENoLock);

    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version::current());

    let profits_mut = kiosk.profits_mut(cap);
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
    account.verify(auth);
    assert!(has_lock(account, name), ENoLock);

    let cap: KioskOwnerCap = account.remove_managed_object(KioskOwnerKey { name }, version::current());
    let profits = kiosk.close_and_withdraw(cap, ctx);
    
    account.keep(profits);
}

// === [ACTION] Public functions ===

public fun new_take<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>, 
    name: String,
    nft_id: ID, 
    recipient: address,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, TakeAction { name, nft_id, recipient }, version_witness, intent_witness);
}

public fun do_take<Config, Outcome, Nft: key + store, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    let action: &TakeAction = account.process_action(executable, version_witness, intent_witness);
    assert!(action.recipient == ctx.sender(), EWrongReceiver);
    let name = action.name;
    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version_witness);

    account_kiosk.list<Nft>(cap, action.nft_id, 0);
    let (nft, mut request) = account_kiosk.purchase<Nft>(action.nft_id, coin::zero<SUI>(ctx));

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

public fun delete_take(expired: &mut Expired) {
    let TakeAction { .. } = expired.remove_action();
}

public fun new_list<Config, Outcome, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>, 
    name: String,
    nft_id: ID, 
    price: u64,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, ListAction { name, nft_id, price }, version_witness, intent_witness);
}

public fun do_list<Config, Outcome, Nft: key + store, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,  
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action: &ListAction = account.process_action(executable, version_witness, intent_witness);
    let name = action.name;
    let cap: &KioskOwnerCap = account.borrow_managed_object(KioskOwnerKey { name }, version_witness);

    kiosk.list<Nft>(cap, action.nft_id, action.price);
}

public fun delete_list(expired: &mut Expired) {
    let ListAction { .. } = expired.remove_action();
}
