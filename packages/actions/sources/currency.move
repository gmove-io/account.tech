/// Members can lock a TreasuryCap in the Account to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Account and burn one of its coin.
/// It uses a Withdraw action. The burnt Coin could be merged beforehand.
/// 
/// Coins minted by the account can also be transferred or paid to any address.

module kraken_actions::currency;

// === Imports ===

use std::{
    type_name,
    string::{Self, String}
};
use sui::{
    transfer::Receiving,
    coin::{Coin, TreasuryCap, CoinMetadata},
    event,
};
use kraken_account::{
    account::Account,
    proposals::Proposal,
    executable::Executable
};
use kraken_actions::{
    owned,
    transfers,
    payments,
};

// === Errors ===

const ENoChange: u64 = 0;
const EUpdateNotExecuted: u64 = 1;
const EWrongValue: u64 = 2;
const EMintNotExecuted: u64 = 3;
const EBurnNotExecuted: u64 = 4;
const ENoLock: u64 = 5;
const EDifferentLength: u64 = 6;

// === Events ===

public struct Minted has copy, drop, store {
    coin_type: String,
    amount: u64,
}

public struct Burned has copy, drop, store {
    coin_type: String,
    amount: u64,
}

// === Structs ===    

/// Dynamic Field key for the CurrencyLock
public struct CurrencyKey<phantom C: drop> has copy, drop, store {}

/// Dynamic Field wrapper restricting access to a TreasuryCap
public struct CurrencyLock<phantom C: drop> has store {
    // the cap to lock
    treasury_cap: TreasuryCap<C>,
}

/// [MEMBER] can lock a TreasuryCap in the Account to restrict minting and burning operations
public struct ManageCurrency has copy, drop {}
/// [PROPOSAL] mints new coins from a locked TreasuryCap
public struct MintProposal has copy, drop {}
/// [PROPOSAL] burns coins from the account using a locked TreasuryCap
public struct BurnProposal has copy, drop {}
/// [PROPOSAL] updates the CoinMetadata associated with a locked TreasuryCap
public struct UpdateProposal has copy, drop {}
/// [PROPOSAL] transfers from a minted coin 
public struct TransferProposal has copy, drop {}
/// [PROPOSAL] pays from a minted coin
public struct PayProposal has copy, drop {}

/// [ACTION] mint new coins
public struct MintAction<phantom C: drop> has store {
    amount: u64,
}

/// [ACTION] burns coins
public struct BurnAction<phantom C: drop> has store {
    amount: u64,
}

/// [ACTION] updates a CoinMetadata object using a locked TreasuryCap 
public struct UpdateAction<phantom C: drop> has store { 
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
}

// === [MEMBER] Public functions ===

/// Only a member can lock a TreasuryCap and borrow it.

public fun lock_cap<C: drop>(
    account: &mut Account,
    treasury_cap: TreasuryCap<C>,
    ctx: &mut TxContext
) {
    account.assert_is_member(ctx);
    let treasury_lock = CurrencyLock { treasury_cap };

    account.add_managed_asset(ManageCurrency {}, CurrencyKey<C> {}, treasury_lock);
}

public fun has_lock<C: drop>(account: &Account): bool {
    account.has_managed_asset(CurrencyKey<C> {})
}

public fun borrow_lock<C: drop>(account: &Account): &CurrencyLock<C> {
    account.borrow_managed_asset(ManageCurrency {}, CurrencyKey<C> {})
}

public fun borrow_lock_mut<C: drop>(account: &mut Account): &mut CurrencyLock<C> {
    account.borrow_managed_asset_mut(ManageCurrency {}, CurrencyKey<C> {})
}

public fun supply<C: drop>(lock: &CurrencyLock<C>): u64 {
    lock.treasury_cap.total_supply()
}

// === [PROPOSAL] Public functions ===

