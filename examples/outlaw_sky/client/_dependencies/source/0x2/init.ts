import * as bag from "./bag/structs"
import * as balance from "./balance/structs"
import * as bcs from "./bcs/structs"
import * as borrow from "./borrow/structs"
import * as clock from "./clock/structs"
import * as coin from "./coin/structs"
import * as display from "./display/structs"
import * as dynamicField from "./dynamic-field/structs"
import * as dynamicObjectField from "./dynamic-object-field/structs"
import * as groth16 from "./groth16/structs"
import * as kiosk from "./kiosk/structs"
import * as linkedTable from "./linked-table/structs"
import * as objectBag from "./object-bag/structs"
import * as objectTable from "./object-table/structs"
import * as object from "./object/structs"
import * as package_ from "./package/structs"
import * as priorityQueue from "./priority-queue/structs"
import * as sui from "./sui/structs"
import * as tableVec from "./table-vec/structs"
import * as table from "./table/structs"
import * as transferPolicy from "./transfer-policy/structs"
import * as txContext from "./tx-context/structs"
import * as url from "./url/structs"
import * as vecMap from "./vec-map/structs"
import * as vecSet from "./vec-set/structs"
import * as versioned from "./versioned/structs"
import { StructClassLoader } from "../../../_framework/loader"

export function registerClasses(loader: StructClassLoader) {
    loader.register(txContext.TxContext)
    loader.register(object.DynamicFields)
    loader.register(object.ID)
    loader.register(object.Ownership)
    loader.register(object.UID)
    loader.register(dynamicField.Field)
    loader.register(bag.Bag)
    loader.register(balance.Balance)
    loader.register(balance.Supply)
    loader.register(bcs.BCS)
    loader.register(borrow.Borrow)
    loader.register(borrow.Referent)
    loader.register(clock.Clock)
    loader.register(url.Url)
    loader.register(coin.Coin)
    loader.register(coin.CoinMetadata)
    loader.register(coin.CurrencyCreated)
    loader.register(coin.TreasuryCap)
    loader.register(vecMap.Entry)
    loader.register(vecMap.VecMap)
    loader.register(package_.Publisher)
    loader.register(package_.UpgradeCap)
    loader.register(package_.UpgradeReceipt)
    loader.register(package_.UpgradeTicket)
    loader.register(display.Display)
    loader.register(display.DisplayCreated)
    loader.register(display.VersionUpdated)
    loader.register(dynamicObjectField.Wrapper)
    loader.register(groth16.Curve)
    loader.register(groth16.PreparedVerifyingKey)
    loader.register(groth16.ProofPoints)
    loader.register(groth16.PublicProofInputs)
    loader.register(vecSet.VecSet)
    loader.register(sui.SUI)
    loader.register(transferPolicy.RuleKey)
    loader.register(transferPolicy.TransferPolicy)
    loader.register(transferPolicy.TransferPolicyCap)
    loader.register(transferPolicy.TransferPolicyCreated)
    loader.register(transferPolicy.TransferRequest)
    loader.register(kiosk.Borrow)
    loader.register(kiosk.Item)
    loader.register(kiosk.ItemDelisted)
    loader.register(kiosk.ItemListed)
    loader.register(kiosk.ItemPurchased)
    loader.register(kiosk.Kiosk)
    loader.register(kiosk.KioskOwnerCap)
    loader.register(kiosk.Listing)
    loader.register(kiosk.Lock)
    loader.register(kiosk.PurchaseCap)
    loader.register(linkedTable.LinkedTable)
    loader.register(linkedTable.Node)
    loader.register(objectBag.ObjectBag)
    loader.register(objectTable.ObjectTable)
    loader.register(priorityQueue.Entry)
    loader.register(priorityQueue.PriorityQueue)
    loader.register(table.Table)
    loader.register(tableVec.TableVec)
    loader.register(versioned.VersionChangeCap)
    loader.register(versioned.Versioned)
}
