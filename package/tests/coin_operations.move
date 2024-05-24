#[test_only]
module kraken::coin_operations_tests {

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};

    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::{receiving_ticket_by_id, take_from_address, take_from_address_by_id};

    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;

    #[test]
    fun test_merge_coins() {
       let mut world = start_world();

        let coin1 = coin::mint_for_testing<SUI>(100, world.scenario().ctx());
        let coin2 = coin::mint_for_testing<SUI>(50, world.scenario().ctx());
        let coin3 = coin::mint_for_testing<SUI>(20, world.scenario().ctx());

        let id1 = object::id(&coin1);
        let id2 = object::id(&coin2);
        let id3 = object::id(&coin3);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(coin1, multisig_address);
        transfer::public_transfer(coin2, multisig_address);
        transfer::public_transfer(coin3, multisig_address);
        
        world.scenario().next_tx(OWNER);

        world.merge_coins<SUI>(receiving_ticket_by_id(id1), vector[receiving_ticket_by_id(id2), receiving_ticket_by_id(id3)]);

        world.scenario().next_tx(OWNER);

        let coin4 = take_from_address<Coin<SUI>>(world.scenario(), multisig_address);

        assert_eq(coin4.value(), 170);

        destroy(coin4);
        world.end();          
    }

    #[test]
    fun test_split_coins() {
       let mut world = start_world();

        let coin1 = coin::mint_for_testing<SUI>(100 ,world.scenario().ctx());

        let id1 = object::id(&coin1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(coin1, multisig_address);
        
        world.scenario().next_tx(OWNER);

        let ids = world.split_coins<SUI>(receiving_ticket_by_id(id1), vector[30, 20]);

        world.scenario().next_tx(OWNER);

        let coin1 = take_from_address_by_id<Coin<SUI>>(world.scenario(), multisig_address, id1);
        let coin2 = take_from_address_by_id<Coin<SUI>>(world.scenario(), multisig_address, ids[0]);
        let coin3 = take_from_address_by_id<Coin<SUI>>(world.scenario(), multisig_address, ids[1]);

        assert_eq(coin1.value(), 50);
        assert_eq(coin2.value(), 20);
        assert_eq(coin3.value(), 30);

        destroy(coin1);
        destroy(coin2);
        destroy(coin3);
        world.end();          
    }    
}