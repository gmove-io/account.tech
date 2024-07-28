/// Members can lock a TreasuryCap in the Multisig to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Multisig and burn one of its coin.
/// It uses a Withdraw action. The Coin could be merged beforehand.

module kraken::currency;

// === Imports ===

use std::{
    type_name,
    string::{Self, String}
};
use sui::{
    transfer::Receiving,
    coin::{Coin, TreasuryCap, CoinMetadata}
};
use kraken::{
    multisig::{Multisig, Executable, Proposal},
    owned
};

// === Errors ===

const ENoChange: u64 = 0;
const EUpdateNotExecuted: u64 = 1;
const EWrongValue: u64 = 2;
const EMintNotExecuted: u64 = 3;
const EBurnNotExecuted: u64 = 4;
const EWrongCoinType: u64 = 5;

// === Structs ===    

// delegated issuer verifying a proposal is destroyed in the module where it was created
public struct Issuer has copy, drop {}

// Wrapper restricting access to a TreasuryCap
// doesn't have store because non-transferrable
public struct CurrencyLock<phantom C: drop> has key {
    id: UID,
    // multisig owning the lock
    multisig_addr: address,
    // the cap to lock
    treasury_cap: TreasuryCap<C>,
}

// [ACTION] mint new coins
public struct Mint<phantom C: drop> has store {
    amount: u64,
}

// [ACTION] burn coins
public struct Burn<phantom C: drop> has store {
    amount: u64,
}

// [ACTION] update a CoinMetadata object using a locked TreasuryCap 
public struct Update has store { 
    coin_type: String,
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
}

// === [MEMBER] Public functions ===

public fun lock_cap<C: drop>(
    multisig: &Multisig,
    treasury_cap: TreasuryCap<C>,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let treasury_lock = CurrencyLock { 
        id: object::new(ctx), 
        multisig_addr: multisig.addr(),
        treasury_cap 
    };

    transfer::transfer(treasury_lock, multisig.addr());
}

// borrow the lock that can only be put back in the multisig because no store
public fun borrow_cap<C: drop>(
    multisig: &mut Multisig, 
    treasury_lock: Receiving<CurrencyLock<C>>,
    ctx: &mut TxContext
): CurrencyLock<C> {
    multisig.assert_is_member(ctx);
    transfer::receive(multisig.uid_mut(), treasury_lock)
}

public fun put_back_cap<C: drop>(treasury_lock: CurrencyLock<C>) {
    let addr = treasury_lock.multisig_addr;
    transfer::transfer(treasury_lock, addr);
}

// === [PROPOSAL] Public functions ===

// step 1: propose to mint an amount of a coin that will be transferred to the multisig
public fun propose_mint<C: drop>(
    multisig: &mut Multisig,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amount: u64,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {}, 
        type_to_name<C>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );
    new_mint<C>(proposal_mut, amount);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: mint the coins and send them to the multisig
