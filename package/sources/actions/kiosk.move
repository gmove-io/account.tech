/// Members can place nfts from their kiosk into the multisig's without approval.
/// Nfts can be transferred into any other Kiosk. Upon approval, the recipient must execute the transfer.
/// The functions take the caller's kiosk and the multisig's kiosk to execute.
/// Nfts can be listed for sale in the kiosk, and then purchased by anyone.
/// The multisig can withdraw the profits from the kiosk.

module kraken::kiosk {
    use std::string::String;
    use sui::coin;
    use sui::transfer::Receiving;
    use sui::sui::SUI;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::TransferPolicy;
    use kiosk::{kiosk_lock_rule, royalty_rule};
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const EWrongReceiver: u64 = 1;
    const ETransferAllNftsBefore: u64 = 2;
    const EWrongNftsPrices: u64 = 3;
    const EListAllNftsBefore: u64 = 4;

    // === Structs ===    

    // delegated witness verifying a proposal is destroyed in the module where it was created
    public struct Auth has copy, drop {}
    
    // Wrapper restricting access to a KioskOwnerCap
    // doesn't have store because non-transferrable
    public struct KioskOwnerLock has key {
        id: UID,
        // multisig owning the lock
        multisig_addr: address,
        // the cap to lock
        kiosk_owner_cap: KioskOwnerCap,
    }

    // [ACTION] transfer nfts from the multisig's kiosk to another one
    public struct Take has store {
        // id of the nfts to transfer
        nft_ids: vector<ID>,
        // owner of the receiver kiosk
        recipient: address,
    }

    // [ACTION] list nfts for purchase
    public struct List has store {
        // id of the nfts to list
        nft_ids: vector<ID>,
        // sui amount
        prices: vector<u64>, 
    }

    // === [MEMBER] Public functions ===

    // not composable because of the lock
    #[allow(lint(share_owned))]
    public fun new(multisig: &Multisig, ctx: &mut TxContext) {
        multisig.assert_is_member(ctx);
        let (mut kiosk, cap) = kiosk::new(ctx);
        kiosk.set_owner_custom(&cap, multisig.addr());

        let kiosk_owner_lock = KioskOwnerLock {
            id: object::new(ctx), 
            multisig_addr: multisig.addr(),
            kiosk_owner_cap: cap 
        };

        transfer::public_share_object(kiosk);
        transfer::transfer(
            kiosk_owner_lock, 
            multisig.addr()
        );
    }

    // borrow the lock that can only be put back in the multisig because no store
    public fun borrow_cap(
        multisig: &mut Multisig, 
        kiosk_owner_lock: Receiving<KioskOwnerLock>,
        ctx: &mut TxContext
    ): KioskOwnerLock {
        multisig.assert_is_member(ctx);
        transfer::receive(multisig.uid_mut(), kiosk_owner_lock)
    }

    public fun put_back_cap(kiosk_owner_lock: KioskOwnerLock) {
        let addr = kiosk_owner_lock.multisig_addr;
        transfer::transfer(kiosk_owner_lock, addr);
    }

    // deposit from another Kiosk, no need for proposal
    // only doable if there is maximum a royalty and lock rule for the type
    public fun place<T: key + store>(
        multisig: &mut Multisig, 
        multisig_kiosk: &mut Kiosk, 
        lock: &KioskOwnerLock,
        sender_kiosk: &mut Kiosk, 
        sender_cap: &KioskOwnerCap, 
        nft_id: ID,
        policy: &mut TransferPolicy<T>,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);

        sender_kiosk.list<T>(sender_cap, nft_id, 0);
        let (nft, mut request) = sender_kiosk.purchase<T>(nft_id, coin::zero<SUI>(ctx));

        if (policy.has_rule<T, kiosk_lock_rule::Rule>()) {
            multisig_kiosk.lock(&lock.kiosk_owner_cap, policy, nft);
            kiosk_lock_rule::prove(&mut request, multisig_kiosk);
        } else {
            multisig_kiosk.place(&lock.kiosk_owner_cap, nft);
        };

        if (policy.has_rule<T, royalty_rule::Rule>()) {
            royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
        }; 

