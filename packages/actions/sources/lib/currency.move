/// Members can lock a TreasuryCap in the Account to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Account and burn one of its coin.
/// It uses a Withdraw action. The burnt Coin could be merged beforehand.
/// 
/// Coins minted by the account can also be transferred or paid to any address.

module account_actions::currency;

// === Imports ===

use std::{
    string::String,
    ascii,
};
use sui::coin::{Coin, TreasuryCap, CoinMetadata};
use account_protocol::{
    account::{Account, Auth},
    intents::{Intent, Expired},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

#[error]
const ENoChange: vector<u8> = b"Proposal must change something";
#[error]
const EWrongValue: vector<u8> = b"Coin has the wrong value";
#[error]
const ENoLock: vector<u8> = b"No lock for this coin type";
#[error]
const EMintDisabled: vector<u8> = b"Mint disabled";
#[error]
const EBurnDisabled: vector<u8> = b"Burn disabled";
#[error]
const ECannotUpdateName: vector<u8> = b"Cannot update name";
#[error]
const ECannotUpdateSymbol: vector<u8> = b"Cannot update symbol";
#[error]
const ECannotUpdateDescription: vector<u8> = b"Cannot update description";
#[error]
const ECannotUpdateIcon: vector<u8> = b"Cannot update icon";
#[error]
const EMaxSupply: vector<u8> = b"Max supply exceeded";

// === Structs ===    

/// Dynamic Object Field key for the TreasuryCap
public struct TreasuryCapKey<phantom CoinType> has copy, drop, store {}
/// Dynamic Field key for the CurrencyRules
public struct CurrencyRulesKey<phantom CoinType> has copy, drop, store {}
/// Dynamic Field wrapper restricting access to a TreasuryCap, permissions are disabled forever if set
public struct CurrencyRules<phantom CoinType> has store {
    // coin can have a fixed supply, can_mint must be true 
    max_supply: Option<u64>,
    // total amount minted
    total_minted: u64,
    // total amount burned
    total_burned: u64,
    // permissions
    can_mint: bool,
    can_burn: bool,
    can_update_symbol: bool,
    can_update_name: bool,
    can_update_description: bool,
    can_update_icon: bool,
}

/// [ACTION] disables permissions marked as true, cannot be reenabled
public struct DisableAction<phantom CoinType> has store {
    mint: bool,
    burn: bool,
    update_symbol: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
}
/// [ACTION] mints new coins
public struct MintAction<phantom CoinType> has store {
    amount: u64,
}
/// [ACTION] burns coins
public struct BurnAction<phantom CoinType> has store {
    amount: u64,
}
/// [ACTION] updates a CoinMetadata object using a locked TreasuryCap 
public struct UpdateAction<phantom CoinType> has store { 
    symbol: Option<ascii::String>,
    name: Option<String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
}

// === [COMMAND] Public functions ===

/// Only a member with the LockCommand role can lock a TreasuryCap
public fun lock_cap<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    treasury_cap: TreasuryCap<CoinType>,
    max_supply: Option<u64>,
) {
    account.verify(auth);

    let rules = CurrencyRules<CoinType> { 
        max_supply,
        total_minted: 0,
        total_burned: 0,
        can_mint: true,
        can_burn: true,
        can_update_symbol: true,
        can_update_name: true,
        can_update_description: true,
        can_update_icon: true,
    };
    account.add_managed_struct(CurrencyRulesKey<CoinType> {}, rules, version::current());
    account.add_managed_object(TreasuryCapKey<CoinType> {}, treasury_cap, version::current());
}

public fun has_cap<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_object(TreasuryCapKey<CoinType> {})
}

public fun borrow_rules<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>
): &CurrencyRules<CoinType> {
    account.borrow_managed_struct(CurrencyRulesKey<CoinType> {}, version::current())
}

// getters
public fun coin_type_supply<Config, Outcome, CoinType>(account: &Account<Config, Outcome>): u64 {
    let cap: &TreasuryCap<CoinType> = account.borrow_managed_object(TreasuryCapKey<CoinType> {}, version::current());
    cap.total_supply()
}

public fun max_supply<CoinType>(lock: &CurrencyRules<CoinType>): Option<u64> {
    lock.max_supply
}

public fun total_minted<CoinType>(lock: &CurrencyRules<CoinType>): u64 {
    lock.total_minted
}

public fun total_burned<CoinType>(lock: &CurrencyRules<CoinType>): u64 {
    lock.total_burned
}

public fun can_mint<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_mint
}

public fun can_burn<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_burn
}

public fun can_update_symbol<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_update_symbol
}

public fun can_update_name<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_update_name
}

public fun can_update_description<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_update_description
}

public fun can_update_icon<CoinType>(lock: &CurrencyRules<CoinType>): bool {
    lock.can_update_icon
}

/// Anyone can burn coins they own if enabled
public fun public_burn<Config, Outcome, CoinType>(
    account: &mut Account<Config, Outcome>, 
    coin: Coin<CoinType>
) {
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);

    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    assert!(rules_mut.can_burn, EBurnDisabled);
    rules_mut.total_burned = rules_mut.total_burned + coin.value();

    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version::current());
    cap_mut.burn(coin);
}

// === [ACTION] Public functions ===

