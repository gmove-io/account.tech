/// Users have a non-transferable account object used to track Multisigs in which they are a member.
/// They can also set a username and profile picture to be displayed on the various frontends.
/// Multisig members can send on-chain invites to new members. 
/// Alternatively, multisig creators can share an invite link to new members that can join the multisig without invite.
/// Invited users can accept or refuse the invite, to add the multisig id to their account or not.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module kraken_multisig::account;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet},
    table::{Self, Table},
};
use kraken_multisig::multisig::Multisig;

// === Errors ===

const ENotMember: u64 = 0;
const EWrongMultisig: u64 = 1;
const EMustLeaveAllMultisigs: u64 = 2;
const EAlreadyHasAccount: u64 = 3;

// === Struct ===

/// Shared object enforcing one account maximum per user
public struct Registry has key {
    id: UID,
    // address to account mapping
    accounts: Table<address, ID>,
}

/// Non-transferable user account for tracking multisigs
public struct Account has key {
    id: UID,
    // to display on the frontends
    username: String,
    // to display on the frontends
    profile_picture: String,
    // multisigs that the user has joined
    multisig_ids: VecSet<ID>,
}

/// Invite object issued by a multisig to a user
public struct Invite has key { 
    id: UID, 
    // multisig that issued the invite
    multisig_id: ID,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Registry {
        id: object::new(ctx),
        accounts: table::new(ctx),
    });
}

/// Creates a soulbound account (1 per user)
public fun new(username: String, profile_picture: String, ctx: &mut TxContext): Account {
    Account {
        id: object::new(ctx),
        username,
        profile_picture,
        multisig_ids: vec_set::empty(),
    }
}

// === [MEMBER] Public functions ===

/// Fills account_id in Multisig, inserts multisig_id in Account, aborts if already joined
public fun join_multisig(account: &mut Account, multisig: &mut Multisig, ctx: &TxContext) {
    multisig.member_mut(ctx.sender()).register_account_id(account.id.to_inner());
    account.multisig_ids.insert(object::id(multisig)); 
}

/// Extracts and verifies account_id in Multisig, removes multisig_id from account, aborts if not member
public fun leave_multisig(account: &mut Account, multisig: &mut Multisig, ctx: &TxContext) {
    multisig.member_mut(ctx.sender()).unregister_account_id();
    account.multisig_ids.remove(&object::id(multisig));
}

/// Can transfer the account only if the other address has no account yet
public fun transfer(registry: &mut Registry, account: Account, recipient: address) {
    assert!(!registry.accounts.contains(recipient), EAlreadyHasAccount);
    transfer::transfer(account, recipient);
}

/// Must leave all multisigs before, for consistency
public fun destroy(account: Account) {
    let Account { id, multisig_ids, .. } = account;
    assert!(multisig_ids.is_empty(), EMustLeaveAllMultisigs);
    id.delete();
}

/// Invites can be sent by a multisig member (upon multisig creation for instance)
public fun send_invite(multisig: &Multisig, recipient: address, ctx: &mut TxContext) {
    // user inviting must be member
    multisig.assert_is_member(ctx);
    // invited user must be member
    assert!(multisig.members().is_member(recipient), ENotMember);
    let invite = Invite { 
        id: object::new(ctx), 
        multisig_id: object::id(multisig) 
    };
    transfer::transfer(invite, recipient);
}

/// Invited user can register the multisig in his account
public fun accept_invite(account: &mut Account, multisig: &mut Multisig, invite: Invite, ctx: &TxContext) {
    let Invite { id, multisig_id } = invite;
    id.delete();
    assert!(multisig_id == object::id(multisig), EWrongMultisig);
    account.join_multisig(multisig, ctx);
}

/// Deletes the invite object
public fun refuse_invite(invite: Invite) {
    let Invite { id, .. } = invite;
    id.delete();
}

// === View functions ===    

public fun username(account: &Account): String {
    account.username
}

public fun profile_picture(account: &Account): String {
    account.profile_picture
}

public fun multisig_ids(account: &Account): vector<ID> {
    account.multisig_ids.into_keys()
}

public fun multisig_id(invite: &Invite): ID {
    invite.multisig_id
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}