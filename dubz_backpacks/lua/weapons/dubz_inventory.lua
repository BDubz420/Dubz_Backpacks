if SERVER then
    AddCSLuaFile()
end

local config = DUBZ_INVENTORY and DUBZ_INVENTORY.Config or {}

SWEP.PrintName = "Backpack"
SWEP.Author = "Dubz"
SWEP.Instructions = "Primary: Drop backpack"
SWEP.Spawnable = false
SWEP.AdminOnly = false
SWEP.Category = config.Category or "Dubz Utilities"

SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"
SWEP.Primary.Ammo = "none"
SWEP.Secondary.Ammo = "none"
SWEP.Primary.Automatic = false
SWEP.Secondary.Automatic = false

function SWEP:Initialize()
    self:SetHoldType("normal")
end

local function dropBackpack(ply)
    if not IsValid(ply) then return end
    local bag = IsValid(ply.DubzInventoryBag) and ply.DubzInventoryBag or nil
    if not IsValid(bag) then return end

    bag:DropFromPlayer(ply)
    ply:StripWeapon("dubz_inventory")
end

function SWEP:PrimaryAttack()
    if CLIENT then return end
    dropBackpack(self:GetOwner())
end

function SWEP:OnRemove()
    if CLIENT then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if IsValid(owner.DubzInventoryBag) then
        owner.DubzInventoryBag:DropFromPlayer(owner)
    end
end

function SWEP:Deploy()
    if CLIENT then return true end
    self:SetNextPrimaryFire(CurTime() + 0.3)
    return true
end

function SWEP:SecondaryAttack()
    if CLIENT then
        net.Start("DubzInventory_RequestOpen")
        net.SendToServer()
    end
end

function SWEP:DrawHUD()
    if not IsValid(LocalPlayer().DubzInventoryBag) then return end
    draw.SimpleText("Press B to open backpack, primary fire to drop it.", "DermaDefault", ScrW() / 2, ScrH() - 50, color_white, TEXT_ALIGN_CENTER)
end
