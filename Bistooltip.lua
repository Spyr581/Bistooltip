local eventFrame = CreateFrame("Frame", nil, UIParent)
Bistooltip_phases_string = ""

local Bistooltip_LastItemId = nil
local Bistooltip_LastLink = nil

local function specHighlighted(class_name, spec_name)
    return (BistooltipAddon.db.char.highlight_spec.spec_name == spec_name and
               BistooltipAddon.db.char.highlight_spec.class_name == class_name)
end

local function specFiltered(class_name, spec_name)
    if specHighlighted(class_name, spec_name) then return false end
    if IsAltKeyDown() then return false end
    if BistooltipAddon.db.char.filter_specs[class_name] then
        return not BistooltipAddon.db.char.filter_specs[class_name][spec_name]
    end
    return false
end

local function classNamesFiltered()
    if BistooltipAddon.db.char.filter_class_names then return true end
end

local function getFilteredItem(item)
    local filtered_item = {}
    for ki, spec in ipairs(item) do
        local class_name = spec.class_name
        local spec_name = spec.spec_name
        if (not specFiltered(class_name, spec_name)) then
            table.insert(filtered_item, spec)
        end
    end
    return filtered_item
end

local function printSpecLine(tooltip, slot, class_name, spec_name)
    local slot_name = slot.name
    local slot_ranks = slot.ranks
    local prefix = "   "
    if BistooltipAddon.db.char.filter_class_names then prefix = "" end
    local left_text = prefix .. "|T" .. Bistooltip_spec_icons[class_name][spec_name] .. ":14|t " .. spec_name
    if (slot_name == "Off hand" or slot_name == "Weapon" or slot_name == "Weapon 1h" or slot_name == "Weapon 2h") then
        left_text = left_text .. " (" .. slot_name .. ")"
    end
    tooltip:AddDoubleLine(left_text, slot_ranks, 1, 0.8, 0)
end

local function printClassName(tooltip, class_name)
    tooltip:AddLine(class_name, 1, 0.8, 0)
end

function searchIDInBislistsClassSpec(structure, phases, id, class, spec)
    local paths = {}
    local seen = {}
    local sortedPhases = {}
    for _, phase in ipairs(phases) do
        if structure[class] and structure[class][spec] and structure[class][spec][phase] then
            table.insert(sortedPhases, phase)
        end
    end
    for _, phase in ipairs(sortedPhases) do
        local items = structure[class][spec][phase]
        for index, itemData in pairs(items) do
            if type(itemData) == "table" and itemData[1] then
                for i, itemId in ipairs(itemData) do
                    if i ~= "slot_name" and i ~= "enhs" and itemId == id then
                        local phaseLabel
                        if i == 1 then phaseLabel = phase .. " BIS"
                        else phaseLabel = phase .. " alt " .. i end
                        if not seen[phaseLabel] then
                            table.insert(paths, phaseLabel)
                            seen[phaseLabel] = true
                        end
                    end
                end
            end
        end
    end
    if #paths > 0 then return table.concat(paths, " / ") else return nil end
end

local function caseInsensitivePairs(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end)
    local i = 0
    return function() i = i + 1; local k = keys[i]; if k then return k, t[k] end end
end

