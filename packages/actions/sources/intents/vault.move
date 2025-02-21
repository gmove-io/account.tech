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

const ENotSameLength: u64 = 0;
const EInsufficientFunds: u64 = 1;
const ECoinTypeDoesntExist: u64 = 2;

// === Structs ===

/// Intent Witness defining the vault spend and transfer intent, and associated role.
public struct SpendAndTransferIntent() has copy, drop;
/// Intent Witness defining the vault spend and vesting intent, and associated role.
public struct SpendAndVestIntent() has copy, drop;

// === Public Functions ===

/// Creates a SpendAndTransferIntent and adds it to an Account.
public fun request_spend_and_transfer<Config, Outcome, CoinType: drop>(
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
        SpendAndTransferIntent(),
        ctx
    );

    recipients.zip_do!(amounts, |recipient, amount| {
        vault::new_spend<_, _, CoinType, _>(&mut intent, account, vault_name, amount, version::current(), SpendAndTransferIntent());
        acc_transfer::new_transfer(&mut intent, account, recipient, version::current(), SpendAndTransferIntent());
    });
    account.add_intent(intent, version::current(), SpendAndTransferIntent());
}

/// Executes a SpendAndTransferIntent, transfers coins from the vault to the recipients. Can be looped over.
public fun execute_spend_and_transfer<Config, Outcome, CoinType: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = vault::do_spend(executable, account, version::current(), SpendAndTransferIntent(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), SpendAndTransferIntent());
}

/// Completes a SpendAndTransferIntent, destroys the executable after looping over the transfers.
public fun complete_spend_and_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), SpendAndTransferIntent());
}

/// Creates a SpendAndVestIntent and adds it to an Account.
public fun request_spend_and_vest<Config, Outcome, CoinType: drop>(
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
        SpendAndVestIntent(),
        ctx
    );

    vault::new_spend<_, _, CoinType, _>(
        &mut intent, account, vault_name, coin_amount, version::current(), SpendAndVestIntent()
    );
    vesting::new_vest(
        &mut intent, account, start_timestamp, end_timestamp, recipient, version::current(), SpendAndVestIntent()
    );
    account.add_intent(intent, version::current(), SpendAndVestIntent());
}

/// Executes a SpendAndVestIntent, create a vesting from a coin in the vault.
public fun execute_spend_and_vest<Config, Outcome, CoinType: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = vault::do_spend(&mut executable, account, version::current(), SpendAndVestIntent(), ctx);
    vesting::do_vest(&mut executable, account, coin, version::current(), SpendAndVestIntent(), ctx);
    account.confirm_execution(executable, version::current(), SpendAndVestIntent());
}