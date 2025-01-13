/// Members can lock a TreasuryCap in the Account to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Account and burn one of its coin.
/// It uses a Withdraw action. The burnt Coin could be merged beforehand.
/// 
/// Coins minted by the account can also be transferred or paid to any address.

module account_actions::currency;

// === Imports ===

use std::{
    type_name::{Self, TypeName},
    string::String,
    ascii,
};
use sui::{
    transfer::Receiving,
    coin::{Coin, TreasuryCap, CoinMetadata},
};
use account_protocol::{
    account::Account,
    intents::{Intent, Expired},
    executable::Executable,
    auth::Auth
};
use account_actions::{
    owned,
    transfer as acc_transfer,
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

/// [PROPOSAL] witness defining the TreasuryCap lock command, and associated role
public struct LockCommand() has drop;
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
    auth.verify_with_role<LockCommand>(account.addr(), b"".to_string());

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
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);

    let mut intent = account.create_intent(
        auth,
        key, 
        description, 
        vector[execution_time], 
        expiration_time, 
        outcome,
        version::current(),
        DisableIntent(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        ctx
    );

    new_disable<Outcome, CoinType, DisableIntent>(
        &mut intent, 
        disable_mint,
        disable_burn,
        disable_update_symbol,
        disable_update_name,
        disable_update_description,
        disable_update_icon,
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
    do_disable<Config, Outcome, CoinType, DisableIntent>(&mut executable, account, version::current(), DisableIntent());   
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
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_mint, EMintDisabled);
    let supply = coin_type_supply<Config, Outcome, CoinType>(account);
    if (rules.max_supply.is_some()) assert!(amount + supply <= *rules.max_supply.borrow(), EMaxSupply);

    let mut intent = account.create_intent(
        auth,
        key, 
        description, 
        execution_times, 
        expiration_time, 
        outcome,
        version::current(),
        MintIntent(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        ctx
    );

    new_mint<Outcome, CoinType, MintIntent>(
        &mut intent, 
        amount, 
        MintIntent()
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
    let coin = do_mint<Config, Outcome, CoinType, MintIntent>(&mut executable, account, version::current(), MintIntent(), ctx);
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
    execution_times: vector<u64>,
    expiration_time: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_burn, EBurnDisabled);

    let mut intent = account.create_intent(
        auth,
        key, 
        description, 
        execution_times, 
        expiration_time, 
        outcome,
        version::current(),
        BurnIntent(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        ctx
    );

    owned::new_withdraw(&mut intent, coin_id, BurnIntent());
    new_burn<Outcome, CoinType, BurnIntent>(
        &mut intent, 
        amount, 
        BurnIntent()
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
    do_burn<Config, Outcome, CoinType, BurnIntent>(&mut executable, account, coin, version::current(), BurnIntent());
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
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    if (!rules.can_update_symbol) assert!(md_symbol.is_none(), ECannotUpdateSymbol);
    if (!rules.can_update_name) assert!(md_name.is_none(), ECannotUpdateName);
    if (!rules.can_update_description) assert!(md_description.is_none(), ECannotUpdateDescription);
    if (!rules.can_update_icon) assert!(md_icon.is_none(), ECannotUpdateIcon);


    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        UpdateIntent(),
        type_to_name<CoinType>(), // the coin type is the auth name 
        ctx
    );

    new_update<Outcome, CoinType, UpdateIntent>(
        &mut intent, 
        md_symbol, 
        md_name, 
        md_description, 
        md_icon, 
        UpdateIntent()
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
    do_update(&mut executable, account, metadata, version::current(), UpdateIntent());
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
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_mint, EMintDisabled);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (rules.max_supply.is_some()) assert!(sum <= *rules.max_supply.borrow(), EMaxSupply);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        execution_times,
        expiration_time,
        outcome,
        version::current(),
        TransferIntent(),
        b"".to_string(),
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        new_mint<Outcome, CoinType, TransferIntent>(
            &mut intent, 
            amount, 
            TransferIntent()
        );
        acc_transfer::new_transfer(&mut intent, recipient, TransferIntent());
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
    let coin: Coin<CoinType> = do_mint(executable, account, version::current(), TransferIntent(), ctx);
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
    assert!(has_cap<Config, Outcome, CoinType>(account), ENoLock);
    let rules: &CurrencyRules<CoinType> = borrow_rules(account);
    assert!(rules.can_mint, EMintDisabled);
    if (rules.max_supply.is_some()) assert!(total_amount <= *rules.max_supply.borrow(), EMaxSupply);

    let mut intent = account.create_intent(
        auth,
        key,
        description,
        vector[execution_time],
        expiration_time,
        outcome,
        version::current(),
        VestingIntent(),
        b"".to_string(),
        ctx
    );

    new_mint<Outcome, CoinType, VestingIntent>(
        &mut intent, 
        total_amount, 
        VestingIntent()
    );
    vesting::new_vesting(&mut intent, start_timestamp, end_timestamp, recipient, VestingIntent());
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
    let coin: Coin<CoinType> = do_mint(&mut executable, account, version::current(), VestingIntent(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), VestingIntent(), ctx);
    account.confirm_execution(executable, version::current(), VestingIntent());
}

// === [ACTION] Public functions ===

public fun new_disable<Outcome, CoinType, W: drop>(
    intent: &mut Intent<Outcome>,
    mint: bool,
    burn: bool,
    update_symbol: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
    witness: W,
) {
    assert!(mint || burn || update_symbol || update_name || update_description || update_icon, ENoChange);
    intent.add_action(DisableAction<CoinType> { mint, burn, update_name, update_symbol, update_description, update_icon }, witness);
}

public fun do_disable<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let action: &DisableAction<CoinType> = account.process_action(executable, version, witness);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version);
    // if disabled, can be true or false, it has no effect
    if (action.mint) rules_mut.can_mint = false;
    if (action.burn) rules_mut.can_burn = false;
    if (action.update_symbol) rules_mut.can_update_symbol = false;
    if (action.update_name) rules_mut.can_update_name = false;
    if (action.update_description) rules_mut.can_update_description = false;
    if (action.update_icon) rules_mut.can_update_icon = false;
}