public fun execute_mint<C: drop>(
    mut executable: Executable,
    lock: &mut CurrencyLock<C>,
    ctx: &mut TxContext
) {
    let coin = mint<C, Issuer>(&mut executable, lock, Issuer {}, 0, ctx);
    transfer::public_transfer(coin, executable.multisig_addr());
    destroy_mint<C, Issuer>(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to burn an amount of a coin owned by the multisig
public fun propose_burn<C: drop>(
    multisig: &mut Multisig,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    let proposal_mut = multisig.create_proposal(
        Issuer {}, 
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

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: burn the coin initially owned by the multisig
public fun execute_burn<C: drop>(
    mut executable: Executable,
    multisig: &mut Multisig,
    receiving: Receiving<Coin<C>>,
    lock: &mut CurrencyLock<C>,
) {
    let coin = owned::withdraw(&mut executable, multisig, receiving, Issuer {}, 0);
    burn<C, Issuer>(&mut executable, lock, coin, Issuer {}, 1);
    owned::destroy_withdraw(&mut executable, Issuer {});
    destroy_burn<C, Issuer>(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// step 1: propose to transfer nfts to another kiosk
public fun propose_update<C: drop>(
    multisig: &mut Multisig,
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
    let proposal_mut = multisig.create_proposal(
        Issuer {},
        type_to_name<C>(), // the coin type is the auth name 
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    new_update<C>(proposal_mut, md_name, md_symbol, md_description, md_icon);
}

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<C: drop>(
    executable: &mut Executable,
    lock: &CurrencyLock<C>,
    metadata: &mut CoinMetadata<C>,
) {
    update(executable, lock, metadata, Issuer {}, 0);
}

// step 5: destroy the executable, must `put_back_cap()`
public fun complete_update(mut executable: Executable) {
    destroy_update(&mut executable, Issuer {});
    executable.destroy(Issuer {});
}

// === [ACTION] Public functions ===

public fun new_mint<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(Mint<C> { amount });
}

public fun mint<C: drop, I: drop>(
    executable: &mut Executable, 
    lock: &mut CurrencyLock<C>, 
    issuer: I, 
    idx: u64,
    ctx: &mut TxContext
): Coin<C> {
    let mint_mut: &mut Mint<C> = executable.action_mut(issuer, idx);
    let coin = lock.treasury_cap.mint(mint_mut.amount, ctx);
    mint_mut.amount = 0; // reset to ensure it has been executed
    coin
}

public fun destroy_mint<C: drop, I: drop>(executable: &mut Executable, issuer: I) {
    let Mint<C> { amount } = executable.remove_action(issuer);
    assert!(amount == 0, EMintNotExecuted);
}

public fun new_burn<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(Burn<C> { amount });
}

public fun burn<C: drop, I: copy + drop>(
    executable: &mut Executable, 
    lock: &mut CurrencyLock<C>, 
    coin: Coin<C>,
    issuer: I, 
    idx: u64,
) {
    let burn_mut: &mut Burn<C> = executable.action_mut(issuer, idx);
    assert!(burn_mut.amount == coin.value(), EWrongValue);
    lock.treasury_cap.burn(coin);
    burn_mut.amount = 0; // reset to ensure it has been executed
}

public fun destroy_burn<C: drop, I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Burn<C> { amount } = executable.remove_action(issuer);
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
    proposal.add_action(Update { coin_type: type_to_name<C>(), name, symbol, description, icon_url });
}

public fun update<C: drop, I: copy + drop>(
    executable: &mut Executable,
    lock: &CurrencyLock<C>,
    metadata: &mut CoinMetadata<C>,
    issuer: I,
    idx: u64,
) {
    let update_mut: &mut Update = executable.action_mut(issuer, idx);
    assert!(update_mut.coin_type == type_to_name<C>(), EWrongCoinType);

    if (update_mut.name.is_some()) {
        lock.treasury_cap.update_name(metadata, update_mut.name.extract());
    };
    if (update_mut.symbol.is_some()) {
        lock.treasury_cap.update_symbol(metadata, string::to_ascii(update_mut.symbol.extract()));
    };
    if (update_mut.description.is_some()) {
        lock.treasury_cap.update_description(metadata, update_mut.description.extract());
    };
    if (update_mut.icon_url.is_some()) {
        lock.treasury_cap.update_icon_url(metadata, string::to_ascii(update_mut.icon_url.extract()));
    };
    // all fields are set to none now
}

public fun destroy_update<I: copy + drop>(executable: &mut Executable, issuer: I) {
    let Update { coin_type: _, name, symbol, description, icon_url } = executable.remove_action(issuer);
    assert!(name.is_none() && symbol.is_none() && description.is_none() && icon_url.is_none(), EUpdateNotExecuted);
}

fun type_to_name<T: drop>(): String {
    type_name::get<T>().into_string().to_string()
}
