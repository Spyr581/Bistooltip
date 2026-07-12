local AceGUI = LibStub("AceGUI-3.0")

local class = nil
local spec = nil
local phase = nil
local class_index = nil
local spec_index = nil
local phase_index = nil

local class_options = {}
local class_options_to_class = {}

local spec_options = {}
local spec_options_to_spec = {}
local spec_frame = nil
local items = {}
local spells = {}
local main_frame = nil

local classDropdown = nil
local specDropdown = nil
local phaseDropDown = nil

local checkmarks = {}
local boemarks = {}

local isHorde = UnitFactionGroup("player") == "Horde"

-- Target equipment scanning
local targetEquipment = {}

-- Forward decls for functions used before definition
local isAutoTrackEnabled

local function scanTargetEquipment()
    targetEquipment = {}
    if not UnitExists("target") or not UnitIsPlayer("target") then
        return
    end
    if CanInspect("target") then
        NotifyInspect("target")
    end
    for i = 1, 19 do
        local itemID = GetInventoryItemID("target", i)
        if itemID and itemID > 0 then
            targetEquipment[itemID] = true
        end
    end
end

local function hasItemInEquipment(item_id)
    -- If tracking is on, only show target's equipment
    if isAutoTrackEnabled() then
        return targetEquipment[item_id] == true
    end
    -- Tracking off: show player's equipment
    if Bistooltip_char_equipment and Bistooltip_char_equipment[item_id] then
        return true
    end
    return false
end

-- Target auto-tracking (moved after function definitions)
local manualMode = false
local trackedTarget = nil
local programmaticChange = false

local function createItemFrame(item_id, size, with_checkmark)
    if item_id < 0 then
        return AceGUI:Create("Label")
    end

    local item_frame = AceGUI:Create("Icon")
    item_frame:SetImageSize(size, size)

    local aliItemID
    if Bistooltip_horde_to_ali then
        aliItemID = Bistooltip_horde_to_ali[item_id]
    end

    if aliItemID then
        item_id = aliItemID
    end

    GameTooltip:SetHyperlink("item:" .. item_id .. ":0:0:0:0:0:0:0")
    local itemName, itemLink, _, _, _, _, _, _, _, itemIcon, _, itemType, _, bindType = GetItemInfo(item_id)

    if not itemName then
        item_frame:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
        return item_frame
    end

    item_frame:SetImage(itemIcon)

    if with_checkmark then
        local checkMark = item_frame.frame:CreateTexture(nil, "OVERLAY")
        checkMark:SetWidth(32)
        checkMark:SetHeight(32)
        checkMark:SetPoint("CENTER", 6, -8)
        checkMark:SetTexture("Interface\\AddOns\\Bistooltip\\checkmark-16.tga")
        table.insert(checkmarks, checkMark)
    end

    if bindType == 2 then
        local boeMark = item_frame.frame:CreateTexture(nil, "OVERLAY")
        boeMark:SetWidth(12)
        boeMark:SetHeight(12)
        boeMark:SetPoint("TOPLEFT", 2, -5)
        boeMark:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        table.insert(boemarks, boeMark)
    end

    item_frame:SetCallback("OnClick", function(button)
        SetItemRef(itemLink, itemLink, "LeftButton")
    end)
    item_frame:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(item_frame.frame)
        GameTooltip:SetPoint("TOPRIGHT", item_frame.frame, "TOPRIGHT", 220, -13)
        GameTooltip:SetHyperlink(itemLink)
    end)
    item_frame:SetCallback("OnLeave", function(widget)
        GameTooltip:Hide()
    end)

    return item_frame
end

