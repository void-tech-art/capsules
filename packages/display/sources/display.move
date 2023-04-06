// Sui's On-Chain Template-system for Displaying Objects

// Type objects are root-level owned objects storing default display data for a given type `T`.
// Rather than using devInspect transactions along with data::view(), the intention is that Sui Fullnodes
// will handle this all for clients behind the scenes.
//
// Type objects can also act as fallbacks when querying for the display-data of an object.
// For example, if you're creating a Capsule like 0x599::outlaw_sky::Outlaw, and you have a dynamic-field for a
// view-function like 'created_by' that will be identical for every Outlaw, it would be wasteful to duplicate
// this field once for every object (10,000x times).
// Instead you can leave that field undefined, and define it once on Display<0x599::outlaw_sky::Outlaw>.
//
// The intent for Display objects is that they should be owned and maintained by the package-publisher, or frozen.

module display::display {
    use std::option::Option;
    use std::string::String;
    use std::vector;

    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::transfer;
    use sui::vec_map::VecMap;

    use sui_utils::encode;
    use sui_utils::struct_tag;
    use sui_utils::typed_id;
    use sui_utils::vec_map2;

    use ownership::ownership;
    use ownership::publish_receipt::{Self, PublishReceipt};
    use ownership::tx_authority::{Self, TxAuthority};

    use display::abstract_display::{Self, AbstractDisplay};

    use attach::data;
    use attach::schema;

    // error enums
    const EINVALID_PUBLISH_RECEIPT: u64 = 0;
    const ETYPE_ALREADY_DEFINED: u64 = 1;
    const ETYPE_IS_NOT_CONCRETE: u64 = 2;
    const EVEC_LENGTH_MISMATCH: u64 = 3;
    const EABSTRACT_DOES_NOT_MATCH_CONCRETE: u64 = 4;
    const ETYPE_IN_RESOLVER_NOT_SPECIFIED: u64 = 5;

    // ========= Concrete Type =========

    // Owned, root-level object. Cannot be destroyed. Singleton, unique on `T`.
    // We could potentially make these storeable as well; it depends if the Sui Fullnode will be able to
    // find it to do resolution.
    struct Display<phantom T> has key {
        id: UID,
        resolvers: VecMap<String, vector<String>>
        // <data::Key { slot: String }> : <T: store>, data-fields owned by owner
    }

    // Added to publish receipt
    struct Key has store, copy, drop { slot: String } // slot is a module + struct name, value is boolean

    // Added to abstract-type to ensure that each concrete type (set of generics) can only ever be defined once
    struct KeyGenerics has store, copy, drop { generics: vector<String> }
    
    // Module authority
    struct Witness has drop { }

    // ========= Create Type Metadata =========

    // Convenience entry function
    public entry fun claim<T>(
        publisher: &mut PublishReceipt,
        keys: vector<String>,
        resolver_strings: vector<vector<String>>,
        ctx: &mut TxContext
    ) {
        let display = claim_<T>(publisher, keys, resolver_strings, ctx);
        transfer::transfer(display, tx_context::sender(ctx));
    }

    // `T` must not contain any generics. If it does, you must first use `define_abstract()` to create
    // an AbstractDisplay object, which is then used with `create_from_abstract()` to define a concrete type
    // per instance of its generics.
    //
    // The `resolver_strings` input to this function should look like:
    // [ [type, resolver-1, resolver-2], [type, resolver-1], ... ]
    public fun claim_<T>(
        publisher: &mut PublishReceipt,
        keys: vector<String>,
        resolver_strings: vector<vector<String>>,
        ctx: &mut TxContext
    ): Display<T> {
        assert!(encode::package_id<T>() == publish_receipt::into_package_id(publisher), EINVALID_PUBLISH_RECEIPT);
        assert!(!encode::has_generics<T>(), ETYPE_IS_NOT_CONCRETE);

        // Ensures that this concrete type can only ever be defined once
        let key = Key { slot: encode::module_and_struct_name<T>() };
        let uid = publish_receipt::uid_mut(publisher);
        assert!(!dynamic_field::exists_(uid, key), ETYPE_ALREADY_DEFINED);
        dynamic_field::add(uid, key, true);

        // We do not enforce any value for 'types' here. The only input-validation we do is to ensure that at
        // the first string is specified in the vector of resolver strings; the type.
        let i = 0;
        while (i < vector::length(&keys)) {
            let resolver = *vector::borrow(&resolver_strings, i);
            assert!(vector::length(&resolver) > 0, ETYPE_IN_RESOLVER_NOT_SPECIFIED);
            i = i + 1;
        };

        let resolvers = vec_map2::create(keys, resolver_strings);

        claim_internal<T>(resolvers, ctx)
    }

