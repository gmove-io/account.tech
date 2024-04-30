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

    // action to be held in a Proposal
    public struct Access has store {
        // the owned objects we want to access
        objects: vector<Owned>,
    }

    // Owned is a struct that holds the id of the object we want to retrieve/receive
    // and whether it is borrowed or withdrawn to know whether we issue a Promise
    public struct Owned has store {
        // is the object borrowed or withdrawn
        is_borrowed: bool,
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
    
    // step 4: get the Objs and borrow or withdraw them
    public fun pop_owned(action: &mut Access): Owned {
        action.objects.pop_back()
    }

    // step 5: destroy the action once all objects are retrieved/received
    public fun complete(action: Access) {
        let Access { objects } = action;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
    }

    // === Core functions ===

    // withdraw the owned object once we unwrapped Owned    
    public fun withdraw<T: key + store>(
        multisig: &mut Multisig, 
        owned: Owned,
        received: Receiving<T>
    ): T {
        let Owned { is_borrowed, id } = owned;
        assert!(!is_borrowed, EShouldBeBorrowed);

        let received = transfer::public_receive(multisig.uid_mut(), received);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    // borrow the owned object once we unwrapped Owned    
    public fun borrow<T: key + store>(
        multisig: &mut Multisig, 
        owned: Owned,
        received: Receiving<T>
    ): (T, Promise) {
        let Owned { is_borrowed, id } = owned;
        assert!(is_borrowed, EShouldBeWithdrawn);

        let received = transfer::public_receive(multisig.uid_mut(), received);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        let promise = Promise {
            return_to: multisig.uid_mut().uid_to_inner().id_to_address(),
            object_id: received_id,
        };

        (received, promise)
    }
    
    // return the object to the multisig to destroy the hot potato
    public fun put_back<T: key + store>(returned: T, promise: Promise) {
        let Promise { return_to, object_id } = promise;
        assert!(object::id(&returned) == object_id, EWrongObject);
        transfer::public_transfer(returned, return_to);
    }

    // === Package functions ===

    // should be created only via proposals
    public(package) fun new_owned(is_borrowed: bool, id: ID): Owned {
        Owned { is_borrowed, id }
    }

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
}

