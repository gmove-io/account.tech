/// Members can lock a TreasuryCap in the Multisig to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Multisig and burn one of its coin.
/// It uses a Withdraw action. The Coin could be merged beforehand.

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
use kraken_multisig::{
    multisig::Multisig,
    proposals::Proposal,
    executable::Executable
};
use kraken_actions::owned;

// === Errors ===

const ENoChange: u64 = 0;
const EUpdateNotExecuted: u64 = 1;
const EWrongValue: u64 = 2;
const EMintNotExecuted: u64 = 3;
const EBurnNotExecuted: u64 = 4;
const ENoLock: u64 = 5;

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

// df key for the CurrencyLock
public struct CurrencyKey<phantom C: drop> has copy, drop, store {}

// Wrapper restricting access to a TreasuryCap
public struct CurrencyLock<phantom C: drop> has store {
    // the cap to lock
    treasury_cap: TreasuryCap<C>,
}

// [MEMBER] can lock a TreasuryCap in the Multisig to restrict minting and burning operations
public struct ManageCurrency has copy, drop {}
// [PROPOSAL] mint new coins from a locked TreasuryCap
public struct MintProposal has copy, drop {}
// [PROPOSAL] burn coins from the multisig using a locked TreasuryCap
public struct BurnProposal has copy, drop {}
// [PROPOSAL] update the CoinMetadata associated with a locked TreasuryCap
public struct UpdateProposal has copy, drop {}

// [ACTION] mint new coins
public struct MintAction<phantom C: drop> has store {
    amount: u64,
}

// [ACTION] burn coins
public struct BurnAction<phantom C: drop> has store {
    amount: u64,
}

// [ACTION] update a CoinMetadata object using a locked TreasuryCap 
public struct UpdateAction<phantom C: drop> has store { 
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
}

// === [MEMBER] Public functions ===

public fun lock_cap<C: drop>(
    multisig: &mut Multisig,
    treasury_cap: TreasuryCap<C>,
    ctx: &mut TxContext
) {
    multisig.assert_is_member(ctx);
    let treasury_lock = CurrencyLock { treasury_cap };

    multisig.add_managed_asset(ManageCurrency {}, CurrencyKey<C> {}, treasury_lock);
}

public fun has_lock<C: drop>(multisig: &Multisig): bool {
    multisig.has_managed_asset(CurrencyKey<C> {})
}

public fun borrow_lock<C: drop>(multisig: &Multisig): &CurrencyLock<C> {
    multisig.borrow_managed_asset(ManageCurrency {}, CurrencyKey<C> {})
}

public fun borrow_lock_mut<C: drop>(multisig: &mut Multisig): &mut CurrencyLock<C> {
    multisig.borrow_managed_asset_mut(ManageCurrency {}, CurrencyKey<C> {})
}

public fun supply<C: drop>(lock: &CurrencyLock<C>): u64 {
    lock.treasury_cap.total_supply()
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
    assert!(has_lock<C>(multisig), ENoLock);
    let proposal_mut = multisig.create_proposal(
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

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: mint the coins and send them to the multisig
public fun execute_mint<C: drop>(
    mut executable: Executable,
    multisig: &mut Multisig,
    ctx: &mut TxContext
) {
    let coin = mint<C, MintProposal>(&mut executable, multisig, MintProposal {}, ctx);
    transfer::public_transfer(coin, multisig.addr());
    destroy_mint<C, MintProposal>(&mut executable, MintProposal {});
    executable.destroy(MintProposal {});
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
    assert!(has_lock<C>(multisig), ENoLock);
    let proposal_mut = multisig.create_proposal(
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

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: burn the coin initially owned by the multisig
public fun execute_burn<C: drop>(
    mut executable: Executable,
    multisig: &mut Multisig,
    receiving: Receiving<Coin<C>>,
) {
    let coin = owned::withdraw(&mut executable, multisig, receiving, BurnProposal {});
    burn<C, BurnProposal>(&mut executable, multisig, coin, BurnProposal {});
    owned::destroy_withdraw(&mut executable, BurnProposal {});
    destroy_burn<C, BurnProposal>(&mut executable, BurnProposal {});
    executable.destroy(BurnProposal {});
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
    assert!(has_lock<C>(multisig), ENoLock);
    let proposal_mut = multisig.create_proposal(
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

// step 2: multiple members have to approve the proposal (multisig::approve_proposal)
// step 3: execute the proposal and return the action (multisig::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<C: drop>(
    mut executable: Executable,
    multisig: &mut Multisig,
    metadata: &mut CoinMetadata<C>,
) {
    update(&mut executable, multisig, metadata, UpdateProposal {});
    destroy_update<C, UpdateProposal>(&mut executable, UpdateProposal {});
    executable.destroy(UpdateProposal {});
}

// === [ACTION] Public functions ===

public fun new_mint<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(MintAction<C> { amount });
}

public fun mint<C: drop, W: drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig,
    witness: W, 
    ctx: &mut TxContext
): Coin<C> {
    let mint_mut: &mut MintAction<C> = executable.action_mut(witness, multisig.addr());
    
    event::emit(Minted {
        coin_type: type_to_name<C>(),
        amount: mint_mut.amount,
    });
    
    let lock_mut = borrow_lock_mut<C>(multisig);
    let coin = lock_mut.treasury_cap.mint(mint_mut.amount, ctx);
    mint_mut.amount = 0; // reset to ensure it has been executed
    coin
}

public fun destroy_mint<C: drop, W: drop>(executable: &mut Executable, witness: W) {
    let MintAction<C> { amount } = executable.remove_action(witness);
    assert!(amount == 0, EMintNotExecuted);
}

public fun mint_is_executed<C: drop>(executable: &Executable): bool {
    let mint: &MintAction<C> = executable.action();
    mint.amount == 0
}

public fun new_burn<C: drop>(proposal: &mut Proposal, amount: u64) {
    proposal.add_action(BurnAction<C> { amount });
}

public fun burn<C: drop, W: copy + drop>(
    executable: &mut Executable, 
    multisig: &mut Multisig,
    coin: Coin<C>,
    witness: W, 
) {
    let burn_mut: &mut BurnAction<C> = executable.action_mut(witness, multisig.addr());
    
    event::emit(Burned {
        coin_type: type_to_name<C>(),
        amount: burn_mut.amount,
    });
    
    let lock_mut = borrow_lock_mut<C>(multisig);
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
    multisig: &mut Multisig,
    metadata: &mut CoinMetadata<C>,
    witness: W,
) {
    let update_mut: &mut UpdateAction<C> = executable.action_mut(witness, multisig.addr());
    let lock_mut = borrow_lock_mut<C>(multisig);

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

fun type_to_name<T: drop>(): String {
    type_name::get<T>().into_string().to_string()
}
