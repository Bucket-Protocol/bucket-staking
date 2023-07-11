module bucket_staking::cetus_staking {

    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;
    use sui::transfer;
    use sui::event;
    use cetus_clmm::position::{Self, Position};

    const EStakeInvalidToken: u64 = 0;
    const EUnstakeNonExistentToken: u64 = 1;

    struct TokenRegistry has key, store {
        id: UID,
        pool_id: ID,
    }

    struct TokenBox has key, store {
        id: UID,
        owner: address,
        lp_token: Position,
    }

    struct StakeProof has key, store {
        id: UID,
        box_id: ID,
    }

    struct StakeEvent has copy, drop {
        registry_id: ID,
        pool_id: ID,
        lp_token_id: ID,
        timestamp: u64,
        liquidity: u128,
    }

    struct UnstakeEvent has copy, drop {
        lp_token_id: ID,
        timestamp: u64,
    }

    public fun new_registry(pool_addr: address, ctx: &mut TxContext): TokenRegistry {
        TokenRegistry {
            id: object::new(ctx),
            pool_id: object::id_from_address(pool_addr),
        }
    }

    public entry fun create_registry(pool_addr: address, ctx: &mut TxContext) {
        transfer::share_object(new_registry(pool_addr, ctx));
    }

    public fun stake(
        clock: &Clock,
        registry: &mut TokenRegistry,
        lp_token: Position,
        ctx: &mut TxContext,
    ): StakeProof {
        assert!(position::pool_id(&lp_token) == registry.pool_id, EStakeInvalidToken);

        let lp_token_id = object::id(&lp_token);
        let box_uid = object::new(ctx);
        let box_id = object::uid_to_inner(&box_uid);
        let liquidity = position::liquidity(&lp_token);
        dof::add(
            &mut registry.id,
            box_id,
            TokenBox {
                id: box_uid,
                owner: tx_context::sender(ctx),
                lp_token,
            },
        );
        event::emit(StakeEvent {
            registry_id: object::id(registry),
            pool_id: registry.pool_id,
            lp_token_id,
            timestamp: clock::timestamp_ms(clock),
            liquidity,
        });

        StakeProof {
            id: object::new(ctx),
            box_id,
        }
    }

    public entry fun stake_and_get_proof(
        clock: &Clock,
        registry: &mut TokenRegistry,
        lp_token: Position,
        ctx: &mut TxContext,
    ) {
        let proof = stake(clock, registry, lp_token, ctx);
        transfer::transfer(proof, tx_context::sender(ctx));
    }

    public fun unstake(
        clock: &Clock,
        registry: &mut TokenRegistry,
        proof: StakeProof,
    ): Position {
        let StakeProof { id, box_id } = proof;
        object::delete(id);
        assert!(
            dof::exists_with_type<ID, TokenBox>(&registry.id, box_id),
            EUnstakeNonExistentToken
        );
        let token_box = dof::remove<ID, TokenBox>(
            &mut registry.id,
            box_id,
        );
        let TokenBox { id, owner: _, lp_token } = token_box;
        object::delete(id);
        event::emit(UnstakeEvent {
            lp_token_id: object::id(&lp_token),
            timestamp: clock::timestamp_ms(clock),
        });
        lp_token
    }

    public entry fun unstake_and_get_token(
        clock: &Clock,
        registry: &mut TokenRegistry,
        proof: StakeProof,
        ctx: &TxContext,
    ) {
        let token = unstake(clock, registry, proof);
        transfer::public_transfer(token, tx_context::sender(ctx));
    }
}