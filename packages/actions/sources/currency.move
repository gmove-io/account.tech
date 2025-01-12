/// Members can lock a TreasuryCap in the Account to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Account and burn one of its coin.
/// It uses a Withdraw action. The burnt Coin could be merged beforehand.
/// 
/// Coins minted by the account can also be transferred or paid to any address.

module account_actions::currency;

// === Imports ===

use std::{
    type_name,
    string::String,
    ascii,
};
use sui::{
    transfer::Receiving,
    coin::{Coin, TreasuryCap, CoinMetadata},
};
use account_protocol::{
    account::Account,
    executable::Executable,
    auth::Auth
};
use account_actions::{
    vesting,
    version,
};

// === Errors ===

#[error]
const ENoChange: vector<u8> = b"Proposal must change something";
#[error]
const EWrongValue: vector<u8> = b"Coin has the wrong value";
#[error]
const ENoLock: vector<u8> = b"No lock for this coin type";
#[error]
const EAmountsRecipentsNotSameLength: vector<u8> = b"Transfer amounts and recipients are not the same length";
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
#[error]
const EWrongObject: vector<u8> = b"Wrong object provided";

// === Structs ===    

public struct Witness() has drop;

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
public struct DisableAction<phantom CoinType> has drop, store {
    mint: bool,
    burn: bool,
    update_symbol: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
}
/// [ACTION] mints and transfers new coins
public struct MintAndTransferAction<phantom CoinType> has drop, store {
    // amount of coins to mint
    amounts: vector<u64>,
    // addresses to transfer to
    recipients: vector<address>,
}
public struct MintAndVestingAction<phantom CoinType> has drop, store {
    // total amount to vest
    total_amount: u64,
    // timestamp when coins can start to be claimed
    start_timestamp: u64,
    // timestamp when balance is totally unlocked
    end_timestamp: u64,
    // address to pay
    recipient: address,
}
/// [ACTION] burns coins
public struct BurnAction<phantom CoinType> has drop, store {
    // id of the coin to burn
    coin_id: ID,
}
/// [ACTION] updates a CoinMetadata object using a locked TreasuryCap 
public struct UpdateAction<phantom CoinType> has drop, store { 
    symbol: Option<ascii::String>,
    name: Option<String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
}

// === [COMMAND] Public functions ===

/// Only a member with the LockCommand role can lock a TreasuryCap
public fun lock_cap<Config, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    treasury_cap: TreasuryCap<CoinType>,
    max_supply: Option<u64>,
) {
    auth.verify_with_role<Witness>(account.addr(), b"".to_string());

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

public fun has_cap<Config, CoinType>(
    account: &Account<Config>
): bool {
    account.has_managed_object(TreasuryCapKey<CoinType> {})
}

public fun borrow_rules<Config, CoinType>(
    account: &Account<Config>
): &CurrencyRules<CoinType> {
    account.borrow_managed_struct(CurrencyRulesKey<CoinType> {}, version::current())
}

// getters
public fun coin_type_supply<Config, CoinType>(account: &Account<Config>): u64 {
    let cap: &TreasuryCap<CoinType> = 
        account.borrow_managed_object(TreasuryCapKey<CoinType> {}, version::current());
    cap.total_supply()
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
    lock.can_mint
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
public fun public_burn<Config, CoinType>(
    account: &mut Account<Config>, 
    coin: Coin<CoinType>
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);

    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    assert!(rules_mut.can_burn, EBurnDisabled);
    rules_mut.total_burned = rules_mut.total_burned + coin.value();

    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version::current());
    cap_mut.burn(coin);
}

// === [PROPOSAL] Public functions ===

