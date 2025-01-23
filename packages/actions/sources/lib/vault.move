/// Members can create multiple treasuries with different budgets and managers (members with roles).
/// This allows for a more flexible and granular way to manage funds.
/// 
/// Coins managed by treasuries can also be transferred or paid to any address.

module account_actions::vault;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
    // transfer::Receiving,
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

#[error]
const EVaultDoesntExist: vector<u8> = b"No Vault with this name";
#[error]
const EVaultAlreadyExists: vector<u8> = b"A vault already exists with this name";
#[error]
const EVaultNotEmpty: vector<u8> = b"Vault must be emptied before closing";

// === Structs ===

/// Dynamic Field key for the Vault
public struct VaultKey has copy, drop, store { name: String }
/// Dynamic field holding a budget with different coin types, key is name
public struct Vault has store {
    // heterogeneous array of Balances, TypeName -> Balance<CoinType>
    bag: Bag
}

/// [ACTION] allows anyone to deposit an amount of this coin to the targeted Vault
public struct DepositAction<phantom CoinType> has store {
    // vault name
    name: String,
    // exact amount to be deposited
    amount: u64,
}
/// [ACTION] struct to be used with specific proposals making good use of the returned coins, similar to owned::withdraw
public struct SpendAction<phantom CoinType> has store {
    // amount to withdraw
    amount: u64,
}

// === [COMMAND] Public Functions ===

/// Members with role can open a vault
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(!has_vault(account, name), EVaultAlreadyExists);

    account.add_managed_struct(VaultKey { name }, Vault { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by a member into a vault
public fun deposit<Config, Outcome, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    coin: Coin<CoinType>, 
) {
    account.verify(auth);
    assert!(has_vault(account, name), EVaultDoesntExist);

    let vault: &mut Vault = 
        account.borrow_managed_struct_mut(VaultKey { name }, version::current());

    if (vault.coin_type_exists<CoinType>()) {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
        balance_mut.join(coin.into_balance());
    } else {
        vault.bag.add(type_name::get<CoinType>(), coin.into_balance());
    };
}

/// Closes the vault if empty
public fun close<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
) {
    account.verify(auth);

    let Vault { bag } = 
        account.remove_managed_struct(VaultKey { name }, version::current());
    assert!(bag.is_empty(), EVaultNotEmpty);
    bag.destroy_empty();
}

public fun has_vault<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_struct(VaultKey { name })
}

public fun borrow_vault<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): &Vault {
    assert!(has_vault(account, name), EVaultDoesntExist);
    account.borrow_managed_struct(VaultKey { name }, version::current())
}

public fun size(vault: &Vault): u64 {
    vault.bag.length()
}

public fun coin_type_exists<CoinType: drop>(vault: &Vault): bool {
    vault.bag.contains(type_name::get<CoinType>())
}

public fun coin_type_value<CoinType: drop>(vault: &Vault): u64 {
    vault.bag.borrow<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).value()
}

// must be called from intent modules

public fun new_deposit<Config, Outcome, CoinType: drop, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>,
    name: String,
    amount: u64,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, DepositAction<CoinType> { name, amount }, version_witness, intent_witness);
}

public fun do_deposit<Config, Outcome, CoinType: drop, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    coin: Coin<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action: &DepositAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let name = action.name;
    assert!(action.amount == coin.value());
    
    let vault: &mut Vault = account.borrow_managed_struct_mut(VaultKey { name }, version_witness);
    if (!vault.coin_type_exists<CoinType>()) {
        vault.bag.add(type_name::get<CoinType>(), coin.into_balance());
    } else {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
        balance_mut.join(coin.into_balance());
    };
}

public fun delete_deposit<CoinType>(expired: &mut Expired) {
    let DepositAction<CoinType> { .. } = expired.remove_action();
}

public fun new_spend<Config, Outcome, CoinType: drop, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>,
    amount: u64,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, SpendAction<CoinType> { amount }, version_witness, intent_witness);
}

public fun do_spend<Config, Outcome, CoinType: drop, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
): Coin<CoinType> {
    let name = executable.managed_name();
    let action: &SpendAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let amount = action.amount;
    
    let vault: &mut Vault = account.borrow_managed_struct_mut(VaultKey { name }, version_witness);
    let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
    let coin = coin::take(balance_mut, amount, ctx);

    if (balance_mut.value() == 0) 
        vault.bag.remove<_, Balance<CoinType>>(type_name::get<CoinType>()).destroy_zero();
    
    coin
}

public fun delete_spend<CoinType>(expired: &mut Expired) {
    let SpendAction<CoinType> { .. } = expired.remove_action();
}