local function createSpellFrame(spell_id, size)
    if spell_id < 0 then
        local f = AceGUI:Create("Label")
        return f
    end

    local spell_frame = AceGUI:Create("Icon")
    spell_frame:SetImageSize(size, size)

    -- Retrieve spell info directly using GetSpellInfo
    local name, rank, icon, castTime, minRange, maxRange = GetSpellInfo(spell_id)
    if not name then
        print("Failed to retrieve spell info for spell ID:", spell_id)
        return spell_frame
    end

    spell_frame:SetImage(icon)
    local link = GetSpellLink(spell_id)
    if not link then
        link = "\124cffffd000\124Hspell:" .. spell_id .. "\124h[" .. name .. "]\124h\124r"
    end

    -- Set callbacks for interactivity
    spell_frame:SetCallback("OnClick", function(button)
        SetItemRef(link, link, "LeftButton")
    end)
    spell_frame:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(spell_frame.frame)
        GameTooltip:SetPoint("TOPRIGHT", spell_frame.frame, "TOPRIGHT", 220, -13)
        GameTooltip:SetHyperlink(link)
    end)
    spell_frame:SetCallback("OnLeave", function(widget)
        GameTooltip:Hide()
    end)

    return spell_frame
end

local function createEnhancementsFrame(enhancements)
    local frame = AceGUI:Create("SimpleGroup")
    frame:SetLayout("Table")
    frame:SetWidth(40)
    frame:SetHeight(40)
    frame:SetUserData("table", {
        columns = {{
            weight = 14
        }, {
            width = 14
        }},
        spaceV = -10,
        spaceH = 0,
        align = "BOTTOMRIGHT"
    })
    frame:SetFullWidth(true)
    frame:SetFullHeight(true)
    frame:SetHeight(0)
    frame:SetAutoAdjustHeight(false)
    for i, enhancement in ipairs(enhancements) do
        local size = 16

        if enhancement.type == "none" then
            frame:AddChild(createItemFrame(-1, size))
        end
        if enhancement.type == "item" then
            frame:AddChild(createItemFrame(enhancement.id, size))
        end
        if enhancement.type == "spell" then
            frame:AddChild(createSpellFrame(enhancement.id, size))
        end
    end
    return frame
end

local function drawItemSlot(slot)
    local f = AceGUI:Create("Label")
    f:SetText(slot.slot_name)
    f:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    spec_frame:AddChild(f)
    spec_frame:AddChild(createEnhancementsFrame(slot.enhs))

    for i, original_item_id in ipairs(slot) do
        local item_id = original_item_id

        -- Check if Bistooltip_horde_to_ali is defined and use it for translation if available
        if isHorde and Bistooltip_horde_to_ali then
            local translated_item_id = Bistooltip_horde_to_ali[original_item_id]
            if translated_item_id then
                item_id = translated_item_id
            end
        end

        -- Check if the item_id is valid and exists in player/target equipment
        if item_id and hasItemInEquipment(item_id) then
            spec_frame:AddChild(createItemFrame(item_id, 40, true))
        else
            spec_frame:AddChild(createItemFrame(item_id, 40))
        end
    end
end

local function drawTableHeader(frame)
    local f = AceGUI:Create("Label")
    f:SetText("Slot")
    f:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    local color = 0.6
    f:SetColor(color, color, color)
    frame:AddChild(f)
    frame:AddChild(AceGUI:Create("Label"))
    for i = 1, 6 do
        f = AceGUI:Create("Label")
        f:SetText("Top " .. i)
        f:SetColor(color, color, color)
        frame:AddChild(f)
    end
end

local function saveData()
    BistooltipAddon.db.char.class_index = class_index
    BistooltipAddon.db.char.spec_index = spec_index
    BistooltipAddon.db.char.phase_index = phase_index
end

local function clearCheckMarks()
    for key, value in ipairs(checkmarks) do
        value:SetTexture(nil)
    end
    checkmarks = {}
end

local function clearBoeMarks()
    for key, value in ipairs(boemarks) do
        value:SetTexture(nil)
    end
    boemarks = {}
end

