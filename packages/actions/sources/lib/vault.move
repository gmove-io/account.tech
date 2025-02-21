/// Members can create multiple vaults with different balances and managers (using roles).
/// This allows for a more flexible and granular way to manage funds.

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
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

const EVaultDoesntExist: u64 = 0;
const EVaultAlreadyExists: u64 = 1;
const EVaultNotEmpty: u64 = 2;

// === Structs ===

/// Dynamic Field key for the Vault.
public struct VaultKey has copy, drop, store { name: String }
/// Dynamic field holding a budget with different coin types, key is name
public struct Vault has store {
    // heterogeneous array of Balances, TypeName -> Balance<CoinType>
    bag: Bag
}

/// Action to deposit an amount of this coin to the targeted Vault.
public struct DepositAction<phantom CoinType> has store {
    // vault name
    name: String,
    // exact amount to be deposited
    amount: u64,
}
/// Action to be used within intent making good use of the returned coin, similar to owned::withdraw.
public struct SpendAction<phantom CoinType> has store {
    // vault name
    name: String,
    // amount to withdraw
    amount: u64,
}

// === Public Functions ===

/// Authorized address can open a vault.
public fun open<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(!has_vault(account, name), EVaultAlreadyExists);

    account.add_managed_data(VaultKey { name }, Vault { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by a an authorized address into a vault.
public fun deposit<Config, Outcome, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String, 
    coin: Coin<CoinType>, 
) {
    account.verify(auth);
    assert!(has_vault(account, name), EVaultDoesntExist);

    let vault: &mut Vault = 
        account.borrow_managed_data_mut(VaultKey { name }, version::current());

    if (vault.coin_type_exists<CoinType>()) {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
        balance_mut.join(coin.into_balance());
    } else {
        vault.bag.add(type_name::get<CoinType>(), coin.into_balance());
    };
}

/// Closes the vault if empty.
public fun close<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
) {
    account.verify(auth);

    let Vault { bag } = 
        account.remove_managed_data(VaultKey { name }, version::current());
    assert!(bag.is_empty(), EVaultNotEmpty);
    bag.destroy_empty();
}

/// Returns true if the vault exists.
public fun has_vault<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_data(VaultKey { name })
}

/// Returns a reference to the vault.
public fun borrow_vault<Config, Outcome>(
    account: &Account<Config, Outcome>, 
    name: String
): &Vault {
    assert!(has_vault(account, name), EVaultDoesntExist);
    account.borrow_managed_data(VaultKey { name }, version::current())
}

/// Returns the number of coin types in the vault.
public fun size(vault: &Vault): u64 {
    vault.bag.length()
}

/// Returns true if the coin type exists in the vault.
public fun coin_type_exists<CoinType: drop>(vault: &Vault): bool {
    vault.bag.contains(type_name::get<CoinType>())
}

/// Returns the value of the coin type in the vault.
public fun coin_type_value<CoinType: drop>(vault: &Vault): u64 {
    vault.bag.borrow<TypeName, Balance<CoinType>>(type_name::get<CoinType>()).value()
}

// Intent functions

/// Creates a DepositAction and adds it to an intent.
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

/// Processes a DepositAction and deposits a coin to the vault.
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
    
    let vault: &mut Vault = account.borrow_managed_data_mut(VaultKey { name }, version_witness);
    if (!vault.coin_type_exists<CoinType>()) {
        vault.bag.add(type_name::get<CoinType>(), coin.into_balance());
    } else {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
        balance_mut.join(coin.into_balance());
    };
}

/// Deletes a DepositAction from an expired intent.
public fun delete_deposit<CoinType>(expired: &mut Expired) {
    let DepositAction<CoinType> { .. } = expired.remove_action();
}

/// Creates a SpendAction and adds it to an intent.
public fun new_spend<Config, Outcome, CoinType: drop, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>,
    name: String,
    amount: u64,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    account.add_action(intent, SpendAction<CoinType> { name, amount }, version_witness, intent_witness);
}

/// Processes a SpendAction and takes a coin from the vault.
public fun do_spend<Config, Outcome, CoinType: drop, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
): Coin<CoinType> {
    let action: &SpendAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let (name, amount) = (action.name, action.amount);
    
    let vault: &mut Vault = account.borrow_managed_data_mut(VaultKey { name }, version_witness);
    let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::get<CoinType>());
    let coin = coin::take(balance_mut, amount, ctx);

    if (balance_mut.value() == 0) 
        vault.bag.remove<_, Balance<CoinType>>(type_name::get<CoinType>()).destroy_zero();
    
    coin
}

/// Deletes a SpendAction from an expired intent.
public fun delete_spend<CoinType>(expired: &mut Expired) {
    let SpendAction<CoinType> { .. } = expired.remove_action();
}