public fun delete_disable<CoinType>(expired: &mut Expired) {
    let DisableAction<CoinType> { .. } = expired.remove_action();
}

public fun new_mint<Outcome, CoinType, W: drop>(
    intent: &mut Intent<Outcome>, 
    amount: u64,
    witness: W,    
) {
    intent.add_action(MintAction<CoinType> { amount }, witness);
}

public fun do_mint<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let action: &MintAction<CoinType> = account.process_action(executable, version, witness);
    let total_supply = coin_type_supply<Config, Outcome, CoinType>(account);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version);
    
    assert!(rules_mut.can_mint, EMintDisabled);
    if (rules_mut.max_supply.is_some()) assert!(action.amount + total_supply <= *rules_mut.max_supply.borrow(), EMaxSupply);
    rules_mut.total_minted = rules_mut.total_minted + action.amount;
    
    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version);
    cap_mut.mint(action.amount, ctx)
}

public fun delete_mint<CoinType>(expired: &mut Expired) {
    let MintAction<CoinType> { .. } = expired.remove_action();
}

public fun new_burn<Outcome, CoinType, W: drop>(
    intent: &mut Intent<Outcome>, 
    amount: u64, 
    witness: W
) {
    intent.add_action(BurnAction<CoinType> { amount }, witness);
}

public fun do_burn<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    coin: Coin<CoinType>,
    version: TypeName,
    witness: W, 
) {
    let action: &BurnAction<CoinType> = account.process_action(executable, version, witness);
    assert!(action.amount == coin.value(), EWrongValue);
    
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version);
    assert!(rules_mut.can_burn, EBurnDisabled);
    rules_mut.total_burned = rules_mut.total_burned + action.amount;

    let cap_mut: &mut TreasuryCap<CoinType> = account.borrow_managed_object_mut(TreasuryCapKey<CoinType> {}, version);
    cap_mut.burn(coin);
}

public fun delete_burn<CoinType>(expired: &mut Expired) {
    let BurnAction<CoinType> { .. } = expired.remove_action();
}

public fun new_update<Outcome, CoinType, W: drop>(
    intent: &mut Intent<Outcome>,
    symbol: Option<ascii::String>,
    name: Option<String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
    witness: W,
) {
    assert!(symbol.is_some() || name.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    intent.add_action(UpdateAction<CoinType> { symbol, name, description, icon_url }, witness);
}

public fun do_update<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
    version: TypeName,
    witness: W,
) {
    let action: &UpdateAction<CoinType> = account.process_action(executable, version, witness);
    let rules_mut: &mut CurrencyRules<CoinType> = account.borrow_managed_struct_mut(CurrencyRulesKey<CoinType> {}, version);

    if (!rules_mut.can_update_symbol) assert!(action.symbol.is_none(), ECannotUpdateSymbol);
    if (!rules_mut.can_update_name) assert!(action.name.is_none(), ECannotUpdateName);
    if (!rules_mut.can_update_description) assert!(action.description.is_none(), ECannotUpdateDescription);
    if (!rules_mut.can_update_icon) assert!(action.icon_url.is_none(), ECannotUpdateIcon);
    
    let (default_symbol, default_name, default_description, default_icon_url) = (metadata.get_symbol(), metadata.get_name(), metadata.get_description(), metadata.get_icon_url().extract().inner_url());
    let cap: &TreasuryCap<CoinType> = account.borrow_managed_object(TreasuryCapKey<CoinType> {}, version);

    cap.update_symbol(metadata, action.symbol.get_with_default(default_symbol));
    cap.update_name(metadata, action.name.get_with_default(default_name));
    cap.update_description(metadata, action.description.get_with_default(default_description));
    cap.update_icon_url(metadata, action.icon_url.get_with_default(default_icon_url));
}

public fun delete_update<CoinType>(expired: &mut Expired) {
    let UpdateAction<CoinType> { .. } = expired.remove_action();
}


// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
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