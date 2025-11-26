DUBZ_INVENTORY = DUBZ_INVENTORY or {}

DUBZ_INVENTORY.Config = {
    Capacity = 10,
    Category = "Dubz Backpacks",
    BackpackKey = KEY_B,
    ColorBackground = Color(0, 0, 0, 190),
    ColorPanel = Color(24, 28, 38),
    ColorAccent = Color(25, 178, 208),
    ColorText = Color(230, 234, 242),
    Backpacks = {
        ["dubz_inventory_bag"] = {
            PrintName     = "Dubz Backpack",
            Model         = "models/props_c17/BriefCase001a.mdl",
            Category      = "Dubz Backpacks",
            Capacity      = 20,
            AttachOffset  = Vector(-5, 12, -3),
            AttachAngles  = Angle(90, 0, -180),
        }
    },
    -- Optional: if you want to restrict what non-weapon entities can be stored,
    -- add them to PocketWhitelist. DarkRP's pocket blacklist is always honored
    -- and will block anything defined there.
    PocketWhitelist = {}
}