public fun new_disable<Config, Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>,
    mint: bool,
    burn: bool,
    update_symbol: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    assert!(mint || burn || update_symbol || update_name || update_description || update_icon, ENoChange);
    account.add_action(
        intent,
        DisableAction<CoinType> { mint, burn, update_name, update_symbol, update_description, update_icon }, 
        version_witness, 
        intent_witness
    );
}

public fun do_disable<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action: &DisableAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let (mint, burn, update_symbol, update_name, update_description, update_icon) = 
        (action.mint, action.burn, action.update_symbol, action.update_name, action.update_description, action.update_icon);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version_witness);
    // if disabled, can be true or false, it has no effect
    if (mint) rules_mut.can_mint = false;
    if (burn) rules_mut.can_burn = false;
    if (update_symbol) rules_mut.can_update_symbol = false;
    if (update_name) rules_mut.can_update_name = false;
    if (update_description) rules_mut.can_update_description = false;
    if (update_icon) rules_mut.can_update_icon = false;
}

public fun delete_disable<CoinType>(expired: &mut Expired) {
    let DisableAction<CoinType> { .. } = expired.remove_action();
}

public fun new_mint<Config, Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>, 
    amount: u64,
    version_witness: VersionWitness,
    intent_witness: IW,    
) {
    account.add_action(intent, MintAction<CoinType> { amount }, version_witness, intent_witness);
}

public fun do_mint<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version_witness: VersionWitness,
    intent_witness: IW, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let action: &MintAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let amount = action.amount;
    let total_supply = coin_type_supply<Config, Outcome, CoinType>(account);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version_witness);
    
    assert!(rules_mut.can_mint, EMintDisabled);
    if (rules_mut.max_supply.is_some()) assert!(amount + total_supply <= *rules_mut.max_supply.borrow(), EMaxSupply);
    rules_mut.total_minted = rules_mut.total_minted + amount;
    
    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version_witness);
    cap_mut.mint(amount, ctx)
}

public fun delete_mint<CoinType>(expired: &mut Expired) {
    let MintAction<CoinType> { .. } = expired.remove_action();
}

public fun new_burn<Config, Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>, 
    account: &Account<Config, Outcome>, 
    amount: u64, 
    version_witness: VersionWitness,
    intent_witness: IW
) {
    account.add_action(intent, BurnAction<CoinType> { amount }, version_witness, intent_witness);
}

public fun do_burn<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    coin: Coin<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW, 
) {
    let action: &BurnAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let amount = action.amount;
    assert!(amount == coin.value(), EWrongValue);
    
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version_witness);
    assert!(rules_mut.can_burn, EBurnDisabled);
    rules_mut.total_burned = rules_mut.total_burned + amount;

    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version_witness);
    cap_mut.burn(coin);
}

public fun delete_burn<CoinType>(expired: &mut Expired) {
    let BurnAction<CoinType> { .. } = expired.remove_action();
}

public fun new_update<Config, Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>,
    account: &Account<Config, Outcome>, 
    symbol: Option<ascii::String>,
    name: Option<String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    assert!(symbol.is_some() || name.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    account.add_action(intent, UpdateAction<CoinType> { symbol, name, description, icon_url }, version_witness, intent_witness);
}

public fun do_update<Config, Outcome, CoinType, IW: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    let action: &UpdateAction<CoinType> = account.process_action(executable, version_witness, intent_witness);
    let (symbol, name, description, icon_url) = (action.symbol, action.name, action.description, action.icon_url);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version_witness);

    if (!rules_mut.can_update_symbol) assert!(symbol.is_none(), ECannotUpdateSymbol);
    if (!rules_mut.can_update_name) assert!(name.is_none(), ECannotUpdateName);
    if (!rules_mut.can_update_description) assert!(description.is_none(), ECannotUpdateDescription);
    if (!rules_mut.can_update_icon) assert!(icon_url.is_none(), ECannotUpdateIcon);
    
    let (default_symbol, default_name, default_description, default_icon_url) = (metadata.get_symbol(), metadata.get_name(), metadata.get_description(), metadata.get_icon_url().extract().inner_url());
    let cap: &TreasuryCap<CoinType> = account.borrow_managed_object(TreasuryCapKey<CoinType> {}, version_witness);

    cap.update_symbol(metadata, symbol.get_with_default(default_symbol));
    cap.update_name(metadata, name.get_with_default(default_name));
    cap.update_description(metadata, description.get_with_default(default_description));
    cap.update_icon_url(metadata, icon_url.get_with_default(default_icon_url));
}

public fun delete_update<CoinType>(expired: &mut Expired) {
    let UpdateAction<CoinType> { .. } = expired.remove_action();
}

// === Test functions ===

#[test_only] 
public fun toggle_can_mint<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_mint = !rules_mut.can_mint;
}

#[test_only] 
public fun toggle_can_burn<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_burn = !rules_mut.can_burn;
}

#[test_only] 
public fun toggle_can_update_symbol<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_symbol = !rules_mut.can_update_symbol;
}

#[test_only] 
public fun toggle_can_update_name<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_name = !rules_mut.can_update_name;
}

#[test_only] 
public fun toggle_can_update_description<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_description = !rules_mut.can_update_description;
}

#[test_only] 
public fun toggle_can_update_icon<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_icon = !rules_mut.can_update_icon;
}