local function getStringLength(str)
    return string.len(string.gsub(str, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then return true end
    end
    return false
end

local DataStore_Inventory = DataStore_Inventory or nil

local function GetItemSource(itemId)
    local source
    local function formatInstanceName(instance)
        local tmpInstance = string.lower(instance)
        if tmpInstance == "the obsidian sanctum (heroic)" then instance = "The Obsidian Sanctum(25)"
        elseif tmpInstance == "the eye of eternity (heroic)" then instance = "The Eye Of Eternity (25)"
        elseif tmpInstance == "naxxramas (heroic)" then instance = "Naxxramas (25)"
        elseif tmpInstance == "ulduar (heroic)" then instance = "Ulduar (25)" end
        return instance
    end
    for zone, bosses in pairs(lootTable) do
        for boss, items in pairs(bosses) do
            if table.contains(items, itemId) then
                local formattedZone = formatInstanceName(zone)
                source = "|cFFFFFFFFSource:|r |cFF00FF00[" .. formattedZone .. "] - " .. boss .. "|r"
                break
            end
        end
        if source then break end
    end
    if not source then
        local Instance, Boss = DataStore_Inventory:GetSource(itemId)
        if Instance and Boss then
            local formattedInstance = formatInstanceName(Instance)
            source = "|cFFFFFFFFSource:|r |cFF00FF00[" .. formattedInstance .. "] - " .. Boss .. "|r"
        else
            return nil
        end
    end
    return source
end

-- ===== SHIFT COMPARISON =====
local function ShowCompareTooltip(tooltip, itemId, link)
    if Bistooltip_CompareFrame then
        Bistooltip_CompareFrame:Hide()
    end
    if not IsShiftKeyDown() then return end
    if not itemId then return end

    local _, _, _, _, _, _, _, itemEquipLoc, _ = GetItemInfo(itemId)
    if not itemEquipLoc or itemEquipLoc == "" then return end

    local slotMap = {
        ["INVTYPE_HEAD"] = "HeadSlot", ["INVTYPE_NECK"] = "NeckSlot",
        ["INVTYPE_SHOULDER"] = "ShoulderSlot", ["INVTYPE_CHEST"] = "ChestSlot",
        ["INVTYPE_ROBE"] = "ChestSlot", ["INVTYPE_WAIST"] = "WaistSlot",
        ["INVTYPE_LEGS"] = "LegsSlot", ["INVTYPE_FEET"] = "FeetSlot",
        ["INVTYPE_WRIST"] = "WristSlot", ["INVTYPE_HAND"] = "HandsSlot",
        ["INVTYPE_FINGER"] = "Finger0Slot", ["INVTYPE_TRINKET"] = "Trinket0Slot",
        ["INVTYPE_CLOAK"] = "BackSlot",
        ["INVTYPE_WEAPON"] = "MainHandSlot", ["INVTYPE_2HWEAPON"] = "MainHandSlot",
        ["INVTYPE_WEAPONMAINHAND"] = "MainHandSlot",
        ["INVTYPE_SHIELD"] = "SecondaryHandSlot", ["INVTYPE_HOLDABLE"] = "SecondaryHandSlot",
        ["INVTYPE_WEAPONOFFHAND"] = "SecondaryHandSlot",
        ["INVTYPE_RANGED"] = "RangedSlot", ["INVTYPE_RANGEDRIGHT"] = "RangedSlot",
        ["INVTYPE_THROWN"] = "RangedSlot", ["INVTYPE_RELIC"] = "RangedSlot",
    }
    local slotIdName = slotMap[itemEquipLoc]
    if not slotIdName then return end

    local invSlot = GetInventorySlotInfo(slotIdName)
    local equippedLink = GetInventoryItemLink("player", invSlot)
    if not equippedLink then return end

    local _, eqItemId = strsplit(":", equippedLink)
    eqItemId = tonumber(eqItemId)
    if not eqItemId or eqItemId == itemId then return end

    if not Bistooltip_CompareFrame then
        Bistooltip_CompareFrame = CreateFrame("GameTooltip", "BistooltipCompare", UIParent, "GameTooltipTemplate")
    end
    Bistooltip_CompareFrame:SetOwner(tooltip:GetOwner() or UIParent, "ANCHOR_NONE")
    Bistooltip_CompareFrame:ClearAllPoints()
    Bistooltip_CompareFrame:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", 0, 0)
    Bistooltip_CompareFrame:SetHyperlink(equippedLink)
    Bistooltip_CompareFrame:Show()
end

-- Function to handle item tooltip
local function OnGameTooltipSetItem(tooltip)
    if BistooltipAddon.db.char.tooltip_with_ctrl and not IsControlKeyDown() then
        return
    end

    local _, link = tooltip:GetItem()
    if not link then return end

    local _, itemId, _, _, _, _, _, _, _, _, _, _, _, _ = strsplit(":", link)
    itemId = tonumber(itemId)
    if not itemId then return end

    -- If same item as before, skip re-adding BiS lines (shift refresh case)
    if itemId == Bistooltip_LastItemId then
        ShowCompareTooltip(tooltip, itemId, link)
        return
    end

    Bistooltip_LastItemId = itemId
    Bistooltip_LastLink = link

    if BistooltipAddon.db.char.show_item_sources ~= false then
        -- Ищем предмет во ВСЕХ бислистах, независимо от выбранного аддона
        local allBisSources = {
            { Bistooltip_wotlk_bislists,   Bistooltip_wowtbc_phases },
            { Bistooltip_tbc_bislists,     Bistooltip_tbc_phases },
            { Bistooltip_classic_bislists, Bistooltip_classic_phases },
        }
        for class, specs in caseInsensitivePairs(Bistooltip_spec_icons) do
            for spec, icon in pairs(specs) do
                if spec ~= "classIcon" then
                    local foundPhases = {}
                    for _, bisSource in ipairs(allBisSources) do
                        local structure, phases = bisSource[1], bisSource[2]
                        if structure and phases then
                            local found = searchIDInBislistsClassSpec(structure, phases, itemId, class, spec)
                            if found then
                                table.insert(foundPhases, found)
                            end
                        end
                    end
                    if #foundPhases > 0 then
                        local iconString = string.format("|T%s:18|t", icon)
                        local lineText = string.format("%s %s - %s", iconString, class, spec)
                        tooltip:AddDoubleLine(lineText, table.concat(foundPhases, " / "), 1, 1, 0, 1, 1, 0)
                    end
                end
            end
        end
    end

    local itemSource = GetItemSource(itemId)
    if itemSource then
        tooltip:AddLine(" ", 1, 1, 0)
        tooltip:AddLine(itemSource, 1, 1, 1)
        tooltip:AddLine(" ", 1, 1, 0)
    end

    ShowCompareTooltip(tooltip, itemId, link)
end

function BistooltipAddon:initBisTooltip()
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, _, e_key, _, _)
        if not GameTooltip:GetOwner() then return end
        if GameTooltip:GetOwner().hasItem then return end

        if e_key == "RALT" or e_key == "LALT" then
            local _, link = GameTooltip:GetItem()
            if link then
                GameTooltip:SetHyperlink("|cff9d9d9d|Hitem:3299::::::::20:257::::::|h[Fractured Canine]|h|r")
                GameTooltip:SetHyperlink(link)
            end
        end

        -- Shift changed: force tooltip rebuild by re-firing OnEnter on frame under cursor
        if e_key == "LSHIFT" or e_key == "RSHIFT" then
            local focus = GetMouseFocus()
            if focus and focus.GetScript then
                local onEnter = focus:GetScript("OnEnter")
                if onEnter then
                    onEnter(focus)
                end
            end
        end
    end)

    GameTooltip:HookScript("OnTooltipSetItem", OnGameTooltipSetItem)
    GameTooltip:HookScript("OnHide", function()
        Bistooltip_LastItemId = nil
        if Bistooltip_CompareFrame then Bistooltip_CompareFrame:Hide() end
    end)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnGameTooltipSetItem)
end
