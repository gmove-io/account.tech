/// Members can create multiple treasuries with different budgets and managers (members with roles).
/// This allows for a more flexible and granular way to manage funds.
/// 
/// Coins managed by treasuries can also be transferred or paid to any address.

module account_actions::treasury;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    transfer::Receiving,
};
use account_protocol::{
    account::Account,
    executable::Executable,
    auth::Auth,
};
use account_actions::{
    vesting,
    version,
};

// === Errors ===

#[error]
const ETreasuryDoesntExist: vector<u8> = b"No Treasury with this name";
#[error]
const EAlreadyExists: vector<u8> = b"A treasury already exists with this name";
#[error]
const ENotSameLength: vector<u8> = b"Recipients and amounts vectors not same length";
#[error]
const ENotEmpty: vector<u8> = b"Treasury must be emptied before closing";
#[error]
const EInsufficientFunds: vector<u8> = b"Insufficient funds for this coin type in treasury";
#[error]
const ECoinTypeDoesntExist: vector<u8> = b"Coin type doesn't exist in treasury";

// === Structs ===

/// [COMMAND] witness defining the treasury opening and closing commands, and associated role
public struct Witness() has drop;

/// Dynamic Field key for the Treasury
public struct TreasuryKey has copy, drop, store { name: String }
/// Dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, TypeName -> Balance<CoinType>
    bag: Bag
}

/// [ACTION] struct to be used with specific proposals making good use of the returned coins, similar to owned::withdraw
public struct SpendAndTransferAction<phantom CoinType> has drop, store {
    // amount to withdraw
    amounts: vector<u64>,
    // recipient
    recipients: vector<address>,
}
/// [ACTION]
public struct SpendAndVestingAction<phantom CoinType> has drop, store {
    // amount to withdraw
    amount: u64,
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}

// === [COMMAND] Public Functions ===

/// Members with role can open a treasury
public fun open<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String,
    ctx: &mut TxContext
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(!has_treasury(account, name), EAlreadyExists);

    account.add_managed_struct(TreasuryKey { name }, Treasury { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by the account into a treasury
public fun deposit_owned<Config, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String, 
    receiving: Receiving<Coin<CoinType>>, 
) {
    let coin = account.receive(receiving, version::current());
    deposit<Config, CoinType>(auth, account, name, coin);
}

// TODO: remove role name (any member can deposit)
/// Deposits coins owned by a member into a treasury
public fun deposit<Config, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String, 
    coin: Coin<CoinType>, 
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());
    assert!(has_treasury(account, name), ETreasuryDoesntExist);

    let treasury: &mut Treasury = 
        account.borrow_managed_struct_mut(TreasuryKey { name }, version::current());

    if (treasury.coin_type_exists<CoinType>()) {
        let balance: &mut Balance<CoinType> = treasury.bag.borrow_mut(type_name::get<CoinType>());
        balance.join(coin.into_balance());
    } else {
        treasury.bag.add(type_name::get<CoinType>(), coin.into_balance());
    };
}

/// Closes the treasury if empty
public fun close<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String,
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());

    let Treasury { bag } = 
        account.remove_managed_struct(TreasuryKey { name }, version::current());
    assert!(bag.is_empty(), ENotEmpty);
    bag.destroy_empty();
}

public fun has_treasury<Config>(
    account: &Account<Config>, 
    name: String
): bool {
    account.has_managed_struct(TreasuryKey { name })
}

public fun borrow_treasury<Config>(
    account: &Account<Config>, 
    name: String
): &Treasury {
    assert!(has_treasury(account, name), ETreasuryDoesntExist);
    account.borrow_managed_struct(TreasuryKey { name }, version::current())
}

public fun coin_type_exists<CoinType: drop>(treasury: &Treasury): bool {
    treasury.bag.contains(type_name::get<CoinType>())
}

public fun coin_type_value<CoinType: drop>(treasury: &Treasury): u64 {
    treasury.bag.borrow<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).value()
}

// === [PROPOSAL] Public Functions ===

// step 1: propose to send managed coins
public fun request_spend_and_transfer<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    treasury_name: String,
    amounts: vector<u64>,
    recipients: vector<address>,
    outcome: Outcome,
) {
    assert!(amounts.length() == recipients.length(), ENotSameLength);
    let treasury = borrow_treasury(account, treasury_name);
    assert!(treasury.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (treasury.coin_type_value<CoinType>() < sum) assert!(sum <= treasury.coin_type_value<CoinType>(), EInsufficientFunds);

    let action = SpendAndTransferAction<CoinType> { amounts, recipients };

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
        treasury_name,
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_spend_and_transfer<Config, CoinType: drop>(
    mut executable: Executable<SpendAndTransferAction<CoinType>>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    let name = executable.issuer().opt_name();
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());

    action_mut.amounts.zip_do!(action_mut.recipients, |amount, recipient| {
        let treasury: &mut Treasury = account.borrow_managed_struct_mut(TreasuryKey { name }, version::current());
        let balance: &mut Balance<CoinType> = treasury.bag.borrow_mut(type_name::get<CoinType>());
        let coin = coin::take(balance, amount, ctx);

        if (balance.value() == 0) 
            treasury.bag.remove<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).destroy_zero();
        
        transfer::public_transfer(coin, recipient);
    });
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_spend_and_transfer<CoinType>(executable: Executable<SpendAndTransferAction<CoinType>>) {
    executable.destroy(version::current(), Witness());
}

// step 1(bis): same but from a treasury
public fun request_spend_and_vesting<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    treasury_name: String, 
    amount: u64, 
    start_timestamp: u64, 
    end_timestamp: u64, 
    recipient: address,
    outcome: Outcome,
) {
    let treasury = borrow_treasury(account, treasury_name);
    assert!(treasury.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    assert!(treasury.coin_type_value<CoinType>() >= amount, EInsufficientFunds);

    let action = SpendAndVestingAction<CoinType> { 
        amount, 
        start_timestamp, 
        end_timestamp, 
        recipient 
    };

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
        treasury_name,
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_spend_and_vesting<Config, CoinType: drop>(
    mut executable: Executable<SpendAndVestingAction<CoinType>>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    let name = executable.issuer().opt_name();
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());

    let treasury: &mut Treasury = account.borrow_managed_struct_mut(TreasuryKey { name }, version::current());
    let balance: &mut Balance<CoinType> = treasury.bag.borrow_mut(type_name::get<CoinType>());
    let coin = coin::take(balance, action_mut.amount, ctx);

    if (balance.value() == 0) 
        treasury.bag.remove<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).destroy_zero();
    
    vesting::create_stream(
        coin, 
        action_mut.start_timestamp, 
        action_mut.end_timestamp, 
        action_mut.recipient, 
        ctx
    );

    executable.destroy(version::current(), Witness());
}