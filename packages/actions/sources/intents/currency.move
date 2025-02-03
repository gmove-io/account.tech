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

#[error]
const EAmountsRecipentsNotSameLength: vector<u8> = b"Transfer amounts and recipients are not the same length";
#[error]
const EMaxSupply: vector<u8> = b"Max supply exceeded";

// === Structs ===

/// [PROPOSAL] witness defining the proposal to disable one or more permissions
public struct DisableIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to mint new coins from a locked TreasuryCap
public struct MintIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to burn coins from the account using a locked TreasuryCap
public struct BurnIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to update the CoinMetadata associated with a locked TreasuryCap
public struct UpdateIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to transfer a minted coin 
public struct TransferIntent() has copy, drop;
/// [PROPOSAL] witness defining the proposal to pay from a minted coin
public struct VestingIntent() has copy, drop;

// === [PROPOSAL] Public functions ===

// step 1: propose to disable minting for the coin forever
public fun request_disable<Config, Outcome, CoinType>(
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
        DisableIntent(), 
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
        DisableIntent()
    );
    account.add_intent(intent, version::current(), DisableIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: disable minting for the coin forever
public fun execute_disable<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    currency::do_disable<_, _, CoinType, _>(&mut executable, account, version::current(), DisableIntent());   
    account.confirm_execution(executable, version::current(), DisableIntent());
}

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun request_mint<Config, Outcome, CoinType>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>,
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    amount: u64,
    ctx: &mut TxContext
) {
    account.verify(auth);

    let mut intent = account.create_intent(
        key, 
        description, 
        execution_times, 
        expiration_time, 
        type_to_name<CoinType>(), 
        outcome,
        version::current(),
        MintIntent(), 
        ctx
    );

    currency::new_mint<_, _, CoinType, _>(
        &mut intent, account,amount, version::current(),MintIntent(),
    );
    account.add_intent(intent, version::current(), MintIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    let coin = currency::do_mint<_, _, CoinType, _>(&mut executable, account, version::current(), MintIntent(), ctx);
    account.keep(coin);
    account.confirm_execution(executable, version::current(), MintIntent());
}

// step 1: propose to burn an amount of a coin owned by the account
public fun request_burn<Config, Outcome, CoinType>(
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
        BurnIntent(), 
        ctx
    );

    owned::new_withdraw(&mut intent, account, coin_id, version::current(), BurnIntent());
    currency::new_burn<_, _, CoinType, _>(
        &mut intent, account,amount, version::current(),BurnIntent(),
    );

    account.add_intent(intent, version::current(), BurnIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: burn the coin initially owned by the account
public fun execute_burn<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    receiving: Receiving<Coin<CoinType>>,
) {
    let coin = owned::do_withdraw(&mut executable, account, receiving, version::current(), BurnIntent());
    currency::do_burn<_, _, CoinType, _>(&mut executable, account, coin, version::current(), BurnIntent());
    account.confirm_execution(executable, version::current(), BurnIntent());
}

// step 1: propose to update the CoinMetadata
public fun request_update<Config, Outcome, CoinType>(
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
        UpdateIntent(),
        ctx
    );

    currency::new_update<_, _, CoinType, _>(
        &mut intent, account,md_symbol, md_name, md_description, md_icon, version::current(),UpdateIntent(),
    );
    account.add_intent(intent, version::current(), UpdateIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
) {
    currency::do_update(&mut executable, account, metadata, version::current(), UpdateIntent());
    account.confirm_execution(executable, version::current(), UpdateIntent());
}

// step 1: propose to send managed coins
public fun request_transfer<Config, Outcome, CoinType>(
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
        TransferIntent(),
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        currency::new_mint<_, _, CoinType, _>(
            &mut intent, account,amount, version::current(),TransferIntent(),
        );
        acc_transfer::new_transfer(
            &mut intent, account, recipient, version::current(), TransferIntent()
        );
    });

    account.add_intent(intent, version::current(), TransferIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, CoinType>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = currency::do_mint(executable, account, version::current(), TransferIntent(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), TransferIntent());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), TransferIntent());
}

// step 1: propose to pay from a minted coin
public fun request_vesting<Config, Outcome, CoinType>(
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
        VestingIntent(),
        ctx
    );

    currency::new_mint<_, _, CoinType, _>(
        &mut intent, account,total_amount, version::current(),VestingIntent(),
    );
    vesting::new_vesting(
        &mut intent, account,start_timestamp, end_timestamp, recipient, version::current(),VestingIntent(),
    );
    account.add_intent(intent, version::current(), VestingIntent());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_vesting<Config, Outcome, CoinType>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = currency::do_mint(&mut executable, account, version::current(), VestingIntent(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), VestingIntent(), ctx);
    account.confirm_execution(executable, version::current(), VestingIntent());
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}