    // Convenience entry function
    public entry fun claim_from_abstract<T>(
        abstract: &mut AbstractDisplay,
        ctx: &mut TxContext
    ) {
        let display = claim_from_abstract_<T>(abstract, &tx_authority::begin(ctx), ctx);
        transfer(display, tx_context::sender(ctx));
    }

    // Returns a concrete type based on an abstract type, like Type<Coin<0x2::sui::SUI>> from
    // AbstractDisplay Coin<T>
    // The raw_fields supplied will be used as a Schema to define the concrete type's display, and must be the same 
    // schema specified in the abstract type's `schema_id` field
    public fun claim_from_abstract_<T>(
        abstract: &mut AbstractDisplay,
        auth: &TxAuthority,
        ctx: &mut TxContext
    ): Display<T> {
        let struct_tag = struct_tag::get<T>();
        assert!(struct_tag::is_same_abstract_type(
            &abstract_display::into_struct_tag(abstract), &struct_tag), EABSTRACT_DOES_NOT_MATCH_CONCRETE);

        // We use the existing resolvers and fields from the abstract type
        let resolvers = *abstract_display::borrow_resolvers(abstract);

        // The owner of the abstract type must authorize this action; the ownership check is done
        // within this function
        let uid = abstract_display::uid_mut(abstract, auth);

        // Ensures that this concrete type can only ever be created once
        let generics = struct_tag::generics(&struct_tag);
        let key = KeyGenerics { generics };
        assert!(!dynamic_field::exists_(uid, key), ETYPE_ALREADY_DEFINED);
        dynamic_field::add(uid, key, true);

        claim_internal<T>(resolvers, ctx)
    }

    // This is used by abstract_type as well, to define concrete types from abstract types
    fun claim_internal<T>(
        resolvers: VecMap<String, vector<String>>,
        ctx: &mut TxContext
    ): Display<T> {
        let display = Display {
            id: object::new(ctx),
            resolvers
        };

        let auth = tx_authority::begin_with_type(&Witness { });
        let typed_id = typed_id::new(&display);
        ownership::as_owned_object(&mut display.id, typed_id, &auth);

        display
    }

    // ====== Modify Resolvers ======
    // This is Display's own custom API for editing the resolvers stored on the Display object.
    
    // Combination of add and edit. If a key already exists, it will be overwritten, otherwise
    // it will be added.
    public entry fun set_resolvers<T>(
        self: &mut Display<T>,
        keys: vector<String>,
        resolver_strings: vector<vector<String>>,
    ) {
        let (i, len) = (0, vector::length(&keys));
        assert!(len == vector::length(&resolver_strings), EVEC_LENGTH_MISMATCH);

        while (i < len) {
            vec_map2::set(
                &mut self.resolvers,
                *vector::borrow(&keys, i),
                *vector::borrow(&resolver_strings, i)
            );
            i = i + 1;
        };
    }

    /// Remove keys from the Type object
    public entry fun remove_resolvers<T>(self: &mut Display<T>, keys: vector<String>) {
        let (i, len) = (0, vector::length(&keys));
        while (i < len) {
            vec_map2::remove_maybe(&mut self.resolvers, *vector::borrow(&keys, i));
            i = i + 1;
        };
    }

    // ======== Accessor Functions =====

