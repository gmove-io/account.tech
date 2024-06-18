/// This module demonstrates how to create a proposal with a custom action.
/// Here the action accessors are public and guarded by a witness.
/// This means that any package can reuse this action for implementing its own proposal.

module examples::access_control_composable {
    use std::string::String;
    use kraken::{
        multisig::{Multisig, Executable, Proposal}
    };

    // === Constants ===

    const MAX_FEE: u64 = 10000; // 100%

    // === Structs ===

    public struct Witness has drop {}

    // [ACTION] action structs must have store only 
    public struct UpdateFee has store {
        fee: u64,
    }

    public struct Protocol has key {
        id: UID,
        // add bunch of fields
        fee: u64,
    }

    // === Public functions ===

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Protocol {
            id: object::new(ctx),
            fee: 0,
        });
    }    

    /*
    * the rest of the module implementation 
    * { ... }
    */

    // === [PROPOSAL] Public functions ===
    
    // step 1: propose to update the version
    public fun propose_update_fee(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        fee: u64,
        ctx: &mut TxContext
    ) {
        assert!(fee <= MAX_FEE);
        let proposal_mut = multisig.create_proposal(
            Witness {},
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
        new_update_fee(proposal_mut, fee);
    }

    // step 2: multiple members have to approve the proposal (kraken::multisig::approve_proposal)
    // step 3: execute the proposal and return the action (kraken::multisig::execute_proposal)

    // function guarded by a Multisig action
    public fun execute_update_fee(
        mut executable: Executable,
        multisig: &mut Multisig,
        protocol: &mut Protocol,
    ) {
        // here index is 0 because there is only one action in the proposal
        update_fee(protocol, &mut executable, multisig, Witness {}, 0);
        destroy_update_fee(&mut executable, Witness {});
        executable.destroy(Witness {});
    }

    // === [ACTION] functions ===

    /// These functions are public and guarded by a witness to ensure correct proposal implementation
    /// This is the pattern that should be use to make actions available to other packages.

    public fun new_update_fee(proposal: &mut Proposal, fee: u64) {
        proposal.add_action(UpdateFee { fee });
    }

    public fun update_fee<W: drop>(
        protocol: &mut Protocol,
        executable: &mut Executable,
        multisig: &Multisig,
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let update_fee_mut: &mut UpdateFee = executable.action_mut(witness, idx);
        protocol.fee = update_fee_mut.fee;
        update_fee_mut.fee = MAX_FEE + 1; // set to > max to enforce exactly one execution
    }
        
    public fun destroy_update_fee<W: drop>(
        executable: &mut Executable,
        witness: W,
    ) {
        let UpdateFee { fee } = executable.remove_action(witness);
        assert!(fee == MAX_FEE + 1);
    }
}