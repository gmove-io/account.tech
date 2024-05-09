/// Handle coin merging and splitting for the multisig.
/// Any member can merge and split without approvals.
/// Used to prepare a Proposal with coins having the exact amount needed.

module sui_multisig::handle_coins {
    use sui::coin::Coin;
    use sui::transfer::Receiving;
    use sui_multisig::multisig::Multisig;

    // members can merge coins, no need for approvals
    public fun merge_coins<T: drop>(
        multisig: &mut Multisig, 
        to_keep: Receiving<Coin<T>>,
        mut to_merge: vector<Receiving<Coin<T>>>, 
        ctx: &TxContext
    ) {
        multisig.assert_is_member(ctx);

        // receive all coins
        let mut merged = transfer::public_receive(multisig.uid_mut(), to_keep);
        let mut coins = vector::empty();
        while (!to_merge.is_empty()) {
            let item = to_merge.pop_back();
            let coin = transfer::public_receive(multisig.uid_mut(), item);
            coins.push_back(coin);
        };
        to_merge.destroy_empty();

        // merge all coins
        while (!coins.is_empty()) {
            merged.join(coins.pop_back());
        };
        coins.destroy_empty();

        multisig.keep(merged);
    }

    // members can split coins, no need for approvals
    // returns the IDs of the new coins for devInspect to prepare the ptb
    public fun split_coins<T: drop>(
        multisig: &mut Multisig, 
        to_split: Receiving<Coin<T>>,
        mut amounts: vector<u64>, 
        ctx: &mut TxContext
    ): vector<ID> {
        multisig.assert_is_member(ctx);

        // receive coin to split
        let mut coin = transfer::public_receive(multisig.uid_mut(), to_split);
        let mut ids = vector::empty();

        // merge all coins
        while (!amounts.is_empty()) {
            let split = coin.split(amounts.pop_back(), ctx);
            ids.push_back(object::id(&split));
            multisig.keep(split);
        };
        multisig.keep(coin);

        ids
    }
}