// step 1: propose to mint an amount of a coin that will be transferred to the account
public fun propose_mint<C: drop>(
    account: &mut Account,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<C>(account), ENoLock);
    let proposal_mut = account.create_proposal(
        MintProposal {}, 
        type_to_name<C>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );
    new_mint<C>(proposal_mut, amount);
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint<C: drop>(
    mut executable: Executable,
    account: &mut Account,
    ctx: &mut TxContext
) {
    let coin = mint<C, MintProposal>(&mut executable, account, MintProposal {}, ctx);
    transfer::public_transfer(coin, account.addr());
    destroy_mint<C, MintProposal>(&mut executable, MintProposal {});
    executable.destroy(MintProposal {});
}

// step 1: propose to burn an amount of a coin owned by the account
public fun propose_burn<C: drop>(
    account: &mut Account,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<C>(account), ENoLock);
    let proposal_mut = account.create_proposal(
        BurnProposal {}, 
        type_to_name<C>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );
    owned::new_withdraw(proposal_mut, vector[coin_id]);
    new_burn<C>(proposal_mut, amount);
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: burn the coin initially owned by the account
public fun execute_burn<C: drop>(
    mut executable: Executable,
    account: &mut Account,
    receiving: Receiving<Coin<C>>,
) {
    let coin = owned::withdraw(&mut executable, account, receiving, BurnProposal {});
    burn<C, BurnProposal>(&mut executable, account, coin, BurnProposal {});
    owned::destroy_withdraw(&mut executable, BurnProposal {});
    destroy_burn<C, BurnProposal>(&mut executable, BurnProposal {});
    executable.destroy(BurnProposal {});
}

