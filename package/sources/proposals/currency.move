/// Members can lock a TreasuryCap in the Multisig to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Multisig and burn one of its coin.
/// It uses a Withdraw action. The Coin could be merged beforehand.

module kraken::currency {
    use std::string::{Self, String};
    use sui::transfer::Receiving;
    use sui::coin::{Coin, TreasuryCap, CoinMetadata};
    use kraken::multisig::{Multisig, Executable, Proposal};
    use kraken::owned;

    // === Errors ===

    const ENoChange: u64 = 0;
    const EUpdateNotExecuted: u64 = 1;
    const EWrongValue: u64 = 2;
    const EMintNotExecuted: u64 = 3;
    const EBurnNotExecuted: u64 = 4;

    // === Structs ===    

    public struct Witness has copy, drop {}
    
    // Wrapper restricting access to a TreasuryCap
    // doesn't have store because non-transferrable
    public struct TreasuryLock<phantom C: drop> has key {
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
        let treasury_lock = TreasuryLock { 
            id: object::new(ctx), 
            multisig_addr: multisig.addr(),
            treasury_cap 
        };

        transfer::transfer(treasury_lock, multisig.addr());
    }

    // borrow the lock that can only be put back in the multisig because no store
    public fun borrow_cap<C: drop>(
        multisig: &mut Multisig, 
        treasury_lock: Receiving<TreasuryLock<C>>,
        ctx: &mut TxContext
    ): TreasuryLock<C> {
        multisig.assert_is_member(ctx);
        transfer::receive(multisig.uid_mut(), treasury_lock)
    }

    public fun put_back_cap<C: drop>(treasury_lock: TreasuryLock<C>) {
        let addr = treasury_lock.multisig_addr;
        transfer::transfer(treasury_lock, addr);
    }

    // === [PROPOSAL] Public functions ===

    // step 1: propose to mint an amount of a coin that will be transferred to the multisig
    public fun propose_mint<C: drop>(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {}, 
            key, 
            execution_time, 
            expiration_epoch, 
            description, 
            ctx
        );
        new_mint<C>(proposal_mut, amount);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: mint the coins and send them to the multisig
    public fun execute_mint<C: drop>(
        mut executable: Executable,
        lock: &mut TreasuryLock<C>,
        ctx: &mut TxContext
    ) {
        let coin = mint<C, Witness>(&mut executable, lock, Witness {}, 0, ctx);
        transfer::public_transfer(coin, executable.multisig_addr());
        destroy_mint<C, Witness>(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // step 1: propose to burn an amount of a coin owned by the multisig
    public fun propose_burn<C: drop>(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin_id: ID,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {}, 
            key, 
            execution_time, 
            expiration_epoch, 
            description, 
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
        lock: &mut TreasuryLock<C>,
    ) {
        let coin = owned::withdraw(&mut executable, multisig, receiving, Witness {}, 0);
        burn<C, Witness>(&mut executable, lock, coin, Witness {}, 1);
        owned::destroy_withdraw(&mut executable, Witness {});
        destroy_burn<C, Witness>(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // step 1: propose to transfer nfts to another kiosk
    public fun propose_update(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        symbol: Option<String>,
        description_md: Option<String>,
        icon_url: Option<String>,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_update(proposal_mut, name, symbol, description_md, icon_url);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: update the CoinMetadata
    public fun execute_update<C: drop>(
        executable: &mut Executable,
        lock: &TreasuryLock<C>,
        metadata: &mut CoinMetadata<C>,
    ) {
        update(executable, lock, metadata, Witness {}, 0);
    }

    // step 5: destroy the executable, must `put_back_cap()`
    public fun complete_update(mut executable: Executable) {
        destroy_update(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // === [ACTION] Public functions ===

    public fun new_mint<C: drop>(proposal: &mut Proposal, amount: u64) {
        proposal.add_action(Mint<C> { amount });
    }

    public fun mint<C: drop, W: drop>(
        executable: &mut Executable, 
        lock: &mut TreasuryLock<C>, 
        witness: W, 
        idx: u64,
        ctx: &mut TxContext
    ): Coin<C> {
        let mint_mut: &mut Mint<C> = executable.action_mut(witness, idx);
        let coin = lock.treasury_cap.mint(mint_mut.amount, ctx);
        mint_mut.amount = 0; // reset to ensure it has been executed
        coin
    }

    public fun destroy_mint<C: drop, W: drop>(executable: &mut Executable, witness: W) {
        let Mint<C> { amount } = executable.remove_action(witness);
        assert!(amount == 0, EMintNotExecuted);
    }

    public fun new_burn<C: drop>(proposal: &mut Proposal, amount: u64) {
        proposal.add_action(Burn<C> { amount });
    }

    public fun burn<C: drop, W: drop>(
        executable: &mut Executable, 
        lock: &mut TreasuryLock<C>, 
        coin: Coin<C>,
        witness: W, 
        idx: u64,
    ) {
        let burn_mut: &mut Burn<C> = executable.action_mut(witness, idx);
        assert!(burn_mut.amount == coin.value(), EWrongValue);
        lock.treasury_cap.burn(coin);
        burn_mut.amount = 0; // reset to ensure it has been executed
    }

    public fun destroy_burn<C: drop, W: drop>(executable: &mut Executable, witness: W) {
        let Burn<C> { amount } = executable.remove_action(witness);
        assert!(amount == 0, EBurnNotExecuted);
    }

    public fun new_update(
        proposal: &mut Proposal,
        name: Option<String>,
        symbol: Option<String>,
        description: Option<String>,
        icon_url: Option<String>,
    ) {
        assert!(name.is_some() || symbol.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
        proposal.add_action(Update { name, symbol, description, icon_url });
    }

    public fun update<C: drop, W: drop>(
        executable: &mut Executable,
        lock: &TreasuryLock<C>,
        metadata: &mut CoinMetadata<C>,
        witness: W,
        idx: u64,
    ) {
        let update_mut: &mut Update = executable.action_mut(witness, idx);
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

    public fun destroy_update<W: drop>(executable: &mut Executable, witness: W) {
        let Update { name, symbol, description, icon_url } = executable.remove_action(witness);
        //@dev Future guard - impossible to trigger now
        assert!(name.is_none() && symbol.is_none() && description.is_none() && icon_url.is_none(), EUpdateNotExecuted);
    }
}
