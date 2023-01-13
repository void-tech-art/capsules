module ownership::ownership {
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use sui::dynamic_field;
    use sui_utils::dynamic_field2;
    use ownership::tx_authority::{Self, TxAuthority};

    // error enums
    const ENO_MODULE_AUTHORITY: u64 = 0;
    const ENO_OWNER_AUTHORITY: u64 = 1;
    const ENO_TRANSFER_AUTHORITY: u64 = 2;
    const EUID_DOES_NOT_BELONG_TO_OBJECT: u64 = 3;
    const EOBJECT_NOT_INITIALIZED: u64 = 4;
    const EOWNERSHIP_ALREADY_INITIALIZED: u64 = 5;
    const ETRANSFER_ALREADY_EXISTS: u64 = 6;
    const EOWNER_ALREADY_EXISTS: u64 = 7;

    // Dynamic field keys
    struct Module has store, copy, drop { } // address
    struct Transfer has store, copy, drop { } // address
    struct Owner has store, copy, drop { } // address
    // The type-name the UID is nested inside of. This signifies that ownership for this UID was
    // initialized
    struct Type has store, copy, drop { } // ascii::string

    // ======= Module Authority =======

    // Convenience function
    public fun initialize<T: key>(uid: &mut UID, obj: &T, auth: &TxAuthority) {
        let module_authority = tx_authority::witness_addr<T>();
        initialize_(uid, obj, module_authority, auth);
    }

    // In this case, ownership of UID reverts to Sui root-level ownership
    public fun initialize_simple<T: key>(uid: &mut UID, obj: &T, auth: &TxAuthority) {
        initialize_(uid, obj, option::none(), auth);
    }

    // Ownership over a UID can only ever be initialized once, and it can only be done by
    // if the module that created it signed the TxAuthority
    public fun initialize_<T: key>(
        uid: &mut UID,
        obj: &T,
        module_authority: Option<address>,
        transfer_authority: Option<address>,
        owner: Option<address>,
        auth: &TxAuthority
    ) {
        assert!(object::uid_to_inner(uid) == object::id(obj), EUID_DOES_NOT_BELONG_TO_OBJECT);
        assert!(tx_authority::is_signed_by_module<T>(auth), ENO_MODULE_AUTHORITY);
        assert!(!is_initialized(uid), EOWNERSHIP_ALREADY_INITIALIZED);

        dynamic_field::add(uid, Type { }, encode::type_name<T>());

        if (option::is_some(&module_authority)) {
            dynamic_field::add(uid, Module { }, option::destroy_some(module_authority));
        };

        if (option::is_some(&transfer_authority)) {
            dynamic_field::add(uid, Transfer { }, option::destroy_some(transfer_authority));
        };

        if (option::is_some(&owner)) {
            dynamic_field::add(uid, Owner { }, option::destroy_some(owner));
        };
    }

    // Requires module and owner permission
    public fun migrate_module(uid: &mut UID, new_module_authority: address, auth: &TxAuthority) {
        assert!(is_authorized_by_module(uid, auth), ENO_MODULE_AUTHORITY);
        assert!(is_authorized_by_owner(uid, auth), ENO_OWNER_AUTHORITY);

        dynamic_field2::set(uid, Module { }, new_module_authority)
    }

    // Requires owner and transfer authority
    // Transfer authority is set to @0x1. All module permissions now default to true
    // This removes all power any module had on this object. Cannot be undone.
    public fun eject_module(uid: &mut UID, auth: &TxAuthority) {
        migrate_module(uid, @0x1, auth)
    }

    // ======= Transfer Authority =======

    // Convenience function
    public fun bind_transfer_to_type<T>(uid: &mut UID, auth: &TxAuthority) {
        let addr = tx_authority::type_into_address<T>();
        bind_transfer(uid, addr, auth);
    }

    // Convenience function
    public fun bind_transfer_to_object<T: key>(uid: &mut UID, obj: &T, auth: &TxAuthority) {
        let addr = object::id_address(obj);
        bind_transfer(uid, addr, auth);
    }

    // Requires owner and creator authority.
    public fun bind_transfer(uid: &mut UID, addr: address, auth: &TxAuthority) {
        assert!(!dynamic_field::exists_(uid, Transfer { }), ETRANSFER_ALREADY_EXISTS);
        assert!(is_authorized_by_module(uid, auth), ENO_MODULE_AUTHORITY);
        assert!(is_authorized_by_owner(uid, auth), ENO_OWNER_AUTHORITY);

        dynamic_field::add(uid, Transfer { }, addr);
    }

    // Requires owner and transfer authority
    public fun unbind_transfer(uid: &mut UID, auth: &TxAuthority) {
        assert!(is_authorized_by_transfer(uid, auth), ENO_MODULE_AUTHORITY);
        assert!(is_authorized_by_owner(uid, auth), ENO_OWNER_AUTHORITY);

        if (dynamic_field::exists_(uid, Transfer { })) {
            dynamic_field::remove<Transfer, address>(uid, Transfer { });
        }
    }

    // Requires owner and transfer authority
    public fun migrate_transfer(uid: &mut UID, new_addr: address, auth: &TxAuthority) {
        assert!(is_authorized_by_transfer(uid, auth), ENO_MODULE_AUTHORITY);
        assert!(is_authorized_by_owner(uid, auth), ENO_OWNER_AUTHORITY);

        dynamic_field2::set(uid, Transfer { }, new_addr);
    }

    // Requires owner and transfer authority
    // Transfer authority is set to @0x0. This means ownership can never be changed again
    public fun immutable_owner(uid: &mut UID, auth: &TxAuthority) {
        migrate_transfer(uid, @0x0, auth)
    }

    // ======= Owner Authority =======

    // Convenience function
    public fun bind_owner_to_type<T>(uid: &mut UID, auth: &TxAuthority) {
        let owner = tx_authority::type_into_address<T>();
        bind_owner(uid, owner, auth);
    }

    // Convenience function
    public fun bind_owner_to_object<T: key>(uid: &mut UID, obj: &T, auth: &TxAuthority) {
        let owner = object::id_address(obj);
        bind_owner(uid, owner, auth);
    }

    // Requires permission from module
    public fun bind_owner(uid: &mut UID, owner: address, auth: &TxAuthority) {
        assert!(!dynamic_field::exists_(uid, Owner { }), EOWNER_ALREADY_EXISTS);
        assert!(is_authorized_by_module(uid, auth), ENO_MODULE_AUTHORITY);

        dynamic_field::add(uid, Owner { }, owner);        
    }

    // Requires permission from transfer
    public fun unbind_owner(uid: &mut UID, auth: &TxAuthority) {
        assert!(is_authorized_by_transfer(uid, auth), ENO_MODULE_AUTHORITY);

        if (dynamic_field::exists_(uid, Owner { })) {
            dynamic_field::remove<Owner, address>(uid, Owner { });
        }       
    }

    // ========== Transfer Function =========

    // Requires transfer authority. Does NOT require ownership or creator authority.
    // This means the specified transfer authority can change ownership arbitrarily, without the current
    // owner being the sender of the transaction.
    // This is useful for marketplaces, reclaimers, and collateral-repossession
    public fun transfer(uid: &mut UID, new_owner: address, auth: &TxAuthority) {
        assert!(is_authorized_by_transfer(uid, auth), ENO_TRANSFER_AUTHORITY);

        *dynamic_field::borrow_mut<Owner, address>(uid, Owner { }) = new_owner;
    }

    // ======= Authority Checkers =======

    public fun is_initialized(uid: &UID): bool {
        dynamic_field::exists_(uid, Type { })
    }

    /// Defaults to `true` if not set.
    public fun is_authorized_by_module(uid: &UID, auth: &TxAuthority): bool {
        if (!is_initialized(uid)) false
        else if (!dynamic_field::exists_(uid, Module { })) true
        else {
            let addr = *dynamic_field::borrow<Module, address>(uid, Module { });
            tx_authority::is_signed_by(addr, auth)
        }
    }

    /// Defaults to `true` if not set.
    public fun is_authorized_by_transfer(uid: &UID, auth: &TxAuthority): bool {
        if (!is_initialized(uid)) false
        else if (!dynamic_field::exists_(uid, Transfer { })) true
        else {
            let addr = *dynamic_field::borrow<Transfer, address>(uid, Transfer { });
            tx_authority::is_signed_by(addr, auth)
        }
    }

    /// Defaults to `true` if not set.
    public fun is_authorized_by_owner(uid: &UID, auth: &TxAuthority): bool {
        if (!is_initialized(uid)) false
        else if (!dynamic_field::exists_(uid, Owner { })) true
        else {
            let addr = *dynamic_field::borrow<Owner, address>(uid, Owner { });
            tx_authority::is_signed_by(addr, auth)
        }
    }

    // ========== Getter Functions =========

    public fun type(uid: &UID): Option<String> {
        if (dynamic_field::exists_(uid, Type { })) {
            option::some(*dynamic_field::borrow<Type, String>(uid, Type { }))
        } else {
            option::none()
        }
    }

    public fun owner(uid: &UID): Option<address> {
        if (dynamic_field::exists_(uid, Owner { })) {
            option::some(*dynamic_field::borrow<Owner, address>(uid, Owner { }))
        } else {
            option::none()
        }
    }

    public fun transfer_authority(uid: &UID): Option<address> {
        if (dynamic_field::exists_(uid, Transfer { })) {
            option::some(*dynamic_field::borrow<Transfer, address>(uid, Transfer { }))
        } else {
            option::none()
        }
    }

    public fun module_authority(uid: &UID): Option<address> {
        if (dynamic_field::exists_(uid, Module { })) {
            let addr = *dynamic_field::borrow<Module, address>(uid, Module { });
            option::some(addr)
        } else {
            option::none()
        }
    }
}