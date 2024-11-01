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
    proposals::{Proposal, Expired},
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

/// Dynamic Field key for the CurrencyLock
public struct CurrencyKey<phantom CoinType> has copy, drop, store {}
/// Dynamic Field wrapper restricting access to a TreasuryCap, permissions are disabled forever if set
public struct CurrencyLock<phantom CoinType> has store {
    // the cap to lock
    treasury_cap: TreasuryCap<CoinType>,
    // coin can have a fixed supply, can_mint must be true 
    max_supply: Option<u64>,
    // total amount minted
    total_minted: u64,
    // total amount burnt
    total_burnt: u64,
    // permissions
    can_mint: bool,
    can_burn: bool,
    can_update_symbol: bool,
    can_update_name: bool,
    can_update_description: bool,
    can_update_icon: bool,
}

/// [PROPOSAL] disables one or more permissions
public struct DisableProposal() has copy, drop;
/// [PROPOSAL] mints new coins from a locked TreasuryCap
public struct MintProposal() has copy, drop;
/// [PROPOSAL] burns coins from the account using a locked TreasuryCap
public struct BurnProposal() has copy, drop;
/// [PROPOSAL] updates the CoinMetadata associated with a locked TreasuryCap
public struct UpdateProposal() has copy, drop;
/// [PROPOSAL] acc_transfer from a minted coin 
public struct TransferProposal() has copy, drop;
/// [PROPOSAL] pays from a minted coin
public struct PayProposal() has copy, drop;

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

// === [MEMBER] Public functions ===

/// Only a member can lock a TreasuryCap and borrow it.

public fun lock_cap<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    treasury_cap: TreasuryCap<CoinType>,
    max_supply: Option<u64>,
) {
    auth.verify(account.addr());

    let treasury_lock = CurrencyLock { 
        treasury_cap,
        max_supply,
        total_minted: 0,
        total_burnt: 0,
        can_mint: true,
        can_burn: true,
        can_update_symbol: true,
        can_update_name: true,
        can_update_description: true,
        can_update_icon: true,
    };
    account.add_managed_asset(CurrencyKey<CoinType> {}, treasury_lock, version::current());
}

public fun has_lock<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_asset(CurrencyKey<CoinType> {})
}

public fun borrow_lock<Config, Outcome, CoinType>(
    account: &Account<Config, Outcome>
): &CurrencyLock<CoinType> {
    account.borrow_managed_asset(CurrencyKey<CoinType> {}, version::current())
}

// getters
public fun supply<CoinType>(lock: &CurrencyLock<CoinType>): u64 {
    lock.treasury_cap.total_supply()
}

public fun total_minted<CoinType>(lock: &CurrencyLock<CoinType>): u64 {
    lock.total_minted
}

public fun total_burnt<CoinType>(lock: &CurrencyLock<CoinType>): u64 {
    lock.total_burnt
}

public fun can_mint<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_mint
}

public fun can_burn<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_mint
}

public fun can_update_symbol<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_symbol
}

public fun can_update_name<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_name
}

public fun can_update_description<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_description
}

public fun can_update_icon<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_icon
}

/// Anyone can burn coins they own if enabled
public fun public_burn<Config, Outcome, CoinType>(
    account: &mut Account<Config, Outcome>, 
    coin: Coin<CoinType>
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);

    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    assert!(lock_mut.can_burn, EBurnDisabled);

    lock_mut.total_burnt = lock_mut.total_burnt + coin.value();
    lock_mut.treasury_cap.burn(coin);
}

// === [PROPOSAL] Public functions ===

