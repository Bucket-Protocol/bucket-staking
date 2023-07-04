module bucket_staking::simple_staking {

    use std::ascii::String;
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use sui::transfer;
    use sui::event;
    use std::type_name;

    struct TokenRegistry<phantom T> has key, store {
        id: UID,
    }

    struct TokenBox<T: key + store> has store {
        owner: address,
        token: T,
    }

    struct StakeProof<phantom T> has key, store {
        id: UID,
        token_id: ID,
    }

    struct StakeEvent has copy, drop {
        type: String,
        registry_id: ID,
        timestamp: u64,
    }

    struct UnstakeEvent has copy, drop {
        type: String,
        registry_id: ID,
        timestamp: u64,
    }

    public fun new_registry<T>(ctx: &mut TxContext): TokenRegistry<T> {
        TokenRegistry { id: object::new(ctx) }
    }

    public entry fun create_registry<T>(ctx: &mut TxContext) {
        transfer::share_object(new_registry<T>(ctx));
    }

    public fun stake<T: key + store>(
        clock: &Clock,
        registry: &mut TokenRegistry<T>,
        token: T,
        ctx: &mut TxContext,
    ): StakeProof<T> {
        let token_id = object::id(&token);
        df::add(
            &mut registry.id,
            token_id,
            TokenBox {
                owner: tx_context::sender(ctx),
                token,
            },
        );
        event::emit(StakeEvent {
            type: type_name::into_string(type_name::get<T>()),
            registry_id: object::id(registry),
            timestamp: clock::timestamp_ms(clock),
        });

        StakeProof {
            id: object::new(ctx),
            token_id,
        }
    }

    public entry fun stake_and_get_proof<T: key + store>(
        clock: &Clock,
        registry: &mut TokenRegistry<T>,
        token: T,
        ctx: &mut TxContext,
    ) {
        let proof = stake(clock, registry, token, ctx);
        transfer::transfer(proof, tx_context::sender(ctx));
    }

    public fun unstake<T: key + store>(
        clock: &Clock,
        registry: &mut TokenRegistry<T>,
        proof: StakeProof<T>,
    ): T {
        let StakeProof { id, token_id } = proof;
        object::delete(id);
        let token_box = df::remove<ID, TokenBox<T>>(
            &mut registry.id,
            token_id,
        );
        let TokenBox { owner: _, token } = token_box;
        event::emit(StakeEvent {
            type: type_name::into_string(type_name::get<T>()),
            registry_id: object::id(registry),
            timestamp: clock::timestamp_ms(clock),
        });
        token
    }

    public entry fun unstake_and_get_token<T: key + store>(
        clock: &Clock,
        registry: &mut TokenRegistry<T>,
        proof: StakeProof<T>,
        ctx: &TxContext,
    ) {
        let token = unstake(clock, registry, proof);
        transfer::public_transfer(token, tx_context::sender(ctx));
    }

    #[test]
    fun test_stake_and_unstake() {
        use sui::test_scenario as ts;
        use sui::sui::SUI;
        use sui::balance;
        use sui::coin::{Self, Coin};
        use sui::transfer;

        let dev = @0xde1;
        let staker = @0x123;

        let scenario_val = ts::begin(dev);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ts::ctx(scenario));
        {
            create_registry<Coin<SUI>>(ts::ctx(scenario));
            let coin = coin::from_balance(balance::create_for_testing<SUI>(100), ts::ctx(scenario));
            transfer::public_transfer(coin, staker);
        };

        ts::next_tx(scenario, staker);
        {
            let registry = ts::take_shared<TokenRegistry<Coin<SUI>>>(scenario);
            assert!(ts::has_most_recent_for_sender<Coin<SUI>>(scenario), 0);
            assert!(!ts::has_most_recent_for_sender<StakeProof<Coin<SUI>>>(scenario), 0);
            let coin = ts::take_from_sender<Coin<SUI>>(scenario);
            stake_and_get_proof(&clock, &mut registry, coin, ts::ctx(scenario));
            ts::return_shared(registry);
        };

        ts::next_tx(scenario, staker);
        {
            let registry = ts::take_shared<TokenRegistry<Coin<SUI>>>(scenario);
            assert!(!ts::has_most_recent_for_sender<Coin<SUI>>(scenario), 0);
            assert!(ts::has_most_recent_for_sender<StakeProof<Coin<SUI>>>(scenario), 0);
            let proof = ts::take_from_sender<StakeProof<Coin<SUI>>>(scenario);
            unstake_and_get_token(&clock, &mut registry, proof, ts::ctx(scenario));
            ts::return_shared(registry);
        };

        ts::next_tx(scenario, staker);
        {
            assert!(ts::has_most_recent_for_sender<Coin<SUI>>(scenario), 0);
            assert!(!ts::has_most_recent_for_sender<StakeProof<Coin<SUI>>>(scenario), 0);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario_val);
    }
}