    public fun borrow_resolvers<T>(self: &Display<T>): &VecMap<String, vector<String>> {
        &self.resolvers
    }

    public fun borrow_mut_resolvers<T>(self: &mut Display<T>): &mut VecMap<String, vector<String>> {
        &mut self.resolvers
    }

    // ======== View Functions =====

    // Display objects serve as convenient view-function fallbacks
    public fun view_with_default<T>(
        uid: &UID,
        namespace: Option<address>,
        display: &Display<T>
    ): vector<u8> {
        data::view_with_default(uid, &display.id, namespace, schema::into_keys(uid, namespace))
    }

    // ======== For Owners ========
    // Because Type lacks the `store` ability, polymorphic transfer and freeze do not work outside of this module

    public entry fun transfer<T>(self: Display<T>, new_owner: address) {
        transfer::transfer(self, new_owner);
    }

    // Makes the display immutable. This cannot be undone
    public entry fun freeze_<T>(self: Display<T>) {
        transfer::freeze_object(self);
    }

    public fun uid<T>(self: &Display<T>): &UID {
        &self.id
    }

    // `Type` is an owned object, so there's no need for an ownership check
    public fun uid_mut<T>(self: &mut Display<T>): &mut UID {
        &mut self.id
    }
}

#[test_only]
module display::type_tests {
    use std::string::{Self, String};
    use sui::test_scenario;
    use sui::transfer;
    use sui::tx_context;
    use display::display;
    use display::publish_receipt;

    use data::data;
    use data::schema;

    struct TEST_OTW has drop {}

    struct TestDisplay {}

    #[test]
    public fun test_define_type() {
        let sender = @0x123;

        let schema_fields = vector[ vector[ string::utf8(b"name"), string::utf8(b"String")], vector[ string::utf8(b"description"), string::utf8(b"Option<String>")], vector[ string::utf8(b"image"), string::utf8(b"String")], vector[ string::utf8(b"power_level"), string::utf8(b"u64")]];

        let data = vector[ vector[6, 79, 117, 116, 108, 97, 119], vector[1, 35, 84, 104, 101, 115, 101, 32, 97, 114, 101, 32, 100, 101, 109, 111, 32, 79, 117, 116, 108, 97, 119, 115, 32, 99, 114, 101, 97, 116, 101, 100, 32, 98, 121, 32, 67], vector[34, 104, 116, 116, 112, 115, 58, 47, 47, 112, 98, 115, 46, 116, 119, 105, 109, 103, 46, 99, 111, 109, 47, 112, 114, 111, 102, 105, 108, 101, 95, 105, 109, 97, 103], vector[199, 0, 0, 0, 0, 0, 0, 0] ];

        let scenario_val = test_scenario::begin(sender);
        let scenario = &mut scenario_val;
        {
            let ctx = test_scenario::ctx(scenario);
            schema::create(schema_fields, ctx);
        };

        test_scenario::next_tx(scenario, sender);
        {
            let schema = test_scenario::take_immutable<schema::Schema>(scenario);
            let ctx = test_scenario::ctx(scenario);
            let publisher = publish_receipt::test_claim(&TEST_OTW {}, ctx);

            type::define<TestDisplay>(&mut publisher, data, vector<vector<String>>[], schema_fields, ctx);

            test_scenario::return_immutable(schema);
            transfer::transfer(publisher, tx_context::sender(ctx));
        };

        test_scenario::next_tx(scenario, sender);
        {
            let type_object = test_scenario::take_from_address<type::Type<display::type_tests::TestDisplay>>(scenario, sender);

            let uid = type::extend(&mut type_object);

            let name = data::borrow<String>(uid, string::utf8(b"name"));
            assert!(*name == string::utf8(b"Outlaw"), 0);

            let power_level = data::borrow<u64>(uid, string::utf8(b"power_level"));
            assert!(*power_level == 199, 0);

            test_scenario::return_to_address(sender, type_object);
        };

        test_scenario::end(scenario_val);
    }
}