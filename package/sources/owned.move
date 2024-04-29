module sui_multisig::owned {
    use sui::transfer::Receiving;
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EShouldBeWithdrawn: u64 = 1;
    const EShouldBeBorrowed: u64 = 2;

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
        object_id: ID,
        return_to: address,
    }

    public fun new(is_borrowed: bool, id: ID): Owned {
        Owned { is_borrowed, id }
    }

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
            object_id: received_id,
            return_to: multisig.uid_mut().uid_to_inner().id_to_address(),
        };

        (received, promise)
    }
    
    public fun put_back<T: key + store>(returned: T, promise: Promise) {
        let Promise { object_id, return_to } = promise;
        assert!(object::id(&returned) == object_id, EWrongObject);
        transfer::public_transfer(returned, return_to);
    }
}