// step 1: propose to disable minting for the coin forever
public fun propose_disable<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    disable_mint: bool,
    disable_burn: bool,
    disable_update_symbol: bool,
    disable_update_name: bool,
    disable_update_description: bool,
    disable_update_icon: bool,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        DisableProposal(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    new_disable<Outcome, CoinType, DisableProposal>(
        &mut proposal, 
        disable_mint,
        disable_burn,
        disable_update_symbol,
        disable_update_name,
        disable_update_description,
        disable_update_icon,
        DisableProposal()
    );
    account.add_proposal(proposal, version::current(), DisableProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: disable minting for the coin forever
public fun execute_disable<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    do_disable<Config, Outcome, CoinType, DisableProposal>(&mut executable, account, version::current(), DisableProposal());   
    executable.destroy(version::current(), DisableProposal());
}

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun propose_mint<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);
    let lock: &CurrencyLock<CoinType> = borrow_lock(account);
    assert!(lock.can_mint, EMintDisabled);
    if (lock.max_supply.is_some()) assert!(amount + lock.supply() <= *lock.max_supply.borrow(), EMaxSupply);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        MintProposal(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    new_mint<Outcome, CoinType, MintProposal>(
        &mut proposal, 
        amount, 
        MintProposal()
    );
    account.add_proposal(proposal, version::current(), MintProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    let coin = do_mint<Config, Outcome, CoinType, MintProposal>(&mut executable, account, version::current(), MintProposal(), ctx);
    account.keep(coin);
    executable.destroy(version::current(), MintProposal());
}

// step 1: propose to burn an amount of a coin owned by the account
public fun propose_burn<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);
    let lock: &CurrencyLock<CoinType> = borrow_lock(account);
    assert!(lock.can_burn, EBurnDisabled);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        BurnProposal(), 
        type_to_name<CoinType>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    owned::new_withdraw(&mut proposal, coin_id, BurnProposal());
    new_burn<Outcome, CoinType, BurnProposal>(
        &mut proposal, 
        amount, 
        BurnProposal()
    );

    account.add_proposal(proposal, version::current(), BurnProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: burn the coin initially owned by the account
public fun execute_burn<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    receiving: Receiving<Coin<CoinType>>,
) {
    let coin = owned::do_withdraw(&mut executable, account, receiving, version::current(), BurnProposal());
    do_burn<Config, Outcome, CoinType, BurnProposal>(&mut executable, account, coin, version::current(), BurnProposal());
    executable.destroy(version::current(), BurnProposal());
}

// step 1: propose to update the CoinMetadata
public fun propose_update<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    md_symbol: Option<ascii::String>,
    md_name: Option<String>,
    md_description: Option<String>,
    md_icon: Option<ascii::String>,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);
    let lock: &CurrencyLock<CoinType> = borrow_lock(account);
    if (!lock.can_update_symbol) assert!(md_symbol.is_none(), ECannotUpdateSymbol);
    if (!lock.can_update_name) assert!(md_name.is_none(), ECannotUpdateName);
    if (!lock.can_update_description) assert!(md_description.is_none(), ECannotUpdateDescription);
    if (!lock.can_update_icon) assert!(md_icon.is_none(), ECannotUpdateIcon);


    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        UpdateProposal(),
        type_to_name<CoinType>(), // the coin type is the auth name 
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_update<Outcome, CoinType, UpdateProposal>(
        &mut proposal, 
        md_symbol, 
        md_name, 
        md_description, 
        md_icon, 
        UpdateProposal()
    );
    account.add_proposal(proposal, version::current(), UpdateProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<Config, Outcome, CoinType>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
) {
    do_update(&mut executable, account, metadata, version::current(), UpdateProposal());
    executable.destroy(version::current(), UpdateProposal());
}

// step 1: propose to send managed coins
public fun propose_transfer<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

    let lock: &CurrencyLock<CoinType> = borrow_lock(account);
    assert!(lock.can_mint, EMintDisabled);
    let sum = amounts.fold!(0, |sum, amount| sum + amount);
    if (lock.max_supply.is_some()) assert!(sum <= *lock.max_supply.borrow(), EMaxSupply);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        TransferProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        new_mint<Outcome, CoinType, TransferProposal>(
            &mut proposal, 
            amount, 
            TransferProposal()
        );
        acc_transfer::new_transfer(&mut proposal, recipient, TransferProposal());
    });

    account.add_proposal(proposal, version::current(), TransferProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, CoinType>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = do_mint(executable, account, version::current(), TransferProposal(), ctx);
    acc_transfer::do_transfer(executable, account, coin, version::current(), TransferProposal());
}

// step 5: complete acc_transfer and destroy the executable
public fun complete_transfer(executable: Executable) {
    executable.destroy(version::current(), TransferProposal());
}

// step 1: propose to pay from a minted coin
public fun propose_vesting<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    total_amount: u64,
    start_timestamp: u64, 
    end_timestamp: u64, 
    recipient: address,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);
    let lock: &CurrencyLock<CoinType> = borrow_lock(account);
    assert!(lock.can_mint, EMintDisabled);
    if (lock.max_supply.is_some()) assert!(total_amount <= *lock.max_supply.borrow(), EMaxSupply);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        version::current(),
        PayProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_mint<Outcome, CoinType, PayProposal>(
        &mut proposal, 
        total_amount, 
        PayProposal()
    );
    vesting::new_vesting(&mut proposal, start_timestamp, end_timestamp, recipient, PayProposal());
    account.add_proposal(proposal, version::current(), PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_vesting<Config, Outcome, CoinType>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = do_mint(&mut executable, account, version::current(), PayProposal(), ctx);
    vesting::do_vesting(&mut executable, account, coin, version::current(), PayProposal(), ctx);
    executable.destroy(version::current(), PayProposal());
}

// === [ACTION] Public functions ===

