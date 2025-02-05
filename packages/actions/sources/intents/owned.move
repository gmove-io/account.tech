module account_actions::owned_intents;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    owned,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    vault,
    version,
};

// === Errors ===

#[error]
const EObjectsRecipientsNotSameLength: vector<u8> = b"Recipients and objects vectors must have the same length";

// === Structs ===

/// [PROPOSAL] 
public struct WithdrawAndTransferToVaultIntent() has copy, drop;
/// [PROPOSAL] acc_transfer multiple objects
public struct WithdrawAndTransferIntent() has copy, drop;
/// [PROPOSAL] streams an amount of coin to be paid at specific intervals
public struct WithdrawAndVestIntent() has copy, drop;

// === [INTENT] Public functions ===

// step 1: propose to send owned objects
public fun request_withdraw_and_transfer_to_vault<Config, Outcome, CoinType: drop>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID,
    coin_amount: u64,
    vault_name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        ctx
    );

    owned::new_withdraw(
        &mut intent, account, coin_id, version::current(), WithdrawAndTransferToVaultIntent()
    );
    vault::new_deposit<_, _, CoinType, _>(
        &mut intent, account, vault_name, coin_amount, version::current(), WithdrawAndTransferToVaultIntent()
    );

    account.add_intent(intent, version::current(), WithdrawAndTransferToVaultIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_withdraw_and_transfer_to_vault<Config, Outcome, CoinType: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<Coin<CoinType>>,
) {
    let object = owned::do_withdraw(&mut executable, account, receiving, version::current(), WithdrawAndTransferToVaultIntent());
    vault::do_deposit(&mut executable, account, object, version::current(), WithdrawAndTransferToVaultIntent());
    
    account.confirm_execution(executable, version::current(), WithdrawAndTransferToVaultIntent());
}

// step 1: propose to send owned objects
public fun request_withdraw_and_transfer<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    object_ids: vector<ID>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(recipients.length() == object_ids.length(), EObjectsRecipientsNotSameLength);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndTransferIntent(),
        ctx
    );

    object_ids.zip_do!(recipients, |object_id, recipient| {
        owned::new_withdraw(&mut intent, account, object_id, version::current(), WithdrawAndTransferIntent());
        acc_transfer::new_transfer(&mut intent, account, recipient, version::current(), WithdrawAndTransferIntent());
    });

    account.add_intent(intent, version::current(), WithdrawAndTransferIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_withdraw_and_transfer<Config, Outcome, T: key + store>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<T>,
) {
    let object = owned::do_withdraw(executable, account, receiving, version::current(), WithdrawAndTransferIntent());
    acc_transfer::do_transfer(executable, account, object, version::current(), WithdrawAndTransferIntent());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_withdraw_and_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), WithdrawAndTransferIntent());
}

// step 1: propose to create a Stream with a specific amount to be paid at each interval
public fun request_withdraw_and_vest<Config, Outcome>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID, // coin owned by the account, must have the total amount to be paid
    start_timestamp: u64,
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        b"".to_string(),
        outcome,
        version::current(),
        WithdrawAndVestIntent(),
        ctx
    );
    
    owned::new_withdraw(
        &mut intent, account, coin_id, version::current(), WithdrawAndVestIntent()
    );
    vesting::new_vest(
        &mut intent, account, start_timestamp, end_timestamp, recipient, version::current(), WithdrawAndVestIntent()
    );
    account.add_intent(intent, version::current(), WithdrawAndVestIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: withdraw and place the coin into Stream to be paid
public fun execute_withdraw_and_vest<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    let coin: Coin<C> = owned::do_withdraw(&mut executable, account, receiving, version::current(), WithdrawAndVestIntent());
    vesting::do_vest(&mut executable, account, coin, version::current(), WithdrawAndVestIntent(), ctx);
    account.confirm_execution(executable, version::current(), WithdrawAndVestIntent());
}