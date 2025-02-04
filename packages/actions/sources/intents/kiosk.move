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
public struct TakeNftsIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to list nfts in a kiosk managed by a account
public struct ListNftsIntent() has copy, drop;

// === [PROPOSAL] Public functions ===

// step 1: propose to transfer nfts to another kiosk
public fun request_take_nfts<Config, Outcome>(
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
    account.verify(auth);
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        kiosk_name,
        outcome,
        version::current(),
        TakeNftsIntent(),
        ctx
    );

    nft_ids.do!(|nft_id| 
        acc_kiosk::new_take(&mut intent, account, kiosk_name, nft_id, recipient, version::current(), TakeNftsIntent())
    );
    account.add_intent(intent, version::current(), TakeNftsIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
public fun execute_take_nfts<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    acc_kiosk::do_take(executable, account, account_kiosk, recipient_kiosk, recipient_cap, policy, version::current(), TakeNftsIntent(), ctx)
}

// step 5: destroy the executable
public fun complete_take_nfts<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), TakeNftsIntent());
}

// step 1: propose to list nfts
public fun request_list_nfts<Config, Outcome>(
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
    account.verify(auth);
    assert!(acc_kiosk::has_lock(account, kiosk_name), ENoLock);
    assert!(nft_ids.length() == prices.length(), ENftsPricesNotSameLength);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        kiosk_name,
        outcome,
        version::current(),
        ListNftsIntent(),
        ctx
    );

    nft_ids.zip_do!(prices, |nft_id, price| 
        acc_kiosk::new_list(&mut intent, account, kiosk_name, nft_id, price, version::current(), ListNftsIntent())
    );
    account.add_intent(intent, version::current(), ListNftsIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: list last nft in action
public fun execute_list_nfts<Config, Outcome, Nft: key + store>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    kiosk: &mut Kiosk,
) {
    acc_kiosk::do_list<_, _, Nft, _>(executable, account, kiosk, version::current(), ListNftsIntent());
}

// step 5: destroy the executable
public fun complete_list_nfts<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), ListNftsIntent());
}