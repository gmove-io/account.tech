module account_actions::vault_intents;

// === Imports ===

use std::string::String;
use sui::coin::Coin;
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    vault,
    version,
};

// === Errors ===

#[error]
const ENotSameLength: vector<u8> = b"Recipients and amounts vectors not same length";
#[error]
const EInsufficientFunds: vector<u8> = b"Insufficient funds for this coin type in vault";
#[error]
const ECoinTypeDoesntExist: vector<u8> = b"Coin type doesn't exist in vault";

// === Structs ===

/// [PROPOSAL] witness defining the vault transfer proposal, and associated role
public struct TransferIntent() has copy, drop;
/// [PROPOSAL] witness defining the vault pay proposal, and associated role
public struct VestingIntent() has copy, drop;

// === [PROPOSAL] Public Functions ===

// step 1: propose to send managed coins
public fun request_transfer<Config, Outcome, CoinType: drop>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    vault_name: String,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(amounts.length() == recipients.length(), ENotSameLength);
    
    let vault = vault::borrow_vault(account, vault_name);
    assert!(vault.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (vault.coin_type_value<CoinType>() < sum) assert!(sum <= vault.coin_type_value<CoinType>(), EInsufficientFunds);

    let mut intent = account.create_intent(
        key,
        description,
        execution_times,
        expiration_time,
        vault_name,
        outcome,
        version::current(),
        TransferIntent(),
        ctx
    );

    recipients.zip_do!(amounts, |recipient, amount| {
        vault::new_spend<_, _, CoinType, _>(&mut intent, account, amount, version::current(), TransferIntent());
        acc_transfer::new_transfer(&mut intent, account, recipient, version::current(), TransferIntent());
    });
    account.add_intent(intent, version::current(), TransferIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, CoinType: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = vault::do_spend(executable, account, version::current(), TransferIntent(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), TransferIntent());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), TransferIntent());
}

// step 1(bis): same but from a vault
public fun request_vesting<Config, Outcome, CoinType: drop>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    vault_name: String, 
    coin_amount: u64, 
    start_timestamp: u64, 
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    let vault = vault::borrow_vault(account, vault_name);
    assert!(vault.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    assert!(vault.coin_type_value<CoinType>() >= coin_amount, EInsufficientFunds);

    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        vault_name,
        outcome,
        version::current(),
        VestingIntent(),
        ctx
    );

    vault::new_spend<_, _, CoinType, _>(
        &mut intent, account, coin_amount, version::current(), VestingIntent()
    );
    vesting::new_vesting(
        &mut intent, account, start_timestamp, end_timestamp, recipient, version::current(), VestingIntent()
    );
    account.add_intent(intent, version::current(), VestingIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_vesting<Config, Outcome, CoinType: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = vault::do_spend(&mut executable, account, version::current(), VestingIntent(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), VestingIntent(), ctx);
    account.confirm_execution(executable, version::current(), VestingIntent());
}