        policy.confirm_request(request);
    }

    // members can delist nfts
    public fun delist<T: key + store>(
        multisig: &mut Multisig, 
        kiosk: &mut Kiosk, 
        lock: &KioskOwnerLock,
        nft: ID,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        kiosk.delist<T>(&lock.kiosk_owner_cap, nft);
    }

    // members can withdraw the profits to the multisig
    public fun withdraw_profits(
        multisig: &mut Multisig,
        kiosk: &mut Kiosk,
        lock: &KioskOwnerLock,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let profits_mut = kiosk.profits_mut(&lock.kiosk_owner_cap);
        let profits_value = profits_mut.value();
        let profits = profits_mut.split(profits_value);

        transfer::public_transfer(
            coin::from_balance<SUI>(profits, ctx), 
            multisig.addr()
        );
    }

    // === [PROPOSAL] Public functions ===

    // step 1: propose to transfer nfts to another kiosk
    public fun propose_take(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Auth {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_take(proposal_mut, nft_ids, recipient);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
    public fun execute_take<T: key + store>(
        executable: &mut Executable,
        multisig_kiosk: &mut Kiosk, 
        lock: &KioskOwnerLock,
        recipient_kiosk: &mut Kiosk, 
        recipient_cap: &KioskOwnerCap, 
        policy: &mut TransferPolicy<T>,
        ctx: &mut TxContext
    ) {
        take(executable, multisig_kiosk, lock, recipient_kiosk, recipient_cap, policy, Auth {}, 0, ctx);
    }

    // step 5: destroy the executable, must `put_back_cap()`
    public fun complete_take(mut executable: Executable) {
        destroy_take(&mut executable, Auth {});
        executable.destroy(Auth {});
    }

    // step 1: propose to list nfts
    public fun propose_list(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        prices: vector<u64>,
        ctx: &mut TxContext
    ) {
        let proposal_mut = multisig.create_proposal(
            Auth {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_list(proposal_mut, nft_ids, prices);
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: list last nft in action
    public fun execute_list<T: key + store>(
        executable: &mut Executable,
        kiosk: &mut Kiosk,
        lock: &KioskOwnerLock,
    ) {
        list<T, Auth>(executable, kiosk, lock, Auth {}, 0);
    }
    
    // step 5: destroy the executable, must `put_back_cap()`
    public fun complete_list(mut executable: Executable) {
        destroy_list(&mut executable, Auth {});
        executable.destroy(Auth {});
    }

    // === [ACTION] Public functions ===

    public fun new_take(proposal: &mut Proposal, nft_ids: vector<ID>, recipient: address) {
        proposal.add_action(Take { nft_ids, recipient });
    }

    public fun take<T: key + store, W: copy + drop>(
        executable: &mut Executable,
        multisig_kiosk: &mut Kiosk, 
        lock: &KioskOwnerLock,
        recipient_kiosk: &mut Kiosk, 
        recipient_cap: &KioskOwnerCap, 
        policy: &mut TransferPolicy<T>,
        witness: W,
        idx: u64,
        ctx: &mut TxContext
    ) {
        let take_mut: &mut Take = executable.action_mut(witness, idx);
        assert!(take_mut.recipient == ctx.sender(), EWrongReceiver);

        let nft_id = take_mut.nft_ids.pop_back();
        multisig_kiosk.list<T>(&lock.kiosk_owner_cap, nft_id, 0);
        let (nft, mut request) = multisig_kiosk.purchase<T>(nft_id, coin::zero<SUI>(ctx));

        if (policy.has_rule<T, kiosk_lock_rule::Rule>()) {
            recipient_kiosk.lock(recipient_cap, policy, nft);
            kiosk_lock_rule::prove(&mut request, recipient_kiosk);
        } else {
            recipient_kiosk.place(recipient_cap, nft);
        };

        if (policy.has_rule<T, royalty_rule::Rule>()) {
            royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
        }; 

        policy.confirm_request(request);
    }

    public fun destroy_take<W: copy + drop>(executable: &mut Executable, witness: W): address {
        let Take { nft_ids, recipient } = executable.remove_action(witness);
        assert!(nft_ids.is_empty(), ETransferAllNftsBefore);
        recipient
    }

    public fun new_list(proposal: &mut Proposal, nft_ids: vector<ID>, prices: vector<u64>) {
        assert!(nft_ids.length() == prices.length(), EWrongNftsPrices);
        proposal.add_action(List { nft_ids, prices });
    }

    public fun list<T: key + store, W: copy + drop>(
        executable: &mut Executable,
        kiosk: &mut Kiosk,
        lock: &KioskOwnerLock,
        witness: W,
        idx: u64,
    ) {
        let list_mut: &mut List = executable.action_mut(witness, idx);
        let nft_id = list_mut.nft_ids.pop_back();
        let price = list_mut.prices.pop_back();
        kiosk.list<T>(&lock.kiosk_owner_cap, nft_id, price);
    }

    public fun destroy_list<W: copy + drop>(executable: &mut Executable, witness: W) {
        let List { nft_ids, prices: _ } = executable.remove_action(witness);
        assert!(nft_ids.is_empty(), EListAllNftsBefore);
    }
}
