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
    transfers,
    payments,
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
const ECannotReenable: vector<u8> = b"Cannot reenable a permission";
#[error]
const ECannotUpdateName: vector<u8> = b"Cannot update name";
#[error]
const ECannotUpdateSymbol: vector<u8> = b"Cannot update symbol";
#[error]
const ECannotUpdateDescription: vector<u8> = b"Cannot update description";
#[error]
const ECannotUpdateIcon: vector<u8> = b"Cannot update icon";

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
    can_update_name: bool,
    can_update_symbol: bool,
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
/// [PROPOSAL] transfers from a minted coin 
public struct TransferProposal() has copy, drop;
/// [PROPOSAL] pays from a minted coin
public struct PayProposal() has copy, drop;

/// [ACTION] disables permissions marked as false
public struct DisableAction<phantom CoinType> has store {
    can_mint: bool,
    can_burn: bool,
    can_update_name: bool,
    can_update_symbol: bool,
    can_update_description: bool,
    can_update_icon: bool,
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
    name: Option<String>,
    symbol: Option<ascii::String>,
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
        can_update_name: true,
        can_update_symbol: true,
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

public fun can_update_name<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_name
}

public fun can_update_symbol<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_symbol
}

public fun can_update_description<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_description
}

public fun can_update_icon<CoinType>(lock: &CurrencyLock<CoinType>): bool {
    lock.can_update_icon
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
    can_mint: bool,
    can_burn: bool,
    can_update_name: bool,
    can_update_symbol: bool,
    can_update_description: bool,
    can_update_icon: bool,
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
        borrow_lock<Config, Outcome, CoinType>(account), 
        can_mint,
        can_burn,
        can_update_name,
        can_update_symbol,
        can_update_description,
        can_update_icon,
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
    disable<Config, Outcome, CoinType, DisableProposal>(&mut executable, account, version::current(), DisableProposal());

    destroy_disable<CoinType, DisableProposal>(&mut executable, version::current(), DisableProposal());
    executable.terminate(version::current(), DisableProposal());
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
        borrow_lock<Config, Outcome, CoinType>(account), 
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
    let coin = mint<Config, Outcome, CoinType, MintProposal>(&mut executable, account, version::current(), MintProposal(), ctx);
    account.keep(coin);

    destroy_mint<CoinType, MintProposal>(&mut executable, version::current(), MintProposal());
    executable.terminate(version::current(), MintProposal());
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

    owned::new_withdraw(&mut proposal, vector[coin_id], BurnProposal());
    new_burn<Outcome, CoinType, BurnProposal>(
        &mut proposal, 
        borrow_lock<Config, Outcome, CoinType>(account), 
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
    let coin = owned::withdraw(&mut executable, account, receiving, version::current(), BurnProposal());
    burn<Config, Outcome, CoinType, BurnProposal>(&mut executable, account, coin, version::current(), BurnProposal());

    owned::destroy_withdraw(&mut executable, version::current(), BurnProposal());
    destroy_burn<CoinType, BurnProposal>(&mut executable, version::current(), BurnProposal());
    executable.terminate(version::current(), BurnProposal());
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
    md_name: Option<String>,
    md_symbol: Option<ascii::String>,
    md_description: Option<String>,
    md_icon: Option<ascii::String>,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, CoinType>(account), ENoLock);

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
        borrow_lock<Config, Outcome, CoinType>(account),
        md_name, 
        md_symbol, 
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
    update(&mut executable, account, metadata, version::current(), UpdateProposal());

    destroy_update<CoinType, UpdateProposal>(&mut executable, version::current(), UpdateProposal());
    executable.terminate(version::current(), UpdateProposal());
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
    assert!(amounts.length() == recipients.length(), EAmountsRecipentsNotSameLength);

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
            borrow_lock<Config, Outcome, CoinType>(account), 
            amount, 
            TransferProposal()
        );
        transfers::new_transfer(&mut proposal, recipient, TransferProposal());
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
    let coin: Coin<CoinType> = mint(executable, account, version::current(), TransferProposal(), ctx);
    destroy_mint<CoinType, TransferProposal>(executable, version::current(), TransferProposal());

    transfers::transfer(executable, account, coin, version::current(), TransferProposal(), true);
    transfers::destroy_transfer(executable, version::current(), TransferProposal());
}

// step 1: propose to pay from a minted coin
public fun propose_pay<Config, Outcome, CoinType>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_amount: u64,
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
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
        borrow_lock<Config, Outcome, CoinType>(account), 
        coin_amount, 
        PayProposal()
    );
    payments::new_pay(&mut proposal, amount, interval, recipient, PayProposal());
    account.add_proposal(proposal, version::current(), PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<Config, Outcome, CoinType>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<CoinType> = mint(&mut executable, account, version::current(), PayProposal(), ctx);
    payments::pay(&mut executable, account, coin, version::current(), PayProposal(), ctx);

    destroy_mint<CoinType, PayProposal>(&mut executable, version::current(), PayProposal());
    payments::destroy_pay(&mut executable, version::current(), PayProposal());
    executable.terminate(version::current(), PayProposal());
}

// === [ACTION] Public functions ===

