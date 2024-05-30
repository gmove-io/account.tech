/// This module allows multisig members to access objects owned by the multisig in a secure way.
/// The objects can be taken only via an Withdraw action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed using an action wrapping the Withdraw action.
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need

module kraken::owned {    
    use sui::transfer::Receiving;
    use kraken::multisig::{Multisig, Executable};

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EReturnAllObjectsBefore: u64 = 1;
    const ERetrieveAllObjectsBefore: u64 = 2;

    // === Structs ===

    // [ACTION] guard access to multisig owned objects which can only be received via this action
    public struct Withdraw has store {
        // the owned objects we want to access
        objects: vector<ID>,
    }

    // [ACTION] enforces accessed objects to be sent back to the multisig
    public struct Borrow has store {
        // list of objects to put back into the multisig
        to_return: vector<ID>,
    }

    // === [ACTIONS] Public functions ===

    public fun new_withdraw(objects: vector<ID>): Withdraw {
        Withdraw { objects }
    }

    public fun withdraw<T: key + store>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        idx: u64,
    ): T {
        let action = executable.action_mut<Withdraw>(idx);
        let (_, index) = action.objects.index_of(&transfer::receiving_object_id(&receiving));
        let id = action.objects.remove(index);

        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    public fun destroy_withdraw(action: Withdraw) {
        let Withdraw { objects } = action;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
    }

    public fun new_borrow(objects: vector<ID>): Borrow {
        Borrow { to_return: objects }
    }

    public fun borrow<T: key + store>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        idx: u64,
    ): T {
        withdraw(executable, multisig, receiving, idx + 1)
    }
    
    public fun put_back<T: key + store>(
        executable: &mut Executable,
        multisig: &Multisig, 
        returned: T, 
        idx: u64,
    ) {
        let action = executable.action_mut<Borrow>(idx);
        let (exists_, index) = action.to_return.index_of(&object::id(&returned));
        assert!(exists_, EWrongObject);

        action.to_return.remove(index);
        transfer::public_transfer(returned, multisig.addr());
    }

    public fun destroy_borrow(action: Borrow) {
        let Borrow { to_return } = action;
        assert!(to_return.is_empty(), EReturnAllObjectsBefore);
        to_return.destroy_empty();
    }
}