local function drawSpecData()
    clearCheckMarks()
    clearBoeMarks()
    saveData()
    items = {}
    spells = {}
    spec_frame:ReleaseChildren()
    drawTableHeader(spec_frame)
    if not spec or not phase then
        return
    end
    local slots = Bistooltip_bislists[class][spec][phase]
    for i, slot in ipairs(slots) do
        drawItemSlot(slot)
    end
end

local function buildClassDict()
    if not Bistooltip_classes or type(Bistooltip_classes) ~= "table" then
        return
    end

    class_options = {}
    for ci, class in ipairs(Bistooltip_classes) do
        local option_name = class.name
        table.insert(class_options, option_name)
        class_options_to_class[option_name] = {
            name = class.name,
            i = ci
        }
    end
end

local function buildSpecsDict(class_i)
    if not Bistooltip_classes or type(Bistooltip_classes) ~= "table" then
        return
    end

    spec_options = {}
    spec_options_to_spec = {}
    local class = Bistooltip_classes[class_i]
    for si, spec in ipairs(class.specs) do
        local option_name = "|T" .. Bistooltip_spec_icons[class.name][spec] .. ":14|t " .. spec
        table.insert(spec_options, option_name)
        spec_options_to_spec[option_name] = spec
    end
end

local function loadData()
    class_index = BistooltipAddon.db.char.class_index
    spec_index = BistooltipAddon.db.char.spec_index
    phase_index = BistooltipAddon.db.char.phase_index
    if class_index then
        class = class_options_to_class[class_options[class_index]].name
        buildSpecsDict(class_index)
    end
    if spec_index then
        spec = spec_options_to_spec[spec_options[spec_index]]
    end
    if phase_index then
        phase = Bistooltip_phases[phase_index]
    end
end

-- Target auto-tracking variables
local manualMode = false
local trackedTarget = nil
local programmaticChange = false

-- Auto-track: read/write directly from saved variable
isAutoTrackEnabled = function()
    return BistooltipAddon.db.char.autoTrackEnabled == true
end

local targetWatcher = CreateFrame("Frame")
targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")

local function updateForTarget()
    if not main_frame then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then return end
    
    local _, targetClassFile = UnitClass("target")
    if not targetClassFile then return end
    
    local tokenToName = {}
    for _, bcd in ipairs(Bistooltip_classes) do
        local token = string.upper(bcd.name)
        token = string.gsub(token, " ", "")
        tokenToName[token] = bcd.name
    end
    
    local className = tokenToName[targetClassFile]
    if not className then return end
    
    local newClassIndex = nil
    for i, opt in ipairs(class_options) do
        if opt == className then newClassIndex = i; break end
    end
    if not newClassIndex then return end
    
    trackedTarget = UnitGUID("target")
    scanTargetEquipment()
    
    class_index = newClassIndex
    class = className
    buildSpecsDict(newClassIndex)
    spec_index = 1
    spec = spec_options_to_spec[spec_options[1]]
    
    programmaticChange = true
    classDropdown:SetValue(newClassIndex)
    specDropdown:SetList(spec_options)
    specDropdown:SetDisabled(false)
    specDropdown:SetValue(1)
    programmaticChange = false
    
    drawSpecData()
end

targetWatcher:SetScript("OnEvent", function(self, event, ...)
    if not isAutoTrackEnabled() then return end
    if not main_frame then return end
    if not UnitExists("target") or not UnitIsPlayer("target") then
        trackedTarget = nil
        return
    end
    local guid = UnitGUID("target")
    if manualMode and trackedTarget and guid == trackedTarget then return end
    manualMode = false
    trackedTarget = guid
    updateForTarget()
end)

