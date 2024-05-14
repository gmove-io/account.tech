/// Users have a non-transferable Account used to track Multisigs in which they are a member.
/// They can also set a username and profile picture to be displayed on the frontends.

module kraken::account {
    use std::string::String;
    use sui::vec_set::{Self, VecSet};

    // non-transferable user account for tracking multisigs
    public struct Account has key {
        id: UID,
        // to display on the frontends
        username: String,
        // to display on the frontends
        profile_picture: String,
        // multisigs that the user has joined
        multisigs: VecSet<ID>,
    }

    // creates and send a soulbound Account to the sender (1 per user)
    public fun new(username: String, profile_picture: String, ctx: &mut TxContext) {
        transfer::transfer(
            Account {
                id: object::new(ctx),
                username,
                profile_picture,
                multisigs: vec_set::empty(),
            },
            ctx.sender(),
        );
    }

    // doesn't modify Multisig's members, abort if already member
    public fun join_multisig(account: &mut Account, multisig: ID) {
        account.multisigs.insert(multisig); 
    }

    // doesn't modify Multisig's members, abort if not member
    public fun leave_multisig(account: &mut Account, multisig: ID) {
        account.multisigs.remove(&multisig);
    }

    public fun destroy(account: Account) {
        let Account { id, username: _, profile_picture: _, multisigs: _ } = account;
        id.delete();
    }
}