public fun new_disable<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>,
    lock: &CurrencyLock<CoinType>,
    can_mint: bool,
    can_burn: bool,
    can_update_name: bool,
    can_update_symbol: bool,
    can_update_description: bool,
    can_update_icon: bool,
    witness: W,
) {
    assert!(!can_mint || !can_burn || !can_update_name || !can_update_symbol || !can_update_description || !can_update_icon, ENoChange);
    // if disabled, must remain false
    if (!lock.can_mint) assert!(!can_mint, ECannotReenable);
    if (!lock.can_burn) assert!(!can_burn, ECannotReenable);
    if (!lock.can_update_name) assert!(!can_update_name, ECannotReenable);
    if (!lock.can_update_symbol) assert!(!can_update_symbol, ECannotReenable);
    if (!lock.can_update_description) assert!(!can_update_description, ECannotReenable);
    if (!lock.can_update_icon) assert!(!can_update_icon, ECannotReenable);

    proposal.add_action(DisableAction<CoinType> { can_mint, can_burn, can_update_name, can_update_symbol, can_update_description, can_update_icon }, witness);
}

public fun disable<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W,
) {
    let disable_action = executable.load<DisableAction<CoinType>, W>(account.addr(), version, witness);
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);

    lock_mut.can_mint = disable_action.can_mint;
    lock_mut.can_burn = disable_action.can_burn;
    lock_mut.can_update_name = disable_action.can_update_name;
    lock_mut.can_update_symbol = disable_action.can_update_symbol;
    lock_mut.can_update_description = disable_action.can_update_description;
    lock_mut.can_update_icon = disable_action.can_update_icon;

    executable.process<DisableAction<CoinType>, W>(version, witness);
}

public fun destroy_disable<CoinType, W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let DisableAction<CoinType> { .. } = executable.cleanup(version, witness);
}

public fun delete_disable_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let DisableAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_mint<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    lock: &CurrencyLock<CoinType>,
    amount: u64,
    witness: W,    
) {
    assert!(lock.can_mint, EMintDisabled);
    proposal.add_action(MintAction<CoinType> { amount }, witness);
}

public fun mint<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    version: TypeName,
    witness: W, 
    ctx: &mut TxContext
): Coin<CoinType> {
    let mint_action = executable.load<MintAction<CoinType>, W>(account.addr(), version, witness);
    
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);
    let coin = lock_mut.treasury_cap.mint(mint_action.amount, ctx);

    executable.process<MintAction<CoinType>, W>(version, witness);

    coin
}

public fun destroy_mint<CoinType, W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let MintAction<CoinType> { .. } = executable.cleanup(version, witness);
}

public fun delete_mint_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let MintAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_burn<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    lock: &CurrencyLock<CoinType>,
    amount: u64, 
    witness: W
) {
    assert!(lock.can_burn, EBurnDisabled);
    proposal.add_action(BurnAction<CoinType> { amount }, witness);
}

public fun burn<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    coin: Coin<CoinType>,
    version: TypeName,
    witness: W, 
) {
    let burn_action = executable.load<BurnAction<CoinType>, W>(account.addr(), version, witness);
    assert!(burn_action.amount == coin.value(), EWrongValue);
    
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);
    lock_mut.treasury_cap.burn(coin);

    executable.process<BurnAction<CoinType>, W>(version, witness);
}

public fun destroy_burn<CoinType, W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let BurnAction<CoinType> { .. } = executable.cleanup(version, witness);
}

public fun delete_burn_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let BurnAction<CoinType> { .. } = expired.remove_expired_action();
}

public fun new_update<Outcome, CoinType, W: drop>(
    proposal: &mut Proposal<Outcome>,
    lock: &CurrencyLock<CoinType>,
    name: Option<String>,
    symbol: Option<ascii::String>,
    description: Option<String>,
    icon_url: Option<ascii::String>,
    witness: W,
) {
    assert!(name.is_some() || symbol.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    if (!lock.can_update_name) assert!(name.is_none(), ECannotUpdateName);
    if (!lock.can_update_symbol) assert!(symbol.is_none(), ECannotUpdateSymbol);
    if (!lock.can_update_description) assert!(description.is_none(), ECannotUpdateDescription);
    if (!lock.can_update_icon) assert!(icon_url.is_none(), ECannotUpdateIcon);

    proposal.add_action(UpdateAction<CoinType> { name, symbol, description, icon_url }, witness);
}

public fun update<Config, Outcome, CoinType, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<CoinType>,
    version: TypeName,
    witness: W,
) {
    let update_action = executable.load<UpdateAction<CoinType>, W>(account.addr(), version, witness);
    let lock_mut: &mut CurrencyLock<CoinType> = account.borrow_managed_asset_mut(CurrencyKey<CoinType> {}, version);

    let (name, symbol, description, icon_url) = (metadata.get_name(), metadata.get_symbol(), metadata.get_description(), metadata.get_icon_url().extract().inner_url());

    lock_mut.treasury_cap.update_name(metadata, update_action.name.get_with_default(name));
    lock_mut.treasury_cap.update_symbol(metadata, update_action.symbol.get_with_default(symbol));
    lock_mut.treasury_cap.update_description(metadata, update_action.description.get_with_default(description));
    lock_mut.treasury_cap.update_icon_url(metadata, update_action.icon_url.get_with_default(icon_url));

    executable.process<UpdateAction<CoinType>, W>(version, witness);
}

public fun destroy_update<CoinType, W: drop>(executable: &mut Executable, version: TypeName, witness: W) {
    let UpdateAction<CoinType> { .. } = executable.cleanup(version, witness);
}

public fun delete_update_action<Outcome, CoinType>(expired: &mut Expired<Outcome>) {
    let UpdateAction<CoinType> { .. } = expired.remove_expired_action();
}


// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}
