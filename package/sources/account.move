/// Users have a non-transferable Account used to track Multisigs in which they are a member.
/// They can also set a username and profile picture to be displayed on the frontends.
/// Multisig members can send on-chain invites to new members.
/// Invited users can accept or refuse the invite, to add the multisig id to their account or not.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module kraken::account {
    use std::string::String;
    use sui::vec_set::{Self, VecSet};
    use sui::transfer::Receiving;
    use kraken::multisig::Multisig;

    // === Errors ===

    const ENotMember: u64 = 0;

    // === Struct ===

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

    public struct Invite has key { 
        id: UID, 
        multisig: ID,
    }

    // === Public mutative functions ===

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

    // === Member only functions ===

    // invites can be sent by a multisig member (upon multisig creation for instance)
    public fun send_invite(multisig: &mut Multisig, account: address, ctx: &mut TxContext): ID {
        // user inviting must be member
        multisig.assert_is_member(ctx);
        // invited user must be member
        assert!(multisig.members().contains(&ctx.sender()), ENotMember);
        let invite = Invite { 
            id: object::new(ctx), 
            multisig: multisig.uid_mut().uid_to_inner() 
        };
        let invite_id = object::id(&invite);
        transfer::transfer(invite, account);

        invite_id
    }

    // invited user can register the multisig in his account
    public fun accept_invite(account: &mut Account, invite: Receiving<Invite>) {
        let received = transfer::receive(&mut account.id, invite);
        let Invite { id, multisig } = received;
        id.delete();
        account.multisigs.insert(multisig);
    }

    // delete the invite object
    public fun refuse_invite(account: &mut Account, invite: Receiving<Invite>) {
        let received = transfer::receive(&mut account.id, invite);
        let Invite { id, multisig: _ } = received;
        id.delete();
    }

    // === View functions ===    

    public fun username(account: &Account): String {
        account.username
    }

    public fun profile_picture(account: &Account): String {
        account.profile_picture
    }

    public fun multisigs(account: &Account): vector<ID> {
        account.multisigs.into_keys()
    }

    public fun multisig(invite: &Invite): ID {
        invite.multisig
    }
}