local function drawDropdowns()
    local dropDownGroup = AceGUI:Create("SimpleGroup")

    dropDownGroup:SetLayout("Table")
    dropDownGroup:SetUserData("table", {
        columns = {110, 180, 70},
        space = 1,
        align = "BOTTOMRIGHT"
    })
    main_frame:AddChild(dropDownGroup)

    classDropdown = AceGUI:Create("Dropdown")
    specDropdown = AceGUI:Create("Dropdown")
    phaseDropDown = AceGUI:Create("Dropdown")
    specDropdown:SetDisabled(true)

    phaseDropDown:SetCallback("OnValueChanged", function(_, _, key)
        if not programmaticChange then manualMode = true end
        phase_index = key
        phase = Bistooltip_phases[key]
        drawSpecData()
    end)

    specDropdown:SetCallback("OnValueChanged", function(_, _, key)
        if not programmaticChange then manualMode = true end
        spec_index = key
        spec = spec_options_to_spec[spec_options[key]]
        drawSpecData()
    end)

    classDropdown:SetCallback("OnValueChanged", function(_, _, key)
        if not programmaticChange then manualMode = true end
        class_index = key
        class = class_options_to_class[class_options[key]].name

        specDropdown:SetDisabled(false)
        buildSpecsDict(key)
        specDropdown:SetList(spec_options)
        specDropdown:SetValue(1)
        spec_index = 1
        spec = spec_options_to_spec[spec_options[1]]
        drawSpecData()
    end)

    classDropdown:SetList(class_options)
    phaseDropDown:SetList(Bistooltip_phases)

    dropDownGroup:AddChild(classDropdown)
    dropDownGroup:AddChild(specDropdown)
    dropDownGroup:AddChild(phaseDropDown)

    local fillerFrame = AceGUI:Create("Label")
    fillerFrame:SetText(" ")
    main_frame:AddChild(fillerFrame)

    classDropdown:SetValue(class_index)
    if (class_index) then
        buildSpecsDict(class_index)
        specDropdown:SetList(spec_options)
        specDropdown:SetDisabled(false)
    end
    specDropdown:SetValue(spec_index)
    phaseDropDown:SetValue(phase_index)
end

local function createSpecFrame()
    local frame = AceGUI:Create("ScrollFrame")
    frame:SetLayout("Table")
    frame:SetUserData("table", {
        columns = {{
            weight = 40
        }, {
            width = 44
        }, {
            width = 44
        }, {
            width = 44
        }, {
            width = 44
        }, {
            width = 44
        }, {
            width = 44
        }, {
            width = 44
        }},
        space = 1,
        align = "middle"
    })
    frame:SetFullWidth(true)
    frame:SetHeight(390)
    frame:SetAutoAdjustHeight(false)
    main_frame:AddChild(frame)
    spec_frame = frame
end

function BistooltipAddon:reloadData()
    buildClassDict()
    class_index = BistooltipAddon.db.char.class_index
    spec_index = BistooltipAddon.db.char.spec_index
    phase_index = BistooltipAddon.db.char.phase_index

    class = class_options_to_class[class_options[class_index]].name
    buildSpecsDict(class_index)
    spec = spec_options_to_spec[spec_options[spec_index]]
    phase = Bistooltip_phases[phase_index]

    if main_frame then
        phaseDropDown:SetList(Bistooltip_phases)
        classDropdown:SetList(class_options)
        specDropdown:SetList(spec_options)

        classDropdown:SetValue(class_index)
        specDropdown:SetValue(spec_index)
        phaseDropDown:SetValue(phase_index)

        drawSpecData()
    end
end

function BistooltipAddon:OpenDiscordLink()
    BistooltipAddon:closeMainFrame()
    StaticPopup_Show("DISCORD_LINK_DIALOG")
    StaticPopupDialogs["DISCORD_LINK_DIALOG"].preferredIndex = 4
end

StaticPopupDialogs["DISCORD_LINK_DIALOG"] = {
    text = "Join our Discord",
    button1 = "Copy Link",
    button2 = "Close",
    OnShow = function(self)
        self.editBox:SetText("https://discord.gg/Xk8BKqSapd")
        self.editBox:SetFocus()
        self.editBox:HighlightText()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
    hasEditBox = true,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    OnHide = function(self)
        self.data = nil
    end,
    EditBoxOnTextChanged = function(self, userInput)
        if userInput then
            self:SetText(self.data)
            self:HighlightText()
        end
    end,
    OnAccept = function(self)
        self.editBox:SetFocus()
        self.editBox:HighlightText()
        self.editBox:CopyText()
        self:Hide()
    end,
    OnCancel = function(self)
        self:Hide()
    end
}