// step 1: propose to disable minting for the coin forever
public fun request_disable<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
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
    outcome: Outcome,
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);
    assert!(disable_mint || disable_burn || disable_update_symbol || disable_update_name || disable_update_description || disable_update_icon, ENoChange);

    let action = DisableAction<CoinType> { 
        mint: disable_mint, 
        burn: disable_burn, 
        update_name: disable_update_name, 
        update_symbol: disable_update_symbol, 
        update_description: disable_update_description, 
        update_icon: disable_update_icon 
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
        type_to_name<CoinType>(), // the coin type is the issuer name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: disable minting for the coin forever
public fun execute_disable<Config, CoinType>(
    mut executable: Executable<DisableAction<CoinType>>,
    account: &mut Account<Config>,
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    // if disabled, can be true or false, it has no effect
    if (action_mut.mint) rules_mut.can_mint = false;
    if (action_mut.burn) rules_mut.can_burn = false;
    if (action_mut.update_symbol) rules_mut.can_update_symbol = false;
    if (action_mut.update_name) rules_mut.can_update_name = false;
    if (action_mut.update_description) rules_mut.can_update_description = false;
    if (action_mut.update_icon) rules_mut.can_update_icon = false;

    executable.destroy(version::current(), Witness());
}

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun request_mint_and_transfer<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    outcome: Outcome,
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_mint, EMintDisabled);
    
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    let current_supply = coin_type_supply<Config, CoinType>(account);
    if (rules.max_supply.is_some()) assert!(sum + current_supply <= *rules.max_supply.borrow(), EMaxSupply);

    let action = MintAndTransferAction<CoinType> { amounts, recipients };

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
        type_to_name<CoinType>(), // the coin type is the issuer name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint_and_transfer<Config, CoinType>(
    mut executable: Executable<MintAndTransferAction<CoinType>>,
    account: &mut Account<Config>,
    ctx: &mut TxContext
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    
    action_mut.amounts.zip_do!(action_mut.recipients, |amount, recipient| {
        let current_supply = coin_type_supply<Config, CoinType>(account);
        let rules_mut: &mut CurrencyRules<CoinType> = 
            account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
        
        assert!(rules_mut.can_mint, EMintDisabled);
        if (rules_mut.max_supply.is_some()) assert!(amount + current_supply <= *rules_mut.max_supply.borrow(), EMaxSupply);
        rules_mut.total_minted = rules_mut.total_minted + amount;
        
        let cap_mut: &mut TreasuryCap<CoinType> = 
            account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version::current());
        let coin = cap_mut.mint(amount, ctx);

        transfer::public_transfer(coin, recipient);
    });
    
    executable.destroy(version::current(), Witness());
}

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun request_mint_and_vesting<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    total_amount: u64,
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    outcome: Outcome,
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);

    assert!(rules.can_mint, EMintDisabled);
    let current_supply = coin_type_supply<Config, CoinType>(account);
    if (rules.max_supply.is_some()) assert!(total_amount + current_supply <= *rules.max_supply.borrow(), EMaxSupply);

    let action = MintAndVestingAction<CoinType> { 
        total_amount, 
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
        type_to_name<CoinType>(), // the coin type is the issuer name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint_and_vesting<Config, CoinType>(
    mut executable: Executable<MintAndVestingAction<CoinType>>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    
    let total_supply = coin_type_supply<Config, CoinType>(account);
    let rules_mut: &mut CurrencyRules<CoinType> = 
        account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    
    assert!(rules_mut.can_mint, EMintDisabled);
    if (rules_mut.max_supply.is_some()) assert!(action_mut.total_amount + total_supply <= *rules_mut.max_supply.borrow(), EMaxSupply);
    rules_mut.total_minted = rules_mut.total_minted + action_mut.total_amount;
    
    let cap_mut: &mut TreasuryCap<CoinType> = 
        account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version::current());
    let coin = cap_mut.mint(action_mut.total_amount, ctx);

    vesting::create_stream(
        coin, 
        action_mut.start_timestamp, 
        action_mut.end_timestamp, 
        action_mut.recipient, 
        ctx
    );
    
    executable.destroy(version::current(), Witness());
}

// step 1: propose to burn an amount of a coin owned by the account
public fun request_burn<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    coin_id: ID,
    outcome: Outcome,
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_burn, EBurnDisabled);

    account.intents_mut(version::current()).lock(coin_id); // throws if already locked
    let action = BurnAction<CoinType> { coin_id };

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
        type_to_name<CoinType>(), // the coin type is the issuer name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: burn the coin initially owned by the account
