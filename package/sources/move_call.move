module sui_multisig::move_call {
    use std::string::String;
    use sui::bag::{Self, Bag};

    use sui_multisig::multisig::{Multisig, Request};

    // === Structs ===

    // dev should define a PackageCap in the package where the Multisig will be used
    // this cap will be used to guard functions preventing anyone to call them
    public struct PackageCapKey has copy, drop, store {}

    public struct Arg<T: store> has copy, drop, store {
        is_obj: bool,
        value: T,
    }

    public struct MoveCall has store {
        // which function we want to call
        function: String,
        // arguments for the function, using dynamic fields
        arguments: Bag, 
    }

    // === Public mutative functions ===

    // attach a PackageCap to the multisig
    // this cap should be created in the package using the multisig
    // the cap will prevent anyone from calling multisig guarded functions
    public fun attach_package_cap<PC: key + store>(
        multisig: &mut Multisig, 
        name: String, 
        cap: PC,
        ctx: &mut TxContext
    ) {
        multisig.attach_cap(name, cap, ctx);
    }

    // step 1: create a Bag to store the Args

    // step 2: construct Args and insert them into a Bag
    // construct a new Arg
    public fun new_arg<T: store>(is_obj: bool, value: T): Arg<T> {
        Arg { is_obj, value }
    }

    // step 3: add Arg to Bag

    // retrieve the Arg value and return whether it's supposed to be an object
    public fun get_arg<T: store>(args: &mut Bag, key: String): (bool, T) {
        let arg = bag::remove(args, key);
        let Arg { is_obj, value } = arg;
        (is_obj, value)
    }

    // step 4: propose a MoveCall for an owned package
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        function: String,
        arguments: Bag,
        ctx: &mut TxContext
    ) {
        let action = MoveCall { function, arguments };
        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }

    // step 5: multiple members have to approve the proposal (multisig::approve_proposal)
    
    // step 6: execute the action and return the borrowed cap with function name and args
    public fun execute<PC: key + store>(
        multisig: &mut Multisig, 
        name: String, 
        ctx: &mut TxContext
    ): (String, Bag, PC, Request) {
        let action = multisig.execute_proposal(name, ctx);
        let MoveCall { function, arguments } = action;

        let (cap, request) = multisig.borrow_cap(PackageCapKey {}, ctx);

        (function, arguments, cap, request)
    }    

    // step 7: assert cap & function name, then use args in the function
}