public fun new_disable<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>,
    mint: bool,
    burn: bool,
    update_symbol: bool,
    update_name: bool,
    update_description: bool,
    update_icon: bool,
    witness: W,
) {
    assert!(mint || burn || update_symbol || update_name || update_description || update_icon, ENoChange);
    proposal.add_action(DisableAction<CoinType> { mint, burn, update_name, update_symbol, update_description, update_icon }, witness);
}

public fun do_disable<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let DisableAction<CoinType> { mint, burn, update_name, update_symbol, update_description, update_icon } = 
        executable.action(account.addr(), version, witness);
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);
    // if disabled, can be true or false, it has no effect
    if (mint) lock_mut.can_mint = false;
    if (burn) lock_mut.can_burn = false;
    if (update_symbol) lock_mut.can_update_symbol = false;
    if (update_name) lock_mut.can_update_name = false;
    if (update_description) lock_mut.can_update_description = false;
    if (update_icon) lock_mut.can_update_icon = false;
}

public fun delete_disable_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let DisableAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_mint<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    amount: u64,
    witness: W,    
) {
    proposal.add_action(MintAction<CoinType> { amount }, witness);
}

public fun do_mint<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let MintAction<CoinType> { amount } = executable.action(account.addr(), version, witness);
    
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);
    assert!(lock_mut.can_mint, EMintDisabled);
    if (lock_mut.max_supply.is_some()) assert!(amount + lock_mut.supply() <= *lock_mut.max_supply.borrow(), EMaxSupply);
    
    lock_mut.total_minted = lock_mut.total_minted + amount;
    lock_mut.treasury_cap.mint(amount, ctx)
}

public fun delete_mint_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let MintAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_burn<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    amount: u64, 
    witness: W
) {
    proposal.add_action(BurnAction<CoinType> { amount }, witness);
}

public fun do_burn<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    coin: Coin<CoinType>,
    version: TypeName,
    witness: W, 
) {
    let BurnAction<CoinType> { amount } = executable.action(account.addr(), version, witness);
    assert!(amount == coin.value(), EWrongValue);
    
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);
    assert!(lock_mut.can_burn, EBurnDisabled);

    lock_mut.total_burnt = lock_mut.total_burnt + amount;
    lock_mut.treasury_cap.burn(coin);
}

public fun delete_burn_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let BurnAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_update<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>,
    symbol: Option<ascii::String>,
    name: Option<String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
    witness: W,
) {
    assert!(symbol.is_some() || name.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    proposal.add_action(UpdateAction<CoinType> { symbol, name, description, icon_url }, witness);
}

public fun do_update<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
    version: TypeName,
    witness: W,
) {
    let UpdateAction<CoinType> { symbol, name, description, icon_url } = 
        executable.action(account.addr(), version, witness);
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);

    if (!lock_mut.can_update_symbol) assert!(symbol.is_none(), ECannotUpdateSymbol);
    if (!lock_mut.can_update_name) assert!(name.is_none(), ECannotUpdateName);
    if (!lock_mut.can_update_description) assert!(description.is_none(), ECannotUpdateDescription);
    if (!lock_mut.can_update_icon) assert!(icon_url.is_none(), ECannotUpdateIcon);
    
    let (default_symbol, default_name, default_description, default_icon_url) = (metadata.get_symbol(), metadata.get_name(), metadata.get_description(), metadata.get_icon_url().extract().inner_url());

    lock_mut.treasury_cap.update_symbol(metadata, symbol.get_with_default(default_symbol));
    lock_mut.treasury_cap.update_name(metadata, name.get_with_default(default_name));
    lock_mut.treasury_cap.update_description(metadata, description.get_with_default(default_description));
    lock_mut.treasury_cap.update_icon_url(metadata, icon_url.get_with_default(default_icon_url));
}

public fun delete_update_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let UpdateAction<CoinType> { .. } = expired.remove_expired_action();
}


// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}

// === Test functions ===

#[test_only] 
public fun toggle_can_mint<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_mint = !lock_mut.can_mint;
}

#[test_only] 
public fun toggle_can_burn<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_burn = !lock_mut.can_burn;
}

#[test_only] 
public fun toggle_can_update_symbol<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_update_symbol = !lock_mut.can_update_symbol;
}

#[test_only] 
public fun toggle_can_update_name<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_update_name = !lock_mut.can_update_name;
}

#[test_only] 
public fun toggle_can_update_description<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_update_description = !lock_mut.can_update_description;
}

#[test_only] 
public fun toggle_can_update_icon<Config, Approvals, CoinType>(account: &mut Account<Config, Approvals>) {
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version::current());
    lock_mut.can_update_icon = !lock_mut.can_update_icon;
}