public fun execute_burn<Config, CoinType>(
    mut executable: Executable<BurnAction<CoinType>>,
    account: &mut Account<Config>,
    receiving: Receiving<Coin<CoinType>>,
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    account.intents_mut(version::current()).unlock(action_mut.coin_id);
    assert!(receiving.receiving_object_id() == action_mut.coin_id, EWrongObject);
    let coin = account.receive(receiving, version::current());
    
    let rules_mut: &mut CurrencyRules<CoinType> = 
        account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    assert!(rules_mut.can_burn, EBurnDisabled);
    rules_mut.total_burned = rules_mut.total_burned + coin.value();

    let cap_mut: &mut TreasuryCap<CoinType> = 
        account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version::current());
    cap_mut.burn(coin);

    executable.destroy(version::current(), Witness());
}

// TODO: add a function to delete burn intent and unlock the object

// step 1: propose to update the CoinMetadata
public fun request_update<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    key: String,
    description: String,
    execution_time: u64,
    expiration_time: u64,
    md_symbol: Option<ascii::String>,
    md_name: Option<String>,
    md_description: Option<String>,
    md_icon: Option<ascii::String>,
    outcome: Outcome,
) {
    assert!(has_cap<Config, CoinType>(account), ENoLock);
    assert!(md_symbol.is_some() || md_name.is_some() || md_description.is_some() || md_icon.is_some(), ENoChange);

    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    if (!rules.can_update_symbol) assert!(md_symbol.is_none(), ECannotUpdateSymbol);
    if (!rules.can_update_name) assert!(md_name.is_none(), ECannotUpdateName);
    if (!rules.can_update_description) assert!(md_description.is_none(), ECannotUpdateDescription);
    if (!rules.can_update_icon) assert!(md_icon.is_none(), ECannotUpdateIcon);

    let action = UpdateAction<CoinType> { 
        symbol: md_symbol, 
        name: md_name, 
        description: md_description, 
        icon_url: md_icon 
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
        type_to_name<CoinType>(), // the coin type is the auth name 
    );
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<Config, CoinType>(
    mut executable: Executable<UpdateAction<CoinType>>,
    account: &mut Account<Config>,
    metadata: &mut CoinMetadata<CoinType>,
) {
    let action_mut = executable.action_mut(account.addr(), version::current(), Witness());
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());

    if (!rules_mut.can_update_symbol) assert!(action_mut.symbol.is_none(), ECannotUpdateSymbol);
    if (!rules_mut.can_update_name) assert!(action_mut.name.is_none(), ECannotUpdateName);
    if (!rules_mut.can_update_description) assert!(action_mut.description.is_none(), ECannotUpdateDescription);
    if (!rules_mut.can_update_icon) assert!(action_mut.icon_url.is_none(), ECannotUpdateIcon);
    
    let (default_symbol, default_name, default_description, default_icon_url) = (metadata.get_symbol(), metadata.get_name(), metadata.get_description(), metadata.get_icon_url().extract().inner_url());
    let cap: &TreasuryCap<CoinType> = account.borrow_managed_object(TreasuryCapKey<CoinType> {}, version::current());

    cap.update_symbol(metadata, action_mut.symbol.get_with_default(default_symbol));
    cap.update_name(metadata, action_mut.name.get_with_default(default_name));
    cap.update_description(metadata, action_mut.description.get_with_default(default_description));
    cap.update_icon_url(metadata, action_mut.icon_url.get_with_default(default_icon_url));

    executable.destroy(version::current(), Witness());
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}

// === Test functions ===

#[test_only] 
public fun toggle_can_mint<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_mint = !rules_mut.can_mint;
}

#[test_only] 
public fun toggle_can_burn<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_burn = !rules_mut.can_burn;
}

#[test_only] 
public fun toggle_can_update_symbol<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_symbol = !rules_mut.can_update_symbol;
}

#[test_only] 
public fun toggle_can_update_name<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_name = !rules_mut.can_update_name;
}

#[test_only] 
public fun toggle_can_update_description<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_description = !rules_mut.can_update_description;
}

#[test_only] 
public fun toggle_can_update_icon<Config, CoinType>(account: &mut Account<Config>) {
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version::current());
    rules_mut.can_update_icon = !rules_mut.can_update_icon;
}