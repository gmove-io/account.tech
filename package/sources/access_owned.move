/// This module allows multisig members to access objects owned by the multisig in a secure way.
/// The objects can be taken or borrowed, and only via an Access Proposal
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need

module sui_multisig::access_owned {
    use std::string::String;
    use sui::transfer::Receiving;
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EShouldBeWithdrawn: u64 = 1;
    const EShouldBeBorrowed: u64 = 2;
    const ERetrieveAllObjectsBefore: u64 = 3;

    // === Structs ===

    // action to be stored in a Proposal
    public struct Access has store {
        // the owned objects we want to access
        objects: vector<Owned>,
    }

    // can only be created in an Access action, guard access to multisig owned objects 
    public struct Owned has store {
        // is the object borrowed or withdrawn to know whether we issue a Promise
        to_borrow: bool,
        // the id of the owned object we want to retrieve/receive
        id: ID,
    }

    // hot potato ensuring the owned object is transferred back
    public struct Promise {
        // the address to return the object to (Multisig)
        return_to: address,
        // the object being borrowed
        object_id: ID,
    }

    // === Multisig functions ===

    // step 1: propose to Access owned objects
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        expiration: u64,
        description: String,
        objects_to_borrow: vector<ID>,
        objects_to_withdraw: vector<ID>,
        ctx: &mut TxContext
    ) {
        let action = new_access(objects_to_borrow, objects_to_withdraw);
        multisig.create_proposal(
            action,
            name,
            expiration,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)
    
    // step 4: get the Owned struct to call withdraw or borrow
    public fun pop_owned(action: &mut Access): Owned {
        action.objects.pop_back()
    }

    // step 5: receive and take the owned object using Owned    
    public fun take<T: key + store>(
        multisig: &mut Multisig, 
        owned: Owned,
        receiving: Receiving<T>
    ): T {
        let Owned { to_borrow, id } = owned;
        assert!(!to_borrow, EShouldBeBorrowed);

        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    // step 5 (bis): receive and borrow the owned object using Owned    
    public fun borrow<T: key + store>(
        multisig: &mut Multisig, 
        owned: Owned,
        receiving: Receiving<T>
    ): (T, Promise) {
        let Owned { to_borrow, id } = owned;
        assert!(to_borrow, EShouldBeWithdrawn);

        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        let promise = Promise {
            return_to: multisig.uid_mut().uid_to_inner().id_to_address(),
            object_id: received_id,
        };

        (received, promise)
    }
    
    // step 5 (bis): if borrowed, return the object to the multisig to destroy the hot potato
    public fun put_back<T: key + store>(returned: T, promise: Promise) {
        let Promise { return_to, object_id } = promise;
        assert!(object::id(&returned) == object_id, EWrongObject);
        transfer::public_transfer(returned, return_to);
    }

    // step 6: destroy the action once all objects are retrieved/received
    public fun complete(action: Access) {
        let Access { objects } = action;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
    }

    // === Package functions ===

    // Access can be wrapped into another action
    public(package) fun new_access(
        mut to_borrow: vector<ID>,
        mut to_withdraw: vector<ID>
    ): Access {
        let mut objects = vector[];
        while (!to_borrow.is_empty()) {
            objects.push_back(new_owned(true, to_borrow.pop_back()));
        };
        while (!to_withdraw.is_empty()) {
            objects.push_back(new_owned(false, to_withdraw.pop_back()));
        };
        Access { objects }
    }

    // callable only via new_access
    public(package) fun new_owned(to_borrow: bool, id: ID): Owned {
        Owned { to_borrow, id }
    }
}

