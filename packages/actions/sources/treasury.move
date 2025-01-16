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
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
};
use account_actions::{
    transfer as acc_transfer,
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

/// [PROPOSAL] witness defining the treasury transfer proposal, and associated role
public struct TransferIntent() has copy, drop;
/// [PROPOSAL] witness defining the treasury pay proposal, and associated role
public struct VestingIntent() has copy, drop;

/// Dynamic Field key for the Treasury
public struct TreasuryKey has copy, drop, store { name: String }
/// Dynamic field holding a budget with different coin types, key is name
public struct Treasury has store {
    // heterogeneous array of Balances, TypeName -> Balance<CoinType>
    bag: Bag
}

/// [ACTION] struct to be used with specific proposals making good use of the returned coins, similar to owned::withdraw
public struct SpendAction<phantom CoinType> has store {
    // amount to withdraw
    amount: u64,
}

// === [COMMAND] Public Functions ===

/// Members with role can open a treasury
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    ctx: &mut TxContext
) {
    auth.verify(account.addr());
    assert!(!has_treasury(account, name), EAlreadyExists);

    account.add_managed_struct(TreasuryKey { name }, Treasury { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by the account into a treasury
public fun deposit_owned<Config, Outcome, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    receiving: Receiving<Coin<CoinType>>, 
) {
    let coin = account.receive(receiving, version::current());
    deposit<Config, Outcome, CoinType>(auth, account, name, coin);
}

// TODO: remove role name (any member can deposit)
/// Deposits coins owned by a member into a treasury
public fun deposit<Config, Outcome, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    coin: Coin<CoinType>, 
) {
    auth.verify(account.addr());
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
public fun close<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
) {
    auth.verify(account.addr());

    let Treasury { bag } = 
        account.remove_managed_struct(TreasuryKey { name }, version::current());
    assert!(bag.is_empty(), ENotEmpty);
    bag.destroy_empty();
}

public fun has_treasury<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_struct(TreasuryKey { name })
}

public fun borrow_treasury<Config, Outcome>(
    account: &Account<Config, Outcome>, 
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
public fun request_transfer<Config, Outcome, CoinType: drop>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_times: vector<u64>,
    expiration_time: u64,
    treasury_name: String,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(amounts.length() == recipients.length(), ENotSameLength);
    let treasury = borrow_treasury(account, treasury_name);
    assert!(treasury.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (treasury.coin_type_value<CoinType>() < sum) assert!(sum <= treasury.coin_type_value<CoinType>(), EInsufficientFunds);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        execution_times,
        expiration_time,
        outcome,
        version::current(),
        TransferIntent(),
        treasury_name,
        ctx
    );

    recipients.zip_do!(amounts, |recipient, amount| {
        new_spend<Outcome, CoinType, TransferIntent>(&mut intent, amount, TransferIntent());
        acc_transfer::new_transfer(&mut intent, recipient, TransferIntent());
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
    let coin: Coin<CoinType> = do_spend(executable, account, version::current(), TransferIntent(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), TransferIntent());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer<Config, Outcome>(
    executable: Executable,
    account: &Account<Config, Outcome>,
) {
    account.confirm_execution(executable, version::current(), TransferIntent());
}

// step 1(bis): same but from a treasury
public fun request_vesting<Config, Outcome, CoinType: drop>(
    auth: Auth,
    outcome: Outcome,
    account: &mut Account<Config, Outcome>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    treasury_name: String, 
    coin_amount: u64, 
    start_timestamp: u64, 
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    let treasury = borrow_treasury(account, treasury_name);
    assert!(treasury.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    assert!(treasury.coin_type_value<CoinType>() >= coin_amount, EInsufficientFunds);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        VestingIntent(),
        treasury_name,
        ctx
    );

    new_spend<Outcome, CoinType, VestingIntent>(&mut intent, coin_amount, VestingIntent());
    vesting::new_vesting(&mut intent, start_timestamp, end_timestamp, recipient, VestingIntent());
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
    let coin: Coin<CoinType> = do_spend(&mut executable, account, version::current(), VestingIntent(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), VestingIntent(), ctx);
    account.confirm_execution(executable, version::current(), VestingIntent());
}

// === [ACTION] Public Functions ===

public fun new_spend<Outcome, CoinType: drop, W: drop>(
    intent: &mut Intent<Outcome>,
    amount: u64,
    witness: W,
) {
    intent.add_action(SpendAction<CoinType> { amount }, witness);
}

public fun do_spend<Config, Outcome, CoinType: drop, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
    ctx: &mut TxContext
): Coin<CoinType> {
    let name = executable.issuer().opt_name();
    let action: &SpendAction<CoinType> = account.process_action(executable, version, witness);
    let amount = action.amount;
    
    let treasury: &mut Treasury = account.borrow_managed_struct_mut(TreasuryKey { name }, version);
    let balance: &mut Balance<CoinType> = treasury.bag.borrow_mut(type_name::get<CoinType>());
    let coin = coin::take(balance, amount, ctx);

    if (balance.value() == 0) 
        treasury.bag.remove<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).destroy_zero();
    
    coin
}

public fun delete_spend<CoinType>(expired: &mut Expired) {
    let SpendAction<CoinType> { .. } = expired.remove_action();
}
