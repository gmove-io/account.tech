module sui_multisig::move_call {
    use std::string::String;
    use sui::bag::{Self, Bag};
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const ERetrieveAllObjectsBefore: u64 = 0;

    // === Structs ===

    // dev should define a PackageCap in the package where the Multisig will be used
    // this cap will be used to guard functions preventing anyone to call them
    public struct PackageCapKey has copy, drop, store {}

    // Arg is a struct that can hold a Move type or an object id
    // if it is a Move type, it is directly use in the function
    // if it is an object, the object is passed to the function and its id is checked
    public struct Arg<T: store> has copy, drop, store {
        // is it a Move type or an object
        is_obj: bool,
        // the id of the shared object we want to pass or the Move type
        value: T,
    }

    // Obj is a struct that holds the id of the object we want to retrieve/receive
    // and whether it is borrowed or withdrawn to know whether we issue a Promise
    public struct Obj has store {
        // is the object borrowed or withdrawn
        is_borrowed: bool,
        // the id of the owned object we want to retrieve/receive
        id: ID,
    }

    public struct MoveCall has store {
        // which function we want to call
        function: String,
        // arguments for the function, using dynamic fields
        arguments: Bag, 
        // owned objects we want to retrieve/receive to use in the call
        objects: vector<Obj>,
    }

    // === Public mutative functions ===

    // step 1: create a Bag to store the Args (can be empty)
    // & create a vector for the objects we want to retrieve (can be empty)

    // step 2: construct Args and insert them into a Bag
    // construct a new Arg
    public fun new_arg<T: store>(is_obj: bool, value: T): Arg<T> {
        Arg { is_obj, value }
    }

    public fun new_obj(is_borrowed: bool, id: ID): Obj {
        Obj { is_borrowed, id }
    }

    // step 3: add Arg to Bag
    // & add Obj to vector

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
        objects: vector<Obj>,
        ctx: &mut TxContext
    ) {
        let action = MoveCall { function, arguments, objects };
        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }

    // step 5: multiple members have to approve the proposal (multisig::approve_proposal)
    
    // step 6: execute the proposal and return the action (multisig::execute_proposal)
    
    // step 7: get the Objs and retrieve/receive them in multisig::owned
    public fun pop_obj(action: &mut MoveCall): Obj {
        action.objects.pop_back()
    }

    // step 8: unwrap the MoveCall and return function name and args
    public fun execute(action: MoveCall): (String, Bag) {
        let MoveCall { function, arguments, objects } = action;

        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();

        (function, arguments)
    }    

    // step 9: in the package, function name, 
    // then use args and received objects (assert id) in the function
}

