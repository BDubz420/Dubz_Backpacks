AddCSLuaFile()

ENT = ENT or {}
ENT.Type = "anim"
ENT.Base = "base_anim"

DUBZ_INVENTORY = DUBZ_INVENTORY or {}
local config = DUBZ_INVENTORY.Config or {
    Capacity         = 10,
    Category         = "Dubz Backpacks",
    BackpackKey      = KEY_B,
    ColorBackground  = Color(0, 0, 0, 190),
    ColorPanel       = Color(24, 28, 38),
    ColorAccent      = Color(25, 178, 208),
    ColorText        = Color(230, 234, 242),
    PocketWhitelist  = {},
    Backpacks        = {
        ["dubz_inventory_bag"] = {
            PrintName    = "Dubz Backpack",
            Model        = "models/props_c17/BriefCase001a.mdl",
            Category     = "Dubz Backpacks",
            Capacity     = 20,
            AttachOffset = Vector(-5, 12, -3),
            AttachAngles = Angle(90, 0, -180),
        }
    }
}

local bagDefinitions = config.Backpacks or {}
local defaultBag = bagDefinitions["dubz_inventory_bag"] or {
    PrintName    = "Dubz Backpack",
    Model        = "models/props_c17/BriefCase001a.mdl",
    Category     = config.Category or "Dubz Backpacks",
    Capacity     = config.Capacity or 10,
    AttachOffset = Vector(-5, 12, -3),
    AttachAngles = Angle(90, 0, -180),
}

--------------------------------------------------------------------
-- SHARED INVENTORY HELPERS
--------------------------------------------------------------------
local function cleanItems(container)
    if not IsValid(container) then return {} end
    container.StoredItems = container.StoredItems or {}
    return container.StoredItems
end

function DUBZ_INVENTORY.GetItems(container)
    return cleanItems(container)
end

local function containerCapacity(container)
    if not IsValid(container) then return config.Capacity or 10 end

    if container.GetBagCapacity then
        return container:GetBagCapacity()
    end

    local bagCfg = bagDefinitions[container:GetClass()] or defaultBag
    return bagCfg.Capacity or config.Capacity or 10
end

local function subMaterialsMatch(a, b)
    if (not a) and (not b) then return true end
    if (not a) or (not b) then return false end
    if table.Count(a) ~= table.Count(b) then return false end

    for idx, mat in pairs(a) do
        if b[idx] ~= mat then
            return false
        end
    end

    return true
end

function DUBZ_INVENTORY.CanStack(a, b)
    if not (a and b) then return false end
    if a.class ~= b.class or a.model ~= b.model or a.itemType ~= b.itemType then return false end
    if a.material ~= b.material then return false end
    if not subMaterialsMatch(a.subMaterials, b.subMaterials) then return false end

    if (a.weaponClass or b.weaponClass) and a.weaponClass ~= b.weaponClass then return false end
    if a.entState or b.entState then return false end -- don't stack uniquely stored entities

    return true
end

function DUBZ_INVENTORY.AddItem(container, itemData)
    if not IsValid(container) or not itemData or not itemData.class then return false end
    local items = cleanItems(container)

    for _, data in ipairs(items) do
        if DUBZ_INVENTORY.CanStack(data, itemData) then
            data.quantity = (data.quantity or 1) + (itemData.quantity or 1)
            return true
        end
    end

    if #items >= containerCapacity(container) then return false end

    itemData.quantity = itemData.quantity or 1
    table.insert(items, itemData)
    return true
end

function DUBZ_INVENTORY.RemoveItem(container, index, amount)
    local items = cleanItems(container)
    local data  = items[index]
    if not data then return nil end

    local take = math.min(amount or 1, data.quantity or 1)
    data.quantity = (data.quantity or 1) - take

    if data.quantity <= 0 then
        table.remove(items, index)
    end

    data.quantity = take
    return data
end

function DUBZ_INVENTORY.MoveItem(fromContainer, toContainer, index, amount)
    local taken = DUBZ_INVENTORY.RemoveItem(fromContainer, index, amount)
    if not taken then return false end

    if DUBZ_INVENTORY.AddItem(toContainer, taken) then
        return true
    end

    -- put the item back if the transfer fails
    DUBZ_INVENTORY.AddItem(fromContainer, taken)
    return false
end

function DUBZ_INVENTORY.DropToWorld(ply, data)
    if not (IsValid(ply) and data and data.class) then return false end
    if not spawnWorldItem then return false end
    return spawnWorldItem(ply, data)
end

function DUBZ_INVENTORY.SendTip(ply, msg)
    if not IsValid(ply) then return end
    net.Start("DubzInventory_Tip")
    net.WriteString(msg)
    net.Send(ply)
end

--------------------------------------------------------------------
-- CAPTURE ENTITY VISUAL / DUPE STATE
--------------------------------------------------------------------
local function captureSubMaterials(ent)
    if not (IsValid(ent) and ent.GetSubMaterial) then return nil end

    local subs = {}
    local maxSub = 0

    if ent.GetNumSubMaterials then
        maxSub = ent:GetNumSubMaterials() or 0
    else
        local mats = ent:GetMaterials() or {}
        maxSub = #mats
    end

    for i = 0, maxSub do
        local sub = ent:GetSubMaterial(i)
        if sub and sub ~= "" then
            subs[i] = sub
        end
    end

    if table.IsEmpty(subs) then return nil end
    return subs
