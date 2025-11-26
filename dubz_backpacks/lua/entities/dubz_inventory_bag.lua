AddCSLuaFile()

ENT.Type        = "anim"
ENT.Base        = "base_anim"
ENT.PrintName   = "Dubz Backpack"
ENT.Category    = "Dubz Entities"
ENT.Spawnable   = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

local BAG_MODEL = "models/props_c17/BriefCase001a.mdl"

DUBZ_INVENTORY = DUBZ_INVENTORY or {}

local config = DUBZ_INVENTORY.Config or {
    Capacity         = 10,
    ColorBackground  = Color(0, 0, 0, 190),
    ColorPanel       = Color(24, 28, 38),
    ColorAccent      = Color(25, 178, 208),
    ColorText        = Color(230, 234, 242),
    PocketWhitelist  = {}
}

--------------------------------------------------------------------
-- SHARED INVENTORY HELPERS
--------------------------------------------------------------------
local function cleanItems(container)
    if not IsValid(container) then return {} end
    container.StoredItems = container.StoredItems or {}
    return container.StoredItems
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

    if #items >= config.Capacity then return false end

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
-- NETWORKING / MENU
--------------------------------------------------------------------
if SERVER then
    util.AddNetworkString("DubzInventory_Open")
    util.AddNetworkString("DubzInventory_Action")
    util.AddNetworkString("DubzInventory_Tip")

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
        if ent:GetClass() ~= "dubz_inventory_bag" then return false end

        local maxDist = 200 * 200
        if ent:GetPos():DistToSqr(ply:GetPos()) > maxDist then return false end

        return true
    end

    function DUBZ_INVENTORY.OpenFor(ply, container)
        if not verifyContainer(ply, container) then return end

        local items = cleanItems(container)

        net.Start("DubzInventory_Open")
        net.WriteEntity(container)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            writeNetItem(data)
        end
        net.Send(ply)
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
        local tr = util.TraceLine({
            start  = eyePos,
            endpos = eyePos + eyeAng:Forward() * 85,
            filter = ply
        })

        -- Offset to the player's right side
        local right = eyeAng:Right()
        pos = eyePos + right * 30 + eyeAng:Forward() * 15

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
end

--------------------------------------------------------------------
-- ENTITY INSTANCE (SERVER)
--------------------------------------------------------------------
function ENT:Initialize()
    if CLIENT then return end

    self:SetModel(BAG_MODEL)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    self.StoredItems   = self.StoredItems or {}
    self.IsCarried     = false
    self.BagOwner      = nil

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

function ENT:AttachToPlayer(ply)
    if not IsValid(ply) then return end

    self.IsCarried = true
    self.BagOwner  = ply

    self:SetNoDraw(true) -- the visible model is clientside
    self:SetParent(ply)

    local bone = ply:LookupBone("ValveBiped.Bip01_Spine2")
    if bone then
        self:FollowBone(ply, bone)
    end

    self.BasePos = Vector(-5, 12, -3)
    self.BaseAng = Angle(90, 0, -180)
end

function ENT:DropFromPlayer(ply)
    if not IsValid(self) then return end

    self.IsCarried = false
    self.BagOwner  = nil

    self:SetParent(nil)
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
function ENT:Use(activator)
    if CLIENT then return end
    if not (IsValid(activator) and activator:IsPlayer()) then return end
    if self.IsCarried then return end

    if DUBZ_INVENTORY and DUBZ_INVENTORY.OpenFor then
        DUBZ_INVENTORY.OpenFor(activator, self)
    end
end

-----------------------------------------------------
--  THINK LOOP — DETECT RIGHT-CLICK FOR PICKUP
-----------------------------------------------------
local lastRMB = {}

function ENT:Think()
    if CLIENT then return end
    if self.IsCarried then return end

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end

        local tr = ply:GetEyeTrace()
        if tr.Entity ~= self then continue end
        if tr.HitPos:DistToSqr(ply:GetShootPos()) > (110 * 110) then continue end

        local isRMB  = ply:KeyDown(IN_ATTACK2)
        local wasRMB = lastRMB[ply] or false

        -- Don't pickup if player is using physgun or gravity gun (so they can move it)
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) then
            local class = wep:GetClass()
            if class == "weapon_physgun" or class == "weapon_physcannon" then
                lastRMB[ply] = isRMB
                continue
            end
        end

        -- Normal pickup behavior
        if isRMB and not wasRMB then
            self:PickupBag(ply)
        end

        lastRMB[ply] = isRMB
    end

    self:NextThink(CurTime())
    return true
end

-----------------------------------------------------
--  RIGHT CLICK PICKUP → GIVE SWEP, ATTACH BAG
-----------------------------------------------------
function ENT:PickupBag(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if self.IsCarried then return end

    if ply:HasWeapon("dubz_inventory") then
        DUBZ_INVENTORY.SendTip(ply, "Drop your current backpack first")
        return
    end

    ply:Give("dubz_inventory")
    self:AttachToPlayer(ply)
    self:SetPos(ply:GetPos())
    self:SetParent(ply)

    if DUBZ_INVENTORY.SendTip then
        DUBZ_INVENTORY.SendTip(ply, "Picked up your backpack")
    end
end

-----------------------------------------------------
--  AUTO-LOOT (Money Pot style) + Drop Cooldown
-----------------------------------------------------
function ENT:StartTouch(ent)
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
    function ENT:Think()
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