function BistooltipAddon:createMainFrame()
    if main_frame then
        BistooltipAddon:closeMainFrame()
        return
    end

    main_frame = AceGUI:Create("Frame")
    main_frame:SetWidth(450)
    main_frame:SetHeight(550)
    main_frame.frame:SetMinResize(450, 300)
    main_frame.frame:SetMaxResize(800, 600)

    main_frame:SetCallback("OnClose", function(widget)
        clearCheckMarks()
        clearBoeMarks()
        spec_frame = nil
        items = {}
        spells = {}
        AceGUI:Release(widget)
        main_frame = nil
    end)
    main_frame:SetLayout("List")
    main_frame:SetTitle(BistooltipAddon.AddonNameAndVersion)

    drawDropdowns()
    createSpecFrame()
    drawSpecData()
    
    -- Auto-detect target on window open (if tracking enabled)
    if isAutoTrackEnabled() and UnitExists("target") and UnitIsPlayer("target") then
        updateForTarget()
    end

    -- Replace the status bar with our source dropdown
    -- Hide built-in status background
    local children = {main_frame.frame:GetChildren()}
    for _, child in ipairs(children) do
        if child:GetObjectType() == "Button" and child:GetBackdrop() then
            child:Hide()
        end
    end
    -- Hide status text
    if main_frame.statustext then
        main_frame.statustext:Hide()
    end

    -- Source selector (placed where status bar was)
    local sourceRow = AceGUI:Create("SimpleGroup")
    sourceRow:SetFullWidth(true)
    sourceRow:SetLayout("Flow")

    local sourceLabel = AceGUI:Create("Label")
    sourceLabel:SetText("Data source:")
    sourceLabel:SetWidth(75)
    sourceLabel:SetFont(GameFontNormal:GetFont(), 11)
    sourceRow:AddChild(sourceLabel)

    local sourceDropdown = AceGUI:Create("Dropdown")
    sourceDropdown:SetList(Bistooltip_source_to_url)
    sourceDropdown:SetValue(BistooltipAddon.db.char["data_source"])
    sourceDropdown:SetWidth(160)
    sourceDropdown:SetCallback("OnValueChanged", function(_, _, key)
        if key ~= BistooltipAddon.db.char["data_source"] then
            local savedClass = class_index
            local savedSpec = spec_index
            BistooltipAddon:changeSpec(key)
            if savedClass and class_options[savedClass] then
                class_index = savedClass
                class = class_options_to_class[class_options[class_index]].name
                buildSpecsDict(class_index)
                if savedSpec and spec_options[savedSpec] then
                    spec_index = savedSpec
                    spec = spec_options_to_spec[spec_options[savedSpec]]
                else
                    spec_index = 1
                    spec = spec_options_to_spec[spec_options[1]]
                end
                phase_index = 1
                phase = Bistooltip_phases[1]
                BistooltipAddon.db.char.class_index = class_index
                BistooltipAddon.db.char.spec_index = spec_index
                BistooltipAddon.db.char.phase_index = 1
                BistooltipAddon.db.char.data_source = key
                enableSpec(key)
                if main_frame then
                    classDropdown:SetList(class_options)
                    classDropdown:SetValue(class_index)
                    specDropdown:SetList(spec_options)
                    specDropdown:SetValue(spec_index)
                    phaseDropDown:SetList(Bistooltip_phases)
                    phaseDropDown:SetValue(1)
                    drawSpecData()
                end
            end
        end
    end)
    sourceRow:AddChild(sourceDropdown)

    -- Buttons row
    local buttonContainer = AceGUI:Create("SimpleGroup")
    buttonContainer:SetFullWidth(true)
    buttonContainer:SetLayout("Flow")

    local reloadButton = AceGUI:Create("Button")
    reloadButton:SetText("Reload Data")
    reloadButton:SetWidth(120)
    reloadButton:SetCallback("OnClick", function()
        BistooltipAddon:reloadData()
    end)
    buttonContainer:AddChild(reloadButton)

    -- Auto-track checkbox (replaces Discord button)
    local trackCheck = AceGUI:Create("CheckBox")
    trackCheck:SetLabel("Auto-track target")
    trackCheck:SetValue(isAutoTrackEnabled())
    trackCheck:SetCallback("OnValueChanged", function(_, _, val)
        BistooltipAddon.db.char.autoTrackEnabled = val
        if val and UnitExists("target") and UnitIsPlayer("target") then
            trackedTarget = UnitGUID("target")
            scanTargetEquipment()
            updateForTarget()
        else
            trackedTarget = nil
        end
    end)
    trackCheck:SetWidth(140)
    buttonContainer:AddChild(trackCheck)

    -- Show item sources checkbox (next to Auto-track)
    local sourcesCheck = AceGUI:Create("CheckBox")
    sourcesCheck:SetLabel("Who uses this")
    sourcesCheck:SetValue(BistooltipAddon.db.char.show_item_sources ~= false)
    sourcesCheck:SetCallback("OnValueChanged", function(_, _, val)
        BistooltipAddon.db.char.show_item_sources = val
    end)
    sourcesCheck:SetWidth(140)
    buttonContainer:AddChild(sourcesCheck)

    local noteLabel = AceGUI:Create("Label")
    noteLabel:SetText("Sometimes servers don't allow to query too many items so keep reloading and reopening the addon.")
    noteLabel:SetWidth(250)
    noteLabel:SetFont(GameFontNormal:GetFont(), 9)
    noteLabel:SetHeight(reloadButton.frame:GetHeight())
    noteLabel:SetFullWidth(false)
    noteLabel.label:SetPoint("BOTTOM")

    local spacerLabel = AceGUI:Create("Label")
    spacerLabel:SetWidth(20)
    buttonContainer:AddChild(spacerLabel)
    buttonContainer:AddChild(noteLabel)

    -- Wrap buttons+note and Data source together to reduce gap
    local bottomGroup = AceGUI:Create("SimpleGroup")
    bottomGroup:SetFullWidth(true)
    bottomGroup:SetLayout("List")
    bottomGroup:AddChild(buttonContainer)
    bottomGroup:AddChild(sourceRow)

    main_frame:AddChild(bottomGroup)
end

function BistooltipAddon:closeMainFrame()
    if main_frame then
        AceGUI:Release(main_frame)
        classDropdown = nil
        specDropdown = nil
        phaseDropDown = nil
        return
    end
end

function BistooltipAddon:initBislists()
    buildClassDict()
    loadData()
    LibStub("AceConsole-3.0"):RegisterChatCommand("bistooltip", function()
        BistooltipAddon:createMainFrame()
    end, persist)
    LibStub("AceConsole-3.0"):RegisterChatCommand("bistbc", function()
        BistooltipAddon:changeSpec("tbc")
        print("|cFF00FF00[Bis-Tooltip]|r Switched to TBC data")
    end, persist)
    LibStub("AceConsole-3.0"):RegisterChatCommand("biswotlk", function()
        BistooltipAddon:changeSpec("wowtbc")
        print("|cFF00FF00[Bis-Tooltip]|r Switched to WotLK data")
    end, persist)
    LibStub("AceConsole-3.0"):RegisterChatCommand("bisclassic", function()
        BistooltipAddon:changeSpec("classic")
        print("|cFF00FF00[Bis-Tooltip]|r Switched to Classic data")
    end, persist)
end
