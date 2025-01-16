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
    version,
};

// === Errors ===

#[error]
const ETreasuryDoesntExist: vector<u8> = b"No Treasury with this name";
#[error]
const EAlreadyExists: vector<u8> = b"A treasury already exists with this name";
#[error]
const ENotEmpty: vector<u8> = b"Treasury must be emptied before closing";

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

// must be called from intent modules

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
