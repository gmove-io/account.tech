module sui_multisig::owned {
    use sui_multisig::multisig::{Multisig, Promise};

    public struct CapRequest<phantom N> has store {}

    // to facilitate discovery on frontends
    public struct CapKey<phantom N> has copy, drop, store {}

    // add a Cap to the Multisig for access control
    // attached cap can't be removed, only borrowed
    // only members can attach caps
    public fun attach_cap<C: key + store>(
        multisig: &mut Multisig, 
        cap: C,
        ctx: &mut TxContext
    ) {
        multisig.attach_object(CapKey<C> {}, cap, ctx);
    }

    public fun request_cap<C: key + store>(): CapRequest<C> {
        CapRequest {}
    }

    // caps can only be borrowed via a proposal
    // issue a hot potato to make sure the cap is returned
    public fun borrow_cap<C: key + store>(
        request: CapRequest<C>,
        multisig: &mut Multisig, 
        ctx: &TxContext
    ): (C, Promise) {
        let CapRequest {} = request;
        multisig.borrow_object(CapKey<C> {}, ctx)
    }

    // re-attach the cap and destroy the hot potato
    public fun return_cap<C: key + store>(
        multisig: &mut Multisig, 
        cap: C, 
        request: Promise,
        ctx: &mut TxContext
    ) {
        multisig.return_object(CapKey<C> {}, cap, request, ctx);
    }
}

