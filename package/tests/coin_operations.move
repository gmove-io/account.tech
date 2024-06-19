#[test_only]
module kraken::coin_operations_tests {

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};

    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::receiving_ticket_by_id;

    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;

    #[test]
    fun test_merge() {
       let mut world = start_world();

        let coin1 = coin::mint_for_testing<SUI>(100, world.scenario().ctx());

        let id1 = object::id(&coin1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(coin1, multisig_address);
        
        world.scenario().next_tx(OWNER);

        let split_coins = world.merge_and_split<SUI>(
            vector[receiving_ticket_by_id(id1)],
            vector[30, 40] // LIFO
        );

        world.scenario().next_tx(OWNER);
        
        let split_coin0 = world.scenario().take_from_address_by_id<Coin<SUI>>(multisig_address, split_coins[0]);
        let split_coin1 = world.scenario().take_from_address_by_id<Coin<SUI>>(multisig_address, split_coins[1]);

        assert_eq(split_coin0.value(), 40);
        assert_eq(split_coin1.value(), 30);

        destroy(split_coin0);
        destroy(split_coin1);
        world.end();          
    }  
}