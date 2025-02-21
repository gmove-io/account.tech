module account_actions::currency_intents;

// === Imports ===

use std::{
    type_name,
    string::String,
    ascii,
};
use sui::{
    transfer::Receiving,
    coin::{Coin, CoinMetadata},
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    owned,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    version,
    currency::{Self, CurrencyRules},
};

// === Errors ===

const EAmountsRecipentsNotSameLength: u64 = 0;
const EMaxSupply: u64 = 1;

// === Structs ===

/// Intent Witness defining the intent to disable one or more permissions.
public struct DisableRulesIntent() has copy, drop;
/// Intent Witness defining the intent to update the CoinMetadata associated with a locked TreasuryCap.
public struct UpdateMetadataIntent() has copy, drop;
/// Intent Witness defining the intent to transfer a minted coin.
public struct MintAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to pay from a minted coin.
public struct MintAndVestIntent() has copy, drop;
/// Intent Witness defining the intent to burn coins from the account using a locked TreasuryCap.
public struct WithdrawAndBurnIntent() has copy, drop;

// === Public functions ===

/// Creates a DisableRulesIntent and adds it to an Account.
public fun request_disable_rules<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    disable_mint: bool,
    disable_burn: bool,
    disable_update_symbol: bool,
    disable_update_name: bool,
    disable_update_description: bool,
    disable_update_icon: bool,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key, 
        description, 
        vector[execution_time], 
        expiration_time, 
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        DisableRulesIntent(), 
        ctx
    );

    currency::new_disable<_, _, CoinType, _>(
        &mut intent, 
        account,
        disable_mint,
        disable_burn,
        disable_update_symbol,
        disable_update_name,
        disable_update_description,
        disable_update_icon,
        version::current(),
        DisableRulesIntent()
    );
    account.add_intent(intent, version::current(), DisableRulesIntent());
}

/// Executes a DisableRulesIntent, disables rules for the coin forever.
public fun execute_disable_rules<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    currency::do_disable<_, _, CoinType, _>(&mut executable, account, version::current(), DisableRulesIntent());   
    account.confirm_execution(executable, version::current(), DisableRulesIntent());
}

/// Creates an UpdateMetadataIntent and adds it to an Account.
public fun request_update_metadata<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    md_symbol: Option<ascii::String>,
    md_name: Option<String>,
    md_description: Option<String>,
    md_icon: Option<ascii::String>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    
    let mut intent = account.create_intent(
        key,
        description,
        vector[execution_time],
        expiration_time,
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        UpdateMetadataIntent(),
        ctx
    );

    currency::new_update<_, _, CoinType, _>(
        &mut intent, account,md_symbol, md_name, md_description, md_icon, version::current(),UpdateMetadataIntent(),
    );
    account.add_intent(intent, version::current(), UpdateMetadataIntent());
}

/// Executes an UpdateMetadataIntent, updates the CoinMetadata.
public fun execute_update_metadata<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
) {
    currency::do_update(&mut executable, account, metadata, version::current(), UpdateMetadataIntent());
    account.confirm_execution(executable, version::current(), UpdateMetadataIntent());
}

/// Creates a MintAndTransferIntent and adds it to an Account.
public fun request_mint_and_transfer<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

    let rules: &CurrencyRules<CoinType> = currency::borrow_rules(account);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (rules.max_supply().is_some()) assert!(sum <= *rules.max_supply().borrow(), EMaxSupply);

    let mut intent = account.create_intent(
        key,
        description,
        execution_times,
        expiration_time,
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        MintAndTransferIntent(),
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        currency::new_mint<_, _, CoinType, _>(
            &mut intent, account,amount, version::current(),MintAndTransferIntent(),
        );
        acc_transfer::new_transfer(
            &mut intent, account, recipient, version::current(), MintAndTransferIntent()
        );
    });

    account.add_intent(intent, version::current(), MintAndTransferIntent());
}

/// Executes a MintAndTransferIntent, sends managed coins. Can be looped over.
public fun execute_mint_and_transfer<Config, Outcome, CoinType>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = currency::do_mint(executable, account, version::current(), MintAndTransferIntent(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), MintAndTransferIntent());
}

/// Completes a MintAndTransferIntent, destroys the executable after looping over the transfers.
public fun complete_mint_and_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), MintAndTransferIntent());
}

/// Creates a MintAndVestIntent and adds it to an Account.
public fun request_mint_and_vest<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    total_amount: u64,
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
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        MintAndVestIntent(),
        ctx
    );

    currency::new_mint<_, _, CoinType, _>(
        &mut intent, account,total_amount, version::current(),MintAndVestIntent(),
    );
    vesting::new_vest(
        &mut intent, account,start_timestamp, end_timestamp, recipient, version::current(),MintAndVestIntent(),
    );
    account.add_intent(intent, version::current(), MintAndVestIntent());
}

/// Executes a MintAndVestIntent, sends managed coins and creates a vesting.
public fun execute_mint_and_vest<Config, Outcome, CoinType>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = currency::do_mint(&mut executable, account, version::current(), MintAndVestIntent(), ctx);
    vesting::do_vest(&mut executable, account, coin, version::current(), MintAndVestIntent(), ctx);
    account.confirm_execution(executable, version::current(), MintAndVestIntent());
}

/// Creates a WithdrawAndBurnIntent and adds it to an Account.
public fun request_withdraw_and_burn<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key, 
        description, 
        vector[execution_time], 
        expiration_time, 
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        WithdrawAndBurnIntent(), 
        ctx
    );

    owned::new_withdraw(&mut intent, account, coin_id, version::current(), WithdrawAndBurnIntent());
    currency::new_burn<_, _, CoinType, _>(
        &mut intent, account,amount, version::current(),WithdrawAndBurnIntent(),
    );

    account.add_intent(intent, version::current(), WithdrawAndBurnIntent());
}

/// Executes a WithdrawAndBurnIntent, burns a coin owned by the account.
public fun execute_withdraw_and_burn<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    receiving: Receiving<Coin<CoinType>>,
) {
    let coin = owned::do_withdraw(&mut executable, account, receiving, version::current(), WithdrawAndBurnIntent());
    currency::do_burn<_, _, CoinType, _>(&mut executable, account, coin, version::current(), WithdrawAndBurnIntent());
    account.confirm_execution(executable, version::current(), WithdrawAndBurnIntent());
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}