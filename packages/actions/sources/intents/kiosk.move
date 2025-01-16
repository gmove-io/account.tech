module account_actions::kiosk_intents;

// === Imports ===

use std::{
    string::String,
};
use sui::{
    kiosk::{Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
};
use account_actions::{
    kiosk as acc_kiosk,
    version,
};

// === Errors ===

#[error]
const ENoLock: vector<u8> = b"No Kiosk found with this name";
#[error]
const ENftsPricesNotSameLength: vector<u8> = b"Nfts prices vectors must have the same length";

// === Structs ===

/// [PROPOSAL] witness defining the proposal to take nfts from a kiosk managed by a account
public struct TakeIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to list nfts in a kiosk managed by a account
public struct ListIntent() has copy, drop;

// === [PROPOSAL] Public functions ===

// step 1: propose to transfer nfts to another kiosk
public fun request_take<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    kiosk_name: String,
    nft_ids: vector<ID>,
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);

    let mut intent = account.create_intent(
        auth, 
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        TakeIntent(),
        kiosk_name,
        ctx
    );

    nft_ids.do!(|nft_id| acc_kiosk::new_take(&mut intent, nft_id, recipient, TakeIntent()));
    account.add_intent(intent, version::current(), TakeIntent());
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
    acc_kiosk::do_take(executable, account, account_kiosk, recipient_kiosk, recipient_cap, policy, version::current(), TakeIntent(), ctx)
}

// step 5: destroy the executable
public fun complete_take<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), TakeIntent());
}

// step 1: propose to list nfts
public fun request_list<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    kiosk_name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>,
    ctx: &mut TxContext
) {
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        ListIntent(),
        kiosk_name,
        ctx
    );

    nft_ids.zip_do!(prices, |nft_id, price| acc_kiosk::new_list(&mut intent, nft_id, price, ListIntent()));
    account.add_intent(intent, version::current(), ListIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: list last nft in action
public fun execute_list<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
) {
    acc_kiosk::do_list<Config, Outcome, Nft, ListIntent>(executable, account, kiosk, version::current(), ListIntent());
}

// step 5: destroy the executable
public fun complete_list<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), ListIntent());
}