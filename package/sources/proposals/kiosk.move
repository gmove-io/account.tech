/// The user to transfer from / to must be a member of the multisig.
/// The functions take the caller's kiosk and the multisig's kiosk to execute the transfer.

module kraken::kiosk {
    use std::string::String;
    use sui::coin;
    use sui::transfer::Receiving;
    use sui::sui::SUI;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::TransferPolicy;
    use kiosk::{kiosk_lock_rule, royalty_rule};
    use kraken::multisig::{Multisig, Executable};

    // === Errors ===

    const EWrongReceiver: u64 = 1;
    const ETransferAllNftsBefore: u64 = 2;
    const EWrongNftsPrices: u64 = 3;
    const EListAllNftsBefore: u64 = 4;

    // === Structs ===    

    public struct Witness has drop {}
    
    // Wrapper restricting access to a KioskOwnerCap
    // doesn't have store because non-transferrable
    public struct KioskOwnerLock has key {
        id: UID,
        // the cap to lock
        kiosk_owner_cap: KioskOwnerCap,
    }

    // [ACTION] transfer nfts from the multisig's kiosk to another one
    public struct Take has store {
        // id of the nfts to transfer
        nfts: vector<ID>,
        // owner of the receiver kiosk
        recipient: address,
    }

    // [ACTION] list nfts for purchase
    public struct List has store {
        // id of the nfts to list
        nfts: vector<ID>,
        // sui amount
        prices: vector<u64>, 
    }

    // === Member only functions ===

    // not composable because of the lock
    public fun new(multisig: &Multisig, ctx: &mut TxContext) {
        multisig.assert_is_member(ctx);
        let (mut kiosk, cap) = kiosk::new(ctx);
        kiosk.set_owner_custom(&cap, multisig.addr());

        transfer::public_share_object(kiosk);
        transfer::transfer(
            KioskOwnerLock { id: object::new(ctx), kiosk_owner_cap: cap }, 
            multisig.addr()
        );
    }

    // borrow the lock that can only be put back in the multisig because no store
    public fun borrow_cap(
        multisig: &mut Multisig, 
        kiosk_owner_lock: Receiving<KioskOwnerLock>,
    ): KioskOwnerLock {
        transfer::receive(multisig.uid_mut(), kiosk_owner_lock)
    }

    public fun put_back_cap(
        multisig: &Multisig, 
        kiosk_owner_lock: KioskOwnerLock,
    ) {
        transfer::transfer(kiosk_owner_lock, multisig.addr());
    }

    // deposit from another Kiosk, no need for proposal
    // step 1: borrow_cap
    // move the nft, validate the request and confirm it
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

    // === Multisig only functions ===

    // step 1: propose to transfer nfts to another kiosk
    public fun propose_take(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nfts: vector<ID>,
        recipient: address,
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
        proposal_mut.push_action(new_take(nfts, recipient));
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: the recipient (anyone) must loop over this function to take the nfts in any of his Kiosks
    public fun take<T: key + store>(
        executable: &mut Executable,
        multisig_kiosk: &mut Kiosk, 
        lock: &KioskOwnerLock,
        recipient_kiosk: &mut Kiosk, 
        recipient_cap: &KioskOwnerCap, 
        policy: &mut TransferPolicy<T>,
        idx: u64,
        ctx: &mut TxContext
    ) {
        assert!(executable.action_mut<Take>(idx).recipient == ctx.sender(), EWrongReceiver);

        let nft_id = executable.action_mut<Take>(idx).nfts.pop_back();
        multisig_kiosk.list<T>(&lock.kiosk_owner_cap, nft_id, 0);
        let (nft, request) = multisig_kiosk.purchase<T>(nft_id, coin::zero<SUI>(ctx));
        recipient_kiosk.place(recipient_cap, nft);

        if (policy.has_rule<T, kiosk_lock_rule::Rule>()) {
            recipient_kiosk.lock(&lock.kiosk_owner_cap, policy, nft);
            kiosk_lock_rule::prove(&mut request, recipient_kiosk);
        } else {
            recipient_kiosk.place(&lock.kiosk_owner_cap, nft);
        };

        if (policy.has_rule<T, royalty_rule::Rule>()) {
            royalty_rule::pay(policy, &mut request, coin::zero<SUI>(ctx));
        }; 

        policy.confirm_request(request);
    }

    // step 5: destroy the executable, must `put_back_cap()`
    public fun complete_take(executable: Executable) {
        let take: Take = executable.pop_action(Witness {});
        let (nfts, _) = take.destroy_take();
        executable.destroy_executable(Witness {});
        assert!(nfts.is_empty(), ETransferAllNftsBefore);
        nfts.destroy_empty();
    }

    // step 1: propose to list nfts
    public fun propose_list(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nfts: vector<ID>,
        prices: vector<u64>,
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
        proposal_mut.push_action(new_list(nfts, prices));
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: list last nft in action
    public fun list<T: key + store>(
        executable: &mut Executable,
        kiosk: &mut Kiosk,
        lock: &KioskOwnerLock,
        idx: u64,
    ) {
        let nft_id = executable.action_mut<List>(idx).nfts.pop_back();
        let price = executable.action_mut<List>(idx).prices.pop_back();
        kiosk.list<T>(&lock.kiosk_owner_cap, nft_id, price);
    }
    
    // step 5: destroy the executable, must `put_back_cap()`
    public fun complete_list(executable: Executable) {
        let list: List = executable.pop_action(Witness {});
        let (nfts, _) = list.destroy_list();
        executable.destroy_executable(Witness {});
        assert!(nfts.is_empty(), EListAllNftsBefore);
        nfts.destroy_empty();
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

    // === [ACTIONS] Public functions ===

    public fun new_take(nfts: vector<ID>, recipient: address): Take {
        Take { nfts, recipient }
    }

    public fun destroy_take(transfer: Take): (vector<ID>, address) {
        let Take { nfts, recipient } = transfer;
        
        (nfts, recipient)
    }

    public fun new_list(nfts: vector<ID>, prices: vector<u64>): List {
        assert!(nfts.length() == prices.length(), EWrongNftsPrices);
        List { nfts, prices }
    }

    public fun destroy_list(list: List): (vector<ID>, vector<u64>) {
        let List { nfts, prices } = list;
        (nfts, prices)
    }

    // === Test functions ===

    // #[test_only]
    // public fun place<T: key + store>(multisig_kiosk: &mut Kiosk, cap: &KioskOwnerCap, nft: T) {
    //     multisig_kiosk.place(cap, nft);
    // }

    // #[test_only]
    // public fun kiosk_list<T: key + store>(multisig_kiosk: &mut Kiosk, cap: &KioskOwnerCap, nft_id: ID, price: u64)  {
    //     multisig_kiosk.list<T>(cap, nft_id, price);        
    // }

    // #[test_only]
    // public fun borrow_cap(
    //     multisig: &mut Multisig, 
    //     multisig_cap: Receiving<KioskOwnerCap>,
    // ): KioskOwnerCap {
    //     transfer::public_receive(multisig.uid_mut(), multisig_cap)
    // }    
}
