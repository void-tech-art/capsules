import * as actionSet from "./action-set/structs"
import * as action from "./action/structs"
import * as destroyed from "./destroyed/structs"
import * as orgTransfer from "./org-transfer/structs"
import * as organization from "./organization/structs"
import * as ownership from "./ownership/structs"
import * as person from "./person/structs"
import * as publishReceipt from "./publish-receipt/structs"
import * as rbac from "./rbac/structs"
import * as txAuthority from "./tx-authority/structs"
import { StructClassLoader } from "../_framework/loader"

export function registerClasses(loader: StructClassLoader) {
    loader.register(destroyed.IsDestroyed)
    loader.register(action.ADMIN)
    loader.register(action.ANY)
    loader.register(action.Action)
    loader.register(action.MANAGER)
    loader.register(actionSet.ActionSet)
    loader.register(txAuthority.TxAuthority)
    loader.register(ownership.Ownership)
    loader.register(ownership.Key)
    loader.register(ownership.FREEZE)
    loader.register(ownership.Frozen)
    loader.register(ownership.INITIALIZE)
    loader.register(ownership.MIGRATE)
    loader.register(ownership.TRANSFER)
    loader.register(ownership.UID_MUT)
    loader.register(orgTransfer.OrgTransfer)
    loader.register(rbac.RBAC)
    loader.register(publishReceipt.PublishReceipt)
    loader.register(organization.Key)
    loader.register(organization.Witness)
    loader.register(organization.Package)
    loader.register(organization.ADD_PACKAGE)
    loader.register(organization.ENDORSE)
    loader.register(organization.Endorsement)
    loader.register(organization.Organization)
    loader.register(organization.REMOVE_PACKAGE)
    loader.register(person.Key)
    loader.register(person.Person)
}