end

local function captureEntityState(ent)
    if not IsValid(ent) then return nil end

    local dupe
    if duplicator and duplicator.CopyEntTable then
        dupe = duplicator.CopyEntTable(ent)
        if dupe then
            dupe.Pos         = nil
            dupe.Angle       = nil
            dupe.EntityPos   = nil
            dupe.EntityAngle = nil
        end
    end

    local mods
    if duplicator and duplicator.CopyEntTable and ent.EntityMods then
        mods = duplicator.CopyEntTable(ent.EntityMods)
    end

    local material   = ent:GetMaterial()
    local subMats    = captureSubMaterials(ent)
    local skin       = ent:GetSkin()

    if (not dupe or table.IsEmpty(dupe))
    and (not mods or table.IsEmpty(mods))
    and (not material or material == "")
    and (not subMats)
    and (not skin or skin == 0)
    then
        return nil
    end

    return {
        dupe         = dupe,
        mods         = mods,
        skin         = skin,
        material     = material,
        subMaterials = subMats
    }
end

--------------------------------------------------------------------
-- ITEM BUILDERS
--------------------------------------------------------------------
local function buildWeaponData(ent)
    local class = ent:GetClass()
    return {
        class      = class,
        name       = ent.PrintName or class,
        model      = ent.WorldModel or ent:GetModel(),
        quantity   = 1,
        itemType   = "weapon",
        clip1      = ent.Clip1 and ent:Clip1() or 0,
        clip2      = ent.Clip2 and ent:Clip2() or 0,
        ammoType1  = ent.GetPrimaryAmmoType and ent:GetPrimaryAmmoType() or -1,
        ammoType2  = ent.GetSecondaryAmmoType and ent:GetSecondaryAmmoType() or -1
    }
end

local function buildSpawnedWeaponData(ent)
    local weaponClass = (ent.GetWeaponClass and ent:GetWeaponClass())
        or ent.weaponClass
        or ent.weaponclass
        or (ent.GetNWString and ent:GetNWString("weaponclass", ent:GetNWString("WeaponClass", "")))
        or ""

    local stored = weaponClass ~= "" and weapons.GetStored(weaponClass)
    local name   = (stored and stored.PrintName) or ent.PrintName or weaponClass or "Weapon"
    local model  = ent:GetModel() or (stored and stored.WorldModel) or "models/weapons/w_pist_deagle.mdl"

    local clip1  = ent.clip1 or (ent.GetNWInt and ent:GetNWInt("clip1")) or 0
    local clip2  = ent.clip2 or (ent.GetNWInt and ent:GetNWInt("clip2")) or 0
    local ammoAdd= ent.ammoadd or (ent.GetNWInt and ent:GetNWInt("ammoadd")) or 0

    return {
        class       = ent:GetClass(),
        weaponClass = weaponClass ~= "" and weaponClass or nil,
        name        = name,
        model       = model,
        quantity    = 1,
        itemType    = "weapon",
        clip1       = clip1,
        clip2       = clip2,
        ammoAdd     = ammoAdd
    }
end

local function buildEntityData(ent)
    local class = ent:GetClass()
    return {
        class        = class,
        name         = ent.PrintName or class,
        model        = ent:GetModel(),
        quantity     = 1,
        itemType     = "entity",
        material     = ent:GetMaterial(),
        subMaterials = captureSubMaterials(ent),
        entState     = captureEntityState(ent)
    }
end

-- unified builder for stored items
local function BuildItemData(ent)
    if not IsValid(ent) then return nil end

    local class = ent:GetClass()
    if class == "spawned_weapon" then
        local data = buildSpawnedWeaponData(ent)
        if not data.weaponClass then return nil end
        return data
    elseif ent:IsWeapon() then
        return buildWeaponData(ent)
    else
        return buildEntityData(ent)
    end
end

--------------------------------------------------------------------
-- POCKET HELPERS
--------------------------------------------------------------------
local function getPocketItems(ply)
    if ply.getPocketItems then
        local items = ply:getPocketItems()
        if items then return items end
    end

    if DarkRP and DarkRP.getPocketItems then
        local items = DarkRP.getPocketItems(ply)
        if items then return items end
    end

    return ply.darkRPPocket or {}
end

local function removePocketItem(ply, index)
    if not IsValid(ply) then return nil end

    if ply.dropPocketItem then
        return ply:dropPocketItem(index)
    end

    if DarkRP and DarkRP.retrievePocketItem then
        return DarkRP.retrievePocketItem(ply, index)
    end

    local pocket = ply.darkRPPocket
    if not pocket then return nil end

    local ent = pocket[index]
    if not ent then return nil end
    table.remove(pocket, index)
    return ent
end

