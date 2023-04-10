module transfer_system::collateralization {
    use std::option;

    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{TxContext};
    use sui::dynamic_field;

    use ownership::ownership;
    use ownership::tx_authority::{Self, TxAuthority};

    use sui_utils::struct_tag;

    struct Witness has drop { }

    struct Request<phantom A, phantom C> has key, store {
        id: UID,
        /// The ID of the asset to requested be borrowed
        asset_id: ID,
        /// The ID of the asset to being offered as collateral
        collateral_id: ID,
        /// The date when the asset is expected to be returned
        due_date: u64,
        /// The period of time which the asset return can be delayed with after the due date has elapsed
        grace_period: u64,
        /// The status of the request
        status: u8
    }

    // `CData`, short for `CollateralData` or `CollateralizationData`
    struct CData has store, drop {
        request_id: ID,
        collateral_id: ID,
        owner: vector<address>
    }

    struct Key has store, copy, drop { }

    // ========== Error enums ==========
    const ENO_OWNER_AUTH: u64 = 0;
    const EINVALID_ASSET_LENDER: u64 = 1;
    const EINVALID_OBJECT_TYPE: u64 = 2;
    const EINVALID_DUE_DATE: u64 = 3;
    const EASSET_ID_MISMATCH: u64 = 4;
    const EREQUEST_ID_MISMATCH: u64 = 5;
    const ECOLLATERAL_ID_MISMATCH: u64 = 6;
    const EASSETS_ALREADY_COLLATERALIZED: u64 = 7;
    const EUNEXPECTED_STATUS: u64 = 8;

    // Request status enums
    const REQUEST_INITIALIZED: u8 = 0;
    const REQUEST_ACCEPTED: u8 = 1;
    const REQUEST_REJECTED: u8 = 2;
    const REQUEST_COMPLETED: u8 = 3;
    const REQUEST_OVERDUE: u8 = 4;

    public fun initialize<A: key, C: key>(
        clock: &Clock,
        asset: &UID,
        collateral: &UID,
        due_date: u64,
        ctx: &mut TxContext
    ) {
        let request = initialize_<A, C>(clock, asset, collateral, due_date, ctx);
        transfer::share_object(request)
    }

    public fun initialize_<A: key, C: key>(
        clock: &Clock,
        asset: &UID,
        collateral: &UID,
        due_date: u64,
        ctx: &mut TxContext
    ): Request<A, C> {
        // Ensures that the collateralization initializer owns the collateral item
        let auth = tx_authority::begin(ctx);
        assert!(ownership::is_authorized_by_owner(collateral, &auth), ENO_OWNER_AUTH);
        
        // Ensures that the asset `A` and collateral `C` types are valid
        assert!(matches_object_type<C>(collateral), EINVALID_OBJECT_TYPE);
        assert!(matches_object_type<A>(asset), EINVALID_OBJECT_TYPE);
       
        // Ensures that asset and collateral are not already (currently) collateralized
        assert!(!dynamic_field::exists_(asset, Key { }), EASSETS_ALREADY_COLLATERALIZED);
        assert!(!dynamic_field::exists_(collateral, Key { }), EASSETS_ALREADY_COLLATERALIZED);

        // TODO: Ensure that asset and collateral are not already (currently) not locked

        // Ensures that the due date is in the future
        assert!(clock::timestamp_ms(clock) < due_date, EINVALID_DUE_DATE);

        let request = Request {
            id: object::new(ctx),
            asset_id: object::uid_to_inner(asset),
            collateral_id: object::uid_to_inner(collateral),
            status: REQUEST_INITIALIZED,
            grace_period: 0,
            due_date,
        };

        request
    }

    public fun accept<A, C>(
        request: &mut Request<A, C>,
        clock: &Clock,
        asset: &mut UID,
        collateral: &mut UID,
        grace_period: u64,
        auth: &TxAuthority
    ) {
        assert!(request.status == REQUEST_INITIALIZED, EUNEXPECTED_STATUS);

        // Ensures that the collateralization accepter owns the asset
        assert!(ownership::is_authorized_by_owner(asset, auth), ENO_OWNER_AUTH);

        // Ensures that the specified collateral and asset matcheses the request's
        assert!(object::uid_to_inner(asset) == request.asset_id, EASSET_ID_MISMATCH);
        assert!(object::uid_to_inner(collateral) == request.collateral_id, ECOLLATERAL_ID_MISMATCH);

        // Ensures that the due date is in the future
        assert!(clock::timestamp_ms(clock) < request.due_date, EINVALID_DUE_DATE);
       
        // Ensures that asset and collateral are not already (currently) collateralized
        assert!(!dynamic_field::exists_(asset, Key { }), EASSETS_ALREADY_COLLATERALIZED);
        assert!(!dynamic_field::exists_(collateral, Key { }), EASSETS_ALREADY_COLLATERALIZED);

        // TODO: Ensure that asset and collateral are not already (currently) not locked

        // Update the grace period provided
        request.grace_period = request.grace_period + grace_period;

        let owner = ownership::get_owner(asset);
        let requester = ownership::get_owner(collateral);

        // TODO: update the collateral item. Ensure that it's locked (non transferrable)

        // Attach the collateralization data to the asset
        let c_data = CData {
            request_id: object::id(request),
            owner: option::destroy_some(owner),
            collateral_id: object::uid_to_inner(collateral),
        };
        dynamic_field::add<Key, CData>(asset, Key { }, c_data);

        // Trasfer asset to the collateralization requester
        let auth = tx_authority::begin_with_type(&Witness {});
        ownership::transfer(asset, option::destroy_some(requester), &auth);
    }

    public fun reject<A, C>(request: &mut Request<A, C>, asset: &UID, collateral: &UID, auth: &TxAuthority) {
        assert!(request.status == REQUEST_INITIALIZED, EUNEXPECTED_STATUS);

        // Ensures that the collateralization rejecter owns the asset
        assert!(ownership::is_authorized_by_owner(asset, auth), ENO_OWNER_AUTH);

        // Ensures that the specified collateral and asset matcheses the request's
        assert!(object::uid_to_inner(asset) == request.asset_id, EASSET_ID_MISMATCH);
        assert!(object::uid_to_inner(collateral) == request.collateral_id, ECOLLATERAL_ID_MISMATCH);

        request.status = REQUEST_REJECTED
    }

    public fun return_asset<A, C>(
        request: &mut Request<A, C>,
        clock: &Clock,
        asset: &mut UID,
        collateral: &mut UID,
        auth: &TxAuthority
    ) {
        assert!(request.status == REQUEST_ACCEPTED, EUNEXPECTED_STATUS);

        // Ensures that the asset returner owns the asset
        assert!(ownership::is_authorized_by_owner(asset, auth), ENO_OWNER_AUTH);

        // Ensures that the specified collateral and asset matcheses the request's
        assert!(object::uid_to_inner(asset) == request.asset_id, EASSET_ID_MISMATCH);
        assert!(object::uid_to_inner(collateral) == request.collateral_id, ECOLLATERAL_ID_MISMATCH);

        let due_at = request.due_date + request.grace_period;

        // If asset is being returned on/before due date (with grace period)
        if(due_at <= clock::timestamp_ms(clock)) {
            request.status = REQUEST_COMPLETED;

            // TODO: Transfer the ownership of the collateral back to the borrower


            // Remove the `CData` from the collateralized asset
            let c_data = dynamic_field::remove<Key, CData>(asset, Key { });

            assert!(c_data.request_id == object::id(request), EREQUEST_ID_MISMATCH);
            assert!(c_data.collateral_id == request.collateral_id, ECOLLATERAL_ID_MISMATCH);

            // Transfer the collateralized asset back to the original owner
            let auth = tx_authority::begin_with_type(&Witness {});
            ownership::transfer(asset, c_data.owner, &auth)
        } else {
            // what should we do here?
        }
    }

    public fun claim_collateral<A, C>(
        request: &mut Request<A, C>,
        clock: &Clock,
        asset: &mut UID,
        collateral: &mut UID,
        auth: &TxAuthority
    ) {
        assert!(request.status == REQUEST_ACCEPTED, EUNEXPECTED_STATUS);

        // Ensures that the collateralization accepter owns the asset
        assert!(ownership::is_authorized_by_owner(asset, auth), ENO_OWNER_AUTH);

        // Ensures that the specified collateral and asset matcheses the request's
        assert!(object::uid_to_inner(asset) == request.asset_id, EASSET_ID_MISMATCH);
        assert!(object::uid_to_inner(collateral) == request.collateral_id, ECOLLATERAL_ID_MISMATCH);

        // Ensures that the due data and the grace period has elapsed
        let due_at = request.due_date + request.grace_period;
        assert!(due_at > clock::timestamp_ms(clock), EINVALID_DUE_DATE);
       
        request.status = REQUEST_OVERDUE;

        // TODO: Transfer the ownership of the collateral to the lender


        // Remove the `CData` from the collateralized asset
        let c_data = dynamic_field::remove<Key, CData>(asset, Key { });

        assert!(c_data.request_id == object::id(request), EREQUEST_ID_MISMATCH);
        assert!(c_data.collateral_id == request.collateral_id, ECOLLATERAL_ID_MISMATCH)
    }

    // ========== Helper functions ===========

    fun matches_object_type<T>(object: &UID): bool {
        let object_type = ownership::get_type(object);
        assert!(option::is_some(&object_type), 0);

        option::destroy_some(object_type) == struct_tag::get<T>()
    }
}