// step 1: propose to update the CoinMetadata
public fun propose_update<C: drop>(
    account: &mut Account,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    md_name: Option<String>,
    md_symbol: Option<String>,
    md_description: Option<String>,
    md_icon: Option<String>,
    ctx: &mut TxContext
) {
    assert!(has_lock<C>(account), ENoLock);
    let proposal_mut = account.create_proposal(
        UpdateProposal {},
        type_to_name<C>(), // the coin type is the auth name 
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_update<C>(proposal_mut, md_name, md_symbol, md_description, md_icon);
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<C: drop>(
    mut executable: Executable,
    account: &mut Account,
    metadata: &mut CoinMetadata<C>,
) {
    update(&mut executable, account, metadata, UpdateProposal {});
    destroy_update<C, UpdateProposal>(&mut executable, UpdateProposal {});
    executable.destroy(UpdateProposal {});
}

// step 1: propose to send managed coins
public fun propose_transfer<C: drop>(
    account: &mut Account, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(amounts.length() == recipients.length(), EDifferentLength);
    let proposal_mut = account.create_proposal(
        TransferProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        new_mint<C>(proposal_mut, amount);
        transfers::new_transfer(proposal_mut, recipient);
    });
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<C: drop>(
    executable: &mut Executable, 
    account: &mut Account, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = mint(executable, account, TransferProposal {}, ctx);

    let mut is_executed = false;
    let mint: &MintAction<C> = executable.action();

    if (mint.amount == 0) {
        let MintAction<C> { .. } = executable.remove_action(TransferProposal {});
        is_executed = true;
    };

    transfers::transfer(executable, account, coin, TransferProposal {}, is_executed);

    if (is_executed) {
        transfers::destroy_transfer(executable, TransferProposal {});
    }
}

// step 1: propose to pay from a minted coin
public fun propose_pay<C: drop>(
    account: &mut Account, 
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
    let proposal_mut = account.create_proposal(
        PayProposal {},
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_mint<C>(proposal_mut, coin_amount);
    payments::new_pay(proposal_mut, amount, interval, recipient);
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<C: drop>(
    mut executable: Executable, 
    account: &mut Account, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = mint(&mut executable, account, PayProposal {}, ctx);
    payments::pay(&mut executable, account, coin, PayProposal {}, ctx);

    destroy_mint<C, PayProposal>(&mut executable, PayProposal {});
    payments::destroy_pay(&mut executable, PayProposal {});
    executable.destroy(PayProposal {});
}

// === [ACTION] Public functions ===

public fun new_mint<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(MintAction<C> { amount });
}

public fun mint<C: drop, W: drop>(
    executable: &mut Executable, 
    account: &mut Account,
    witness: W, 
    ctx: &mut TxContext
): Coin<C> {
    let mint_mut: &mut MintAction<C> = executable.action_mut(witness, account.addr());
    
    event::emit(Minted {
        coin_type: type_to_name<C>(),
        amount: mint_mut.amount,
    });
    
    let lock_mut = borrow_lock_mut<C>(account);
    let coin = lock_mut.treasury_cap.mint(mint_mut.amount, ctx);
    mint_mut.amount = 0; // reset to ensure it has been executed
    coin
}

public fun destroy_mint<C: drop, W: drop>(executable: &mut Executable, witness: W) {
    let MintAction<C> { amount } = executable.remove_action(witness);
    assert!(amount == 0, EMintNotExecuted);
}

public fun new_burn<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(BurnAction<C> { amount });
}

public fun burn<C: drop, W: copy + drop>(
    executable: &mut Executable, 
    account: &mut Account,
    coin: Coin<C>,
    witness: W, 
) {
    let burn_mut: &mut BurnAction<C> = executable.action_mut(witness, account.addr());
    
    event::emit(Burned {
        coin_type: type_to_name<C>(),
        amount: burn_mut.amount,
    });
    
    let lock_mut = borrow_lock_mut<C>(account);
    assert!(burn_mut.amount == coin.value(), EWrongValue);
    lock_mut.treasury_cap.burn(coin);
    burn_mut.amount = 0; // reset to ensure it has been executed
}

public fun destroy_burn<C: drop, W: copy + drop>(executable: &mut Executable, witness: W) {
    let BurnAction<C> { amount } = executable.remove_action(witness);
    assert!(amount == 0, EBurnNotExecuted);
}

public fun new_update<C: drop>(
    proposal: &mut Proposal,
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
) {
    assert!(name.is_some() || symbol.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    proposal.add_action(UpdateAction<C> { name, symbol, description, icon_url });
}

public fun update<C: drop, W: copy + drop>(
    executable: &mut Executable,
    account: &mut Account,
    metadata: &mut CoinMetadata<C>,
    witness: W,
) {
    let update_mut: &mut UpdateAction<C> = executable.action_mut(witness, account.addr());
    let lock_mut = borrow_lock_mut<C>(account);

    if (update_mut.name.is_some()) {
        lock_mut.treasury_cap.update_name(metadata, update_mut.name.extract());
    };
    if (update_mut.symbol.is_some()) {
        lock_mut.treasury_cap.update_symbol(metadata, string::to_ascii(update_mut.symbol.extract()));
    };
    if (update_mut.description.is_some()) {
        lock_mut.treasury_cap.update_description(metadata, update_mut.description.extract());
    };
    if (update_mut.icon_url.is_some()) {
        lock_mut.treasury_cap.update_icon_url(metadata, string::to_ascii(update_mut.icon_url.extract()));
    };
    // all fields are set to none now
}

public fun destroy_update<C: drop, W: copy + drop>(executable: &mut Executable, witness: W) {
    let UpdateAction<C> { name, symbol, description, icon_url, .. } = executable.remove_action(witness);
    assert!(name.is_none() && symbol.is_none() && description.is_none() && icon_url.is_none(), EUpdateNotExecuted);
}

// === [CORE DEPS] Public functions ===

public fun delete_mint_action<C: drop, W: copy + drop>(
    action: MintAction<C>, 
    account: &Account,
    witness: W,
) {
    account.deps().assert_core_dep(witness);
    let MintAction { .. } = action;
}

public fun delete_burn_action<C: drop, W: copy + drop>(
    action: BurnAction<C>, 
    account: &Account,
    witness: W,
) {
    account.deps().assert_core_dep(witness);
    let BurnAction { .. } = action;
}

public fun delete_update_action<C: drop, W: copy + drop>(
    action: UpdateAction<C>, 
    account: &Account,
    witness: W,
) {
    account.deps().assert_core_dep(witness);
    let UpdateAction { .. } = action;
}

// === Private functions ===

fun type_to_name<T: drop>(): String {
    type_name::get<T>().into_string().to_string()
}