local function addPocketItem(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return false end

    if ply.addPocketItem then
        return ply:addPocketItem(ent)
    end

    if DarkRP and DarkRP.storePocketItem then
        return DarkRP.storePocketItem(ply, ent)
    end

    ply.darkRPPocket = ply.darkRPPocket or {}
    table.insert(ply.darkRPPocket, ent)
    return true
end

local function pocketItemData(ply)
    local items = {}
    for idx, ent in ipairs(getPocketItems(ply)) do
        if IsValid(ent) then
            local data = BuildItemData(ent)
            if data then
                data.quantity = 1
                data.pocketIndex = idx
                table.insert(items, data)
            end
        end
    end
    return items
end

--------------------------------------------------------------------
-- NETWORKING / MENU
--------------------------------------------------------------------
if SERVER then
    util.AddNetworkString("DubzInventory_Open")
    util.AddNetworkString("DubzInventory_Action")
    util.AddNetworkString("DubzInventory_Tip")
    util.AddNetworkString("DubzInventory_RequestOpen")
    util.AddNetworkString("DubzInventory_PocketAction")
    util.AddNetworkString("DubzInventory_DropBag")
    util.AddNetworkString("DubzInventory_EquipBag")

    local function writeNetItem(data)
        net.WriteString(data.class or "")
        net.WriteString(data.name or data.class or "Unknown Item")
        net.WriteString(data.model or "")
        net.WriteUInt(math.Clamp(data.quantity or 1, 1, 65535), 16)
        net.WriteString(data.itemType or "entity")
        net.WriteString(data.material or "")

        local subMats = data.subMaterials or {}
        net.WriteUInt(math.min(table.Count(subMats), 16), 5)
        for idx, mat in pairs(subMats) do
            net.WriteUInt(idx, 5)
            net.WriteString(mat)
        end
    end

    local function verifyContainer(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return false end
        if ent:GetClass() ~= "dubz_inventory_bag" and not bagDefinitions[ent:GetClass()] then return false end

        local maxDist = 200 * 200
        if ent:GetPos():DistToSqr(ply:GetPos()) > maxDist then return false end

        return true
    end

    function DUBZ_INVENTORY.OpenFor(ply, container)
        if not verifyContainer(ply, container) then return end

        local items = cleanItems(container)
        local pocket = pocketItemData(ply)

        net.Start("DubzInventory_Open")
        net.WriteEntity(container)
        net.WriteUInt(containerCapacity(container), 8)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            writeNetItem(data)
        end

        net.WriteUInt(#pocket, 8)
        for _, data in ipairs(pocket) do
            writeNetItem(data)
            net.WriteUInt(data.pocketIndex or 0, 8)
        end
        net.Send(ply)
    end

    local function canEquipBag(ply, ent)
        if not (IsValid(ply) and ply:IsPlayer()) then return false end
        if not verifyContainer(ply, ent) then return false end

        if ent.IsCarried then
            DUBZ_INVENTORY.SendTip(ply, "Someone else is wearing this bag")
            return false
        end

        if IsValid(ply.DubzInventoryBag) then
            DUBZ_INVENTORY.SendTip(ply, "You already have a backpack equipped")
            return false
        end

        return true
    end

    local function equipBag(ply, ent)
        if not canEquipBag(ply, ent) then return end

        ent:AttachToPlayer(ply)
        ent:SetPos(ply:GetPos())
        ent:SetParent(ply)
        DUBZ_INVENTORY.SendTip(ply, "Equipped your backpack")
    end

    local function validModelPath(path)
        return path and path ~= "" and util.IsValidModel(path)
    end

    local function resolveSpawnModel(data)
        if validModelPath(data.model) then
            return data.model
        end

        if data.weaponClass then
            local stored = weapons.GetStored(data.weaponClass)
            if stored and validModelPath(stored.WorldModel) then
                return stored.WorldModel
            end
        end

        return "models/weapons/w_pist_deagle.mdl"
    end

    local function spawnWorldItem(ply, data)
        if not (IsValid(ply) and data and data.class) then return false end

        local eyePos = ply:EyePos()
        local eyeAng = ply:EyeAngles()
        util.TraceLine({
            start  = eyePos,
            endpos = eyePos + eyeAng:Forward() * 85,
            filter = ply
        })

        local right = eyeAng:Right()
        local pos = eyePos + right * 30 + eyeAng:Forward() * 15

        local ang = Angle(0, eyeAng.yaw, 0)
        local ent = ents.Create(data.class)
        if not IsValid(ent) then return false end

        if data.class == "spawned_weapon" then
            if not data.weaponClass then return false end

            if ent.SetWeaponClass then
                ent:SetWeaponClass(data.weaponClass)
            else
                ent.weaponClass = data.weaponClass
                ent.weaponclass = data.weaponClass
            end

            ent:SetNWString("weaponclass", data.weaponClass)
            ent:SetNWString("WeaponClass", data.weaponClass)
            ent:SetModel(resolveSpawnModel(data))

            ent.clip1   = data.clip1
            ent.clip2   = data.clip2
            ent.ammoadd = data.ammoAdd
            ent:SetNWInt("clip1", data.clip1 or 0)
            ent:SetNWInt("clip2", data.clip2 or 0)
            if data.ammoAdd then
                ent:SetNWInt("ammoadd", data.ammoAdd)
            end
        end

        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:Spawn()
        ent:Activate()

        if data.itemType == "weapon" and ent:IsWeapon() then
            if data.clip1 then ent:SetClip1(data.clip1) end
            if data.clip2 then ent:SetClip2(data.clip2) end
        end

        local material     = data.material or (data.entState and data.entState.material)
        local subMaterials = data.subMaterials or (data.entState and data.entState.subMaterials)

        if material and material ~= "" then
            ent:SetMaterial(material)
        end

        if subMaterials then
            for idx, mat in pairs(subMaterials) do
                ent:SetSubMaterial(idx, mat)
            end
        end

        if data.entState and data.entState.dupe and duplicator and duplicator.DoGeneric then
            duplicator.DoGeneric(ent, data.entState.dupe)
        end

        if data.entState and data.entState.skin then
            ent:SetSkin(data.entState.skin)
        end

        if data.entState and data.entState.mods and duplicator and duplicator.ApplyEntityModifier then
            for mod, info in pairs(data.entState.mods) do
                duplicator.ApplyEntityModifier(ply, ent, mod, info)
            end
        end

        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then
            ent:PhysicsInit(SOLID_VPHYSICS)
            ent:SetMoveType(MOVETYPE_VPHYSICS)
            ent:SetSolid(SOLID_VPHYSICS)
            phys = ent:GetPhysicsObject()
        end

        if IsValid(phys) then
            phys:Wake()
        end

        return IsValid(ent)
    end

    net.Receive("DubzInventory_Action", function(_, ply)
        local container = net.ReadEntity()
        local index     = net.ReadUInt(8)
        local action    = net.ReadString()
        local amount    = net.ReadUInt(16)

        if not verifyContainer(ply, container) then return end

        local items = cleanItems(container)
        local data  = items[index]
        if not data then return end

        if action == "use" then
            local removed = DUBZ_INVENTORY.RemoveItem(container, index, 1)
            if not removed then return end

            if removed.itemType == "weapon" then
                local giveClass = removed.weaponClass or removed.class
                local given = giveClass and ply:Give(giveClass)
                if IsValid(given) then
                    given.PrintName = removed.name
                    if removed.clip1 then given:SetClip1(removed.clip1) end
                    if removed.clip2 then given:SetClip2(removed.clip2) end
                    if removed.ammoType1 and removed.clip1 and removed.clip1 > 0 then
                        ply:GiveAmmo(removed.clip1, removed.ammoType1)
                    end
                    if removed.ammoType2 and removed.clip2 and removed.clip2 > 0 then
                        ply:GiveAmmo(removed.clip2, removed.ammoType2)
                    end
                    if removed.ammoAdd and given:GetPrimaryAmmoType() >= 0 then
                        ply:GiveAmmo(removed.ammoAdd, given:GetPrimaryAmmoType())
                    end
                    DUBZ_INVENTORY.SendTip(ply, "Equipped " .. removed.name)
                end
            else
                if spawnWorldItem(ply, removed) then
                    DUBZ_INVENTORY.SendTip(ply, "Spawned " .. removed.name)
                end
            end

        elseif action == "drop" then
            local removed = DUBZ_INVENTORY.RemoveItem(container, index, math.max(amount, 1))
            if not removed then return end

            local dropCount = math.max(removed.quantity or 0, 0)
            if dropCount <= 0 then return end

            removed.quantity = 1
            local spawned = 0
            for _ = 1, dropCount do
                if spawnWorldItem(ply, removed) then
                    spawned = spawned + 1
                else
                    break
                end
            end

            local remaining = dropCount - spawned
            if remaining > 0 then
                removed.quantity = remaining
                DUBZ_INVENTORY.AddItem(container, removed)
            end

            DUBZ_INVENTORY.SendTip(ply, string.format("Dropped %s", removed.name or "item"))

        elseif action == "destroy" then
            DUBZ_INVENTORY.RemoveItem(container, index, math.max(amount, 1))
            DUBZ_INVENTORY.SendTip(ply, "Destroyed item")

        elseif action == "split" then
            local dataRef = items[index]
            if dataRef and (dataRef.quantity or 1) > 1 then
                local half = math.floor(dataRef.quantity / 2)
                dataRef.quantity = dataRef.quantity - half
                DUBZ_INVENTORY.AddItem(container, {
                    class        = dataRef.class,
                    name         = dataRef.name,
                    model        = dataRef.model,
                    quantity     = half,
                    itemType     = dataRef.itemType,
                    material     = dataRef.material,
                    subMaterials = dataRef.subMaterials
                })
                DUBZ_INVENTORY.SendTip(ply, "Split stack")
            end
        end

        DUBZ_INVENTORY.OpenFor(ply, container)
    end)

    net.Receive("DubzInventory_PocketAction", function(_, ply)
        local container = net.ReadEntity()
        local action    = net.ReadString()
        local pocketIdx = net.ReadUInt(8)

        if action == "pocket_to_bag" then
            if not verifyContainer(ply, container) then return end

            local ent = removePocketItem(ply, pocketIdx)
            if not IsValid(ent) then return end

            local item = BuildItemData(ent)
            if not item then return end

            if not DUBZ_INVENTORY.AddItem(container, item) then
                addPocketItem(ply, ent)
                DUBZ_INVENTORY.SendTip(ply, "Backpack is full")
                return
            end

            ent:Remove()
            DUBZ_INVENTORY.SendTip(ply, "Moved item to backpack")
            DUBZ_INVENTORY.OpenFor(ply, container)

        elseif action == "drop_pocket" then
            local ent = removePocketItem(ply, pocketIdx)
            if not IsValid(ent) then return end

            local eyePos = ply:EyePos()
            local eyeAng = ply:EyeAngles()
            local pos = eyePos + eyeAng:Forward() * 40
            ent:SetPos(pos)
            ent:SetAngles(Angle(0, eyeAng.yaw, 0))
            ent:SetParent(nil)
            ent:SetMoveType(MOVETYPE_VPHYSICS)
            ent:SetSolid(SOLID_VPHYSICS)
            ent:Spawn()
            ent:Activate()

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(ply:GetAimVector() * 120)
                phys:Wake()
            end

            DUBZ_INVENTORY.SendTip(ply, "Dropped pocket item")
        end
    end)

    net.Receive("DubzInventory_RequestOpen", function(_, ply)
        local bag = IsValid(ply.DubzInventoryBag) and ply.DubzInventoryBag or nil
        if not IsValid(bag) then
            DUBZ_INVENTORY.SendTip(ply, "You don't have a backpack equipped")
            return
        end

        DUBZ_INVENTORY.OpenFor(ply, bag)
    end)

    net.Receive("DubzInventory_DropBag", function(_, ply)
        local bag = net.ReadEntity()
        if not verifyContainer(ply, bag) then return end
        if bag.BagOwner ~= ply then return end

        bag:DropFromPlayer(ply)
    end)

    net.Receive("DubzInventory_EquipBag", function(_, ply)
        local ent = net.ReadEntity()
        equipBag(ply, ent)
    end)

    hook.Add("KeyPress", "DubzInventory_RClickPickup", function(ply, key)
        if key ~= IN_ATTACK2 then return end
        if IsValid(ply.DubzInventoryBag) then return end

        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        if not verifyContainer(ply, ent) then return end
        if tr.HitPos:DistToSqr(ply:EyePos()) > 22500 then return end

        equipBag(ply, ent)
    end)
end

--------------------------------------------------------------------
-- ENTITY INSTANCE (SERVER)
--------------------------------------------------------------------
local BaseBag = {}
BaseBag.Type        = "anim"
BaseBag.Base        = "base_anim"
BaseBag.PrintName   = defaultBag.PrintName
BaseBag.Category    = defaultBag.Category or config.Category or "Dubz Backpacks"
BaseBag.Spawnable   = true
BaseBag.RenderGroup = RENDERGROUP_OPAQUE
BaseBag.BagConfig   = defaultBag

function BaseBag:GetBagConfig()
    return bagDefinitions[self:GetClass()] or self.BagConfig or defaultBag
end

function BaseBag:GetBagCapacity()
    local cfg = self:GetBagConfig()
    return cfg.Capacity or config.Capacity or 10
end

function BaseBag:GetBagOffsets()
    local cfg = self:GetBagConfig()
    return cfg.AttachOffset or Vector(-5, 12, -3), cfg.AttachAngles or Angle(90, 0, -180)
end

function BaseBag:GetBagModel()
    local cfg = self:GetBagConfig()
    return cfg.Model or defaultBag.Model
end

function BaseBag:Initialize()
    if CLIENT then return end

    self:SetModel(self:GetBagModel())
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetUseType(SIMPLE_USE)

    self.StoredItems   = self.StoredItems or {}
    self.IsCarried     = false
    self.BagOwner      = nil

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

function BaseBag:AttachToPlayer(ply)
    if not IsValid(ply) then return end

    self.IsCarried = true
    self.BagOwner  = ply
    ply.DubzInventoryBag = self
    if ply.SetNWEntity then
        ply:SetNWEntity("DubzInventoryBag", self)
    end
    if self.SetNWEntity then
        self:SetNWEntity("DubzBagOwner", ply)
    end

    self:SetNoDraw(false)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetParent(ply)

    local bone = ply:LookupBone("ValveBiped.Bip01_Spine2")
    if bone then
        self:FollowBone(ply, bone)
    end

    self.BasePos, self.BaseAng = self:GetBagOffsets()
end

function BaseBag:DropFromPlayer(ply)
    if not IsValid(self) then return end

    self.IsCarried = false
    self.BagOwner  = nil

    if IsValid(ply) then
        ply.DubzInventoryBag = nil
        if ply.SetNWEntity then
            ply:SetNWEntity("DubzInventoryBag", NULL)
        end
    end

    if self.SetNWEntity then
        self:SetNWEntity("DubzBagOwner", NULL)
    end

    self:SetParent(nil)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetNoDraw(false)

    if IsValid(ply) and ply:IsPlayer() then
        local eyePos = ply:EyePos()
        local eyeAng = ply:EyeAngles()
        local tr = util.TraceLine({
            start  = eyePos,
            endpos = eyePos + eyeAng:Forward() * 85,
            filter = ply
        })

        local pos = tr.HitPos + tr.HitNormal * 8
        if not tr.Hit then
            pos = eyePos + eyeAng:Forward() * 30
        end

        self:SetPos(pos)
        self:SetAngles(Angle(0, eyeAng.yaw, 0))

        self.NextPickupAllowed = CurTime() + 0.3
    end

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

-----------------------------------------------------
--  E KEY = OPEN MENU (ONLY WHEN BAG ON GROUND)
-----------------------------------------------------
function BaseBag:Use(activator)
    if CLIENT then return end
    if not (IsValid(activator) and activator:IsPlayer()) then return end

    if self.IsCarried then
        if self.BagOwner ~= activator then
            DUBZ_INVENTORY.SendTip(activator, "Someone else is wearing this bag")
        end
        return
    end

    DUBZ_INVENTORY.OpenFor(activator, self)
end

-----------------------------------------------------
--  AUTO-LOOT (Money Pot style) + Drop Cooldown
-----------------------------------------------------
function BaseBag:StartTouch(ent)
    if CLIENT then return end
    if not IsValid(ent) then return end
    if ent == self then return end

    -- Do not pick up players or NPCs ever
    if ent:IsPlayer() or ent:IsNPC() then return end

    -- Cooldown to prevent instantly re-picking dropped items
    if CurTime() < (self.NextPickupAllowed or 0) then return end

    -- Respect DarkRP pocket blacklist exactly like money pot
    local blacklist = DarkRP.getPocketBlacklist and DarkRP.getPocketBlacklist() or {}
    if blacklist[ent:GetClass()] then
        local owner = IsValid(self.BagOwner) and self.BagOwner or nil
        if owner and DarkRP and DarkRP.notify then
            DarkRP.notify(owner, 1, 4, "This item cannot be stored.")
        end
        return
    end

    -- Build correct item data (weapons, props, entities)
    local item = BuildItemData(ent)
    if not item then return end

    -- Respect stacking + capacity
    if not DUBZ_INVENTORY.AddItem(self, item) then
        local owner = IsValid(self.BagOwner) and self.BagOwner or nil
        if owner then
            DUBZ_INVENTORY.SendTip(owner, "Backpack is full")
        end
        return
    end

    -- Remove the world entity and store it
    ent:Remove()

    -- Feedback
    local owner = IsValid(self.BagOwner) and self.BagOwner or nil
    if owner then
        DUBZ_INVENTORY.SendTip(owner, "Stored " .. (item.name or item.class) .. " in backpack")
    end
end

--------------------------------------------------------------------
-- CLIENT: SWAY / POSITION UPDATES
--------------------------------------------------------------------
if CLIENT then
    function BaseBag:Think()
        local ply = self.BagOwner
        if not IsValid(ply) or not self.BasePos or not self.BaseAng then return end

        self.SwayVel    = self.SwayVel or Angle(0, 0, 0)
        self.SwayOffset = self.SwayOffset or Angle(0, 0, 0)

        local vel = ply:GetVelocity():Length()

        local target = Angle(
            math.Clamp(vel * 0.018, 0, 4),
            0,
            math.Clamp(vel * 0.012, 0, 3)
        )

        self.SwayVel    = LerpAngle(FrameTime() * 8, self.SwayVel, target)
        self.SwayOffset = LerpAngle(FrameTime() * 6, self.SwayOffset, self.SwayVel)

        local bone = ply:LookupBone("ValveBiped.Bip01_Spine2")
        if bone then
            local ang = self.BaseAng + self.SwayOffset
            self:SetLocalPos(self.BasePos)
            self:SetLocalAngles(ang)
        end

        self:SetNextClientThink(CurTime())
        return true
    end
end

--------------------------------------------------------------------
-- REGISTRATION
--------------------------------------------------------------------
ENT = table.Copy(BaseBag)
ENT.PrintName = defaultBag.PrintName
ENT.Category  = defaultBag.Category or config.Category or "Dubz Backpacks"
ENT.BagConfig = defaultBag

for className, cfg in pairs(bagDefinitions) do
    if className ~= "dubz_inventory_bag" then
        local newEnt = table.Copy(BaseBag)
        newEnt.PrintName = cfg.PrintName or defaultBag.PrintName
        newEnt.Category  = cfg.Category or defaultBag.Category
        newEnt.BagConfig = cfg
        scripted_ents.Register(newEnt, className)
    end
end

--------------------------------------------------------------------
-- CLIENT UI / INPUT
--------------------------------------------------------------------
if CLIENT then
    local function readNetItem()
        local item = {}
        item.class   = net.ReadString()
        item.name    = net.ReadString()
        item.model   = net.ReadString()
        item.quantity= net.ReadUInt(16)
        item.itemType= net.ReadString()
        item.material= net.ReadString()

        local subCount = net.ReadUInt(5)
        item.subMaterials = {}
        for _ = 1, subCount do
            local idx = net.ReadUInt(5)
            local mat = net.ReadString()
            item.subMaterials[idx] = mat
        end

        return item
    end

    local function buildItemPanel(list, item, opts)
        opts = opts or {}

        local panel = list:Add("DPanel")
        panel:SetTall(64)
        panel:Dock(TOP)
        panel:DockMargin(0, 0, 0, 6)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, config.ColorPanel)
        end

        local icon = vgui.Create("DModelPanel", panel)
        icon:SetModel(item.model)
        icon:SetSize(64, 64)
        icon:Dock(LEFT)
        icon:SetFOV(20)
        icon:SetCamPos(Vector(50, 50, 50))
        icon:SetLookAt(Vector(0, 0, 0))
        icon.LayoutEntity = function() return end

        if item.material and item.material ~= "" then
            icon:SetMaterial(item.material)
        end

        if item.subMaterials then
            for idx, mat in pairs(item.subMaterials) do
                icon:SetSubMaterial(idx, mat)
            end
        end

        local label = vgui.Create("DLabel", panel)
        label:Dock(FILL)
        label:DockMargin(8, 8, 8, 8)
        label:SetTextColor(config.ColorText)
        label:SetWrap(true)
        label:SetText(string.format("%s x%s", item.name, item.quantity or 1))

        panel.ItemData = item
        panel.DragName = opts.dragName or ""
        if panel.DragName ~= "" then
            panel:Droppable(panel.DragName)
        end

        return panel
    end

    local function promptAmount(maxAmount, callback)
        Derma_StringRequest("Drop Quantity", "How many would you like to drop?", tostring(maxAmount), function(text)
            local num = tonumber(text) or 0
            num = math.Clamp(math.floor(num), 1, maxAmount)
            callback(num)
        end)
    end

    local function openMenu(container, capacity, items, pocketItems)
        if not IsValid(container) then return end

        local frame = vgui.Create("DFrame")
        frame:SetSize(640, 540)
        frame:Center()
        frame:SetTitle("Backpack & Pocket")
        frame:MakePopup()

        local top = vgui.Create("DPanel", frame)
        top:Dock(TOP)
        top:SetTall(28)
        top.Paint = function(self, w, h)
            draw.RoundedBox(0, 0, 0, w, h, config.ColorBackground)
        end

        local info = vgui.Create("DLabel", top)
        info:Dock(LEFT)
        info:SetTextColor(config.ColorText)
        info:SetText(string.format("Backpack capacity: %d / %d", #items, capacity))
        info:DockMargin(8, 6, 0, 0)

        local dropButton = vgui.Create("DButton", top)
        dropButton:Dock(RIGHT)
        dropButton:SetText("Drop Backpack")
        dropButton:SetWide(120)
        dropButton:DockMargin(0, 4, 8, 4)
        local owner = IsValid(container) and container:GetNWEntity("DubzBagOwner")
        dropButton:SetVisible(IsValid(owner) and owner == LocalPlayer())
        dropButton.DoClick = function()
            net.Start("DubzInventory_DropBag")
            net.WriteEntity(container)
            net.SendToServer()
            frame:Close()
        end

        local containerPanel = vgui.Create("DPanel", frame)
        containerPanel:Dock(FILL)
        containerPanel:DockPadding(8, 8, 8, 8)
        containerPanel.Paint = function(self, w, h)
            draw.RoundedBox(0, 0, 0, w, h, config.ColorBackground)
        end

        local pocketList = vgui.Create("DScrollPanel", containerPanel)
        pocketList:Dock(LEFT)
        pocketList:SetWide(300)
        pocketList:DockMargin(0, 0, 4, 0)

        local bagList = vgui.Create("DScrollPanel", containerPanel)
        bagList:Dock(FILL)

        local dropZone = vgui.Create("DPanel", containerPanel)
        dropZone:Dock(BOTTOM)
        dropZone:SetTall(60)
        dropZone:DockMargin(0, 8, 0, 0)
        dropZone.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, config.ColorPanel)
            draw.SimpleText("Drag here to drop items", "DermaDefaultBold", w / 2, h / 2, config.ColorText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        bagList:Receiver("DubzPocketItem", function(_, panels, drop)
            if not drop then return end
            local item = panels[1].ItemData
            if not item then return end

            net.Start("DubzInventory_PocketAction")
            net.WriteEntity(container)
            net.WriteString("pocket_to_bag")
            net.WriteUInt(item.pocketIndex or 0, 8)
            net.SendToServer()
        end)

        dropZone:Receiver("DubzPocketItem", function(_, panels, drop)
            if not drop then return end
            local item = panels[1].ItemData
            if not item then return end

            net.Start("DubzInventory_PocketAction")
            net.WriteEntity(container)
            net.WriteString("drop_pocket")
            net.WriteUInt(item.pocketIndex or 0, 8)
            net.SendToServer()
        end)

        dropZone:Receiver("DubzBagItem", function(_, panels, drop)
            if not drop then return end
            local item = panels[1].ItemData
            if not item then return end
            local maxAmount = item.quantity or 1
            promptAmount(maxAmount, function(amount)
                net.Start("DubzInventory_Action")
                net.WriteEntity(container)
                net.WriteUInt(item.index or 0, 8)
                net.WriteString("drop")
                net.WriteUInt(amount, 16)
                net.SendToServer()
            end)
        end)

        for _, data in ipairs(pocketItems) do
            local panel = buildItemPanel(pocketList, data, { dragName = "DubzPocketItem" })
            panel.DoClick = function()
                net.Start("DubzInventory_PocketAction")
                net.WriteEntity(container)
                net.WriteString("drop_pocket")
                net.WriteUInt(data.pocketIndex or 0, 8)
                net.SendToServer()
            end
        end

        for idx, data in ipairs(items) do
            data.index = idx
            local panel = buildItemPanel(bagList, data, { dragName = "DubzBagItem" })
            panel.DoClick = function()
                net.Start("DubzInventory_Action")
                net.WriteEntity(container)
                net.WriteUInt(idx, 8)
                net.WriteString("use")
                net.WriteUInt(1, 16)
                net.SendToServer()
            end
        end
    end

    net.Receive("DubzInventory_Open", function()
        local container = net.ReadEntity()
        local capacity  = net.ReadUInt(8)
        local count     = net.ReadUInt(8)
        local items     = {}
        for _ = 1, count do
            table.insert(items, readNetItem())
        end

        local pocketCount = net.ReadUInt(8)
        local pocketItems = {}
        for _ = 1, pocketCount do
            local item = readNetItem()
            item.pocketIndex = net.ReadUInt(8)
            table.insert(pocketItems, item)
        end

        openMenu(container, capacity, items, pocketItems)
    end)

    net.Receive("DubzInventory_Tip", function()
        local msg = net.ReadString()
        notification.AddLegacy(msg, NOTIFY_GENERIC, 3)
        surface.PlaySound("buttons/button15.wav")
    end)

    local holdStart, holdTriggered

    local function getEquippedBag()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        return ply:GetNWEntity("DubzInventoryBag")
    end

    hook.Add("PlayerButtonDown", "DubzInventory_OpenKey", function(ply, button)
        if ply ~= LocalPlayer() then return end
        if button ~= (config.BackpackKey or KEY_B) then return end

        holdStart = CurTime()
        holdTriggered = false
    end)

    hook.Add("PlayerButtonUp", "DubzInventory_OpenKey", function(ply, button)
        if ply ~= LocalPlayer() then return end
        if button ~= (config.BackpackKey or KEY_B) then return end

        if holdTriggered then
            holdStart = nil
            return
        end

        if not IsValid(getEquippedBag()) then
            notification.AddLegacy("You don't have a backpack equipped", NOTIFY_GENERIC, 3)
            holdStart = nil
            return
        end

        net.Start("DubzInventory_RequestOpen")
        net.SendToServer()
        holdStart = nil
    end)

    hook.Add("Think", "DubzInventory_BackpackHold", function()
        if not holdStart then return end
        if not input.IsKeyDown(config.BackpackKey or KEY_B) then
            holdStart = nil
            return
        end

        local bag = getEquippedBag()
        if not IsValid(bag) then
            holdStart = nil
            return
        end

        if not holdTriggered and CurTime() - holdStart >= 3 then
            holdTriggered = true
            net.Start("DubzInventory_DropBag")
            net.WriteEntity(bag)
            net.SendToServer()
            holdStart = nil
        end
    end)

    hook.Add("HUDPaint", "DubzInventory_BackpackHoldHUD", function()
        if not holdStart then return end
        local bag = getEquippedBag()
        if not IsValid(bag) then return end

        local elapsed = CurTime() - holdStart
        local frac = math.Clamp(elapsed / 3, 0, 1)

        local w, h = 220, 18
        local x, y = ScrW() / 2 - w / 2, ScrH() * 0.8

        draw.RoundedBox(4, x, y, w, h, config.ColorBackground)
        draw.RoundedBox(4, x + 2, y + 2, (w - 4) * frac, h - 4, config.ColorAccent)
        draw.SimpleText("Hold to drop backpack", "DermaDefault", x + w / 2, y + h / 2, config.ColorText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)
end

--------------------------------------------------------------------
-- SERVER CLEANUP HOOKS
--------------------------------------------------------------------
if SERVER then
    hook.Add("PlayerDisconnected", "DubzInventory_Cleanup", function(ply)
        if not IsValid(ply.DubzInventoryBag) then return end
        ply.DubzInventoryBag:DropFromPlayer(ply)
    end)

    hook.Add("PlayerDeath", "DubzInventory_DropOnDeath", function(ply)
        if not IsValid(ply.DubzInventoryBag) then return end
        ply.DubzInventoryBag:DropFromPlayer(ply)
    end)
end
