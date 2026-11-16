-- Options page (Options > AddOns > Cinematic Azeroth, or /cinema): the key, the bars' size and
-- speed, and a preview.

local ADDON, ns = ...
local CA = ns.CA

local panel, category
local controls = {}

local function Refresh()
	for _, control in ipairs(controls) do control.Refresh() end
end

local function Changed()
	CA.Layout()
	if panel and panel:IsShown() then Refresh() end
end

local function CheckBox(parent, key, onChange, tooltip)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
	c:SetScript("OnClick", function(self)
		CA.db[key] = self:GetChecked() and true or false
		if onChange then onChange() end
	end)
	if tooltip then
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(c.label:GetText(), 1, 1, 1)
			GameTooltip:AddLine(tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	c.Refresh = function() c:SetChecked(CA.db[key]) end
	controls[#controls + 1] = c
	return c
end

-- Built without a template, like HeadlineDepthScale's, so it doesn't depend on which slider
-- templates this client has.
local function Slider(parent, label, key, minValue, maxValue, step, format, onChange)
	local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(260, 17)
	s:SetHitRectInsets(0, 0, -10, 0)
	if s.SetBackdrop then
		s:SetBackdrop({
			bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
			edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 3, right = 3, top = 6, bottom = 6 },
		})
	end
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(minValue, maxValue)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

	s.label = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
	s.label:SetText(label)

	s.value = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	s.value:SetPoint("LEFT", s, "RIGHT", 10, 0)

	local low = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 3)
	low:SetText(format(minValue))
	local high = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 3)
	high:SetText(format(maxValue))

	s:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / step + 0.5) * step
		self.value:SetText(format(value))
		if self.refreshing then return end
		CA.db[key] = value
		if onChange then onChange() end
	end)
	s.Refresh = function()
		s.refreshing = true
		s:SetValue(CA.db[key])
		s.value:SetText(format(CA.db[key]))
		s.refreshing = false
	end
	controls[#controls + 1] = s
	return s
end

---------------------------------------------------------------------------------------------------
-- Key button: click, then press a key.

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true,
}
local MOUSE_BINDINGS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function ModifierPrefix()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function KeysText(keys)
	if #keys == 0 then return nil end
	local texts = {}
	for i, key in ipairs(keys) do texts[i] = GetBindingText(key) end
	return table.concat(texts, ", ")
end

local function KeyButton(parent)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(180, 24)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- The OnKeyDown script exists only while capturing: a shown frame that has one receives every key
	-- press and swallows it, whatever EnableKeyboard says (2026-11-09: set permanently, it took the
	-- whole keyboard). Blizzard's KeybindListener sets and clears its own the same way.
	local function Stop()
		b.capturing = false
		b:SetScript("OnKeyDown", nil)
		b.Refresh()
	end

	local function Bind(binding)
		Stop()
		CA.SetKey(binding)
		b.Refresh()
	end

	local function OnKeyDown(self, key)
		if MODIFIER_KEYS[key] then return end
		if key == "ESCAPE" then
			Stop()
		else
			Bind(ModifierPrefix() .. key)
		end
	end

	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			Stop()
			CA.SetKey(nil)
			b.Refresh()
		elseif self.capturing then
			Stop()
		elseif InCombatLockdown() then
			CA.Print("key bindings can't change during combat.")
		else
			self.capturing = true
			self:SetScript("OnKeyDown", OnKeyDown)
			self:SetText("Press a key...")
		end
	end)
	b:SetScript("OnMouseDown", function(self, button)
		if self.capturing and MOUSE_BINDINGS[button] then Bind(ModifierPrefix() .. MOUSE_BINDINGS[button]) end
	end)
	b:SetScript("OnHide", function(self)
		if self.capturing then Stop() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Toggle cinematic mode")
		GameTooltip:AddLine("Left-click, then press a key or a mouse button (Escape cancels).", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click to clear.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.Refresh = function()
		if not b.capturing then b:SetText(KeysText(CA.OurKeys()) or "Not set") end
	end
	controls[#controls + 1] = b
	return b
end

---------------------------------------------------------------------------------------------------

local function PresetButton(parent, label, ratio)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(70, 22)
	b:SetText(label)
	b:SetScript("OnClick", function()
		local percent = (1 - CA.ScreenAspect() / ratio) / 2 * 100
		percent = math.max(0, math.min(25, math.floor(percent * 2 + 0.5) / 2))
		if percent <= 0 then CA.Print(("your screen is already as wide as %s or wider."):format(label)) end
		CA.db.barPercent = percent
		Changed()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(("Bar height that leaves a %s picture on this screen"):format(label), 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function Percent(value) return ("%g%%"):format(value) end
local function Seconds(value) return ("%.1f s"):format(value) end

local function SetupOptionsPage()
	panel = CreateFrame("Frame")
	panel.name = "Cinematic Azeroth"
	-- Until Settings first displays it (it then parents it and calls Show), the page is a shown
	-- frame with no parent; keep it hidden so nothing on it can take input.
	panel:Hide()

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Cinematic Azeroth")

	local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText("Press your key to hide the whole interface (and, as chosen below, the nameplates, the "
		.. "names above heads, the interaction icons and the text in the world) and slide in letterbox bars. Press it again, or Escape, to come back. The interface is hidden by "
		.. "Blizzard's own Toggle UI, so it also works in combat.")

	local keyTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	keyTitle:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
	keyTitle:SetText("Your key")

	local keyButton = KeyButton(panel)
	keyButton:SetPoint("TOPLEFT", keyTitle, "BOTTOMLEFT", 0, -6)

	local keyHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	keyHint:SetPoint("LEFT", keyButton, "RIGHT", 12, 0)
	keyHint:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	keyHint:SetJustifyH("LEFT")
	keyHint:SetText("Click, then press a key or a mouse button (Escape cancels). Right-click to clear. "
		.. "Also in Blizzard's Key Bindings, section Cinematic Azeroth. Not the mouse wheel: it can't be told "
		.. "apart from Blizzard's Toggle UI key.")

	local withToggle = CheckBox(panel, "withToggleUIKey")
	withToggle:SetPoint("TOPLEFT", keyButton, "BOTTOMLEFT", -2, -14)
	local checkRefresh = withToggle.Refresh
	withToggle.Refresh = function()
		checkRefresh()
		-- Without our own keys, in case GetBindingKey counts their override to TOGGLEUI.
		local ours, toggleKeys = {}, {}
		for _, key in ipairs(CA.OurKeys()) do ours[key] = true end
		for _, key in ipairs(CA.Keys(GetBindingKey("TOGGLEUI"))) do
			if not ours[key] then toggleKeys[#toggleKeys + 1] = key end
		end
		local keys = KeysText(toggleKeys) or "not bound"
		withToggle.label:SetText(("Also add the bars when Blizzard's Toggle UI key (%s) hides the interface"):format(keys))
	end

	local hidesTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	hidesTitle:SetPoint("TOPLEFT", withToggle, "BOTTOMLEFT", 2, -14)
	hidesTitle:SetText("Cinematic mode hides (the interface always goes)")

	local hidePlates = CheckBox(panel, "hidePlates", nil, "Unticked, the addon shows the nameplates again "
		.. "right after Blizzard hides them with the interface. That is done from the addon's own code, so if "
		.. "errors mention Cinematic Azeroth while nameplates are kept, tick this again.")
	hidePlates:SetPoint("TOPLEFT", hidesTitle, "BOTTOMLEFT", -2, -4)
	hidePlates.label:SetText("Nameplates (Threat Plates included)")

	local hideNames = CheckBox(panel, "hideNames", function() CA.UpdateCVars() end, "Blizzard's names "
		.. "above heads: yours, NPCs, players, pets, minions, critters. They are switched off in Blizzard's Names "
		.. "settings and put back exactly as they were afterwards, even after a crash (at the next login). The game "
		.. "doesn't let addons change them during combat: in cinematic mode started during a fight, they go when "
		.. "the fight ends.")
	hideNames:SetPoint("TOPLEFT", hidePlates, "BOTTOMLEFT", 0, 0)
	hideNames.label:SetText("Names above heads (NPCs, players, pets)")

	local hideBubbles = CheckBox(panel, "hideBubbles", function() CA.UpdateCVars() end, "Speech bubbles "
		.. "(say, yell, party and raid, NPCs too), switched off in Blizzard's settings and put back afterwards. "
		.. "Unticked, the bubbles stay and the chat typing bar works in cinematic mode too, so you can talk.")
	hideBubbles:SetPoint("TOPLEFT", hideNames, "BOTTOMLEFT", 0, 0)
	hideBubbles.label:SetText("Speech bubbles (unticked: typing bar too)")

	local hideCombatText = CheckBox(panel, "hideCombatText", function() CA.UpdateCVars() end, "The damage, "
		.. "healing and effect numbers shown on units, switched off in Blizzard's settings and put back afterwards.")
	hideCombatText:SetPoint("TOPLEFT", hideBubbles, "BOTTOMLEFT", 0, 0)
	hideCombatText.label:SetText("Combat numbers")

	local hideIcons = CheckBox(panel, "hideInteractIcons", function() CA.UpdateCVars() end, "The icon over the "
		.. "NPC or object you would interact with: vendor, trainer, flight master, mailbox... and the fishing bobber "
		.. "(Better Fishing switches these icons on for every cast; the addon switches them off again). Switched off "
		.. "in Blizzard's settings and put back afterwards. Interacting still works, Better Fishing's key included. "
		.. "A cast already out when cinematic mode starts keeps its icon until it ends. The game doesn't let addons "
		.. "change them during combat.")
	hideIcons:SetPoint("TOPLEFT", hideCombatText, "BOTTOMLEFT", 0, 0)
	hideIcons.label:SetText("Interaction icons (NPCs, fishing bobber)")

	local RIGHT_COLUMN = 350

	local keepTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	keepTitle:SetPoint("TOPLEFT", hidesTitle, "TOPLEFT", RIGHT_COLUMN, 0)
	keepTitle:SetText("Shown over the scene")

	local keepInteraction = CheckBox(panel, "keepInteraction", nil, "NPC dialog and quests, loot, vendors, "
		.. "flight master, trainers, bank, mail, auction house, stable, books, trade, with their confirmation "
		.. "pop-ups. In cinematic mode they are moved out of the hidden interface, so the ones an NPC opens appear "
		.. "alone over the scene, at their usual place. Everything goes back when cinematic mode ends.")
	keepInteraction:SetPoint("TOPLEFT", keepTitle, "BOTTOMLEFT", -2, -4)
	keepInteraction.label:SetText("Interaction windows")

	local keepBags = CheckBox(panel, "keepBags", nil, "In cinematic mode your bag keys open and close your bags "
		.. "over the scene, and so do vendors, the bank, the mailbox, trades and the auction house. Blizzard "
		.. "refuses to open bags while the interface is hidden, so the addon opens them itself, with Blizzard's own "
		.. "bag code. If using an item from them gives an error mentioning Cinematic Azeroth, untick this.")
	keepBags:SetPoint("TOPLEFT", keepInteraction, "BOTTOMLEFT", 0, 0)
	keepBags.label:SetText("Bags (your bag key too)")

	local keepTooltips = CheckBox(panel, "keepTooltips", nil, "Item and spell tooltips while an interaction "
		.. "window or the bags are open. Unticked, tooltips stay hidden in cinematic mode.")
	keepTooltips:SetPoint("TOPLEFT", keepBags, "BOTTOMLEFT", 0, 0)
	keepTooltips.label:SetText("Tooltips")

	local keepQuestMarks = CheckBox(panel, "keepQuestMarks", function() CA.UpdateCVars() end, "The ! and ? "
		.. "over quest givers. They have no setting of their own: they go with the nameplates when Blizzard hides "
		.. "the interface. So the addon brings those back and, if Nameplates is ticked on the left, switches the "
		.. "nameplates off in Blizzard's settings instead (put back afterwards). Those settings can't change "
		.. "during combat: then the marks stay hidden.")
	keepQuestMarks:SetPoint("TOPLEFT", keepTooltips, "BOTTOMLEFT", 0, 0)
	keepQuestMarks.label:SetText("Quest marks (! and ?)")

	local exitOnCombat = CheckBox(panel, "exitOnCombat", nil, "The interface, nameplates and names come "
		.. "back when combat starts, just before combat locks the interface.")
	exitOnCombat:SetPoint("TOPLEFT", hideIcons, "BOTTOMLEFT", 0, -10)
	exitOnCombat.label:SetText("Turn cinematic mode off when combat starts")

	local returnAfterCombat = CheckBox(panel, "returnAfterCombat", nil, ("When combat turned cinematic mode "
		.. "off, it comes back %d seconds after the fight (not while you are typing, nor when dead)."):format(CA.RETURN_DELAY))
	returnAfterCombat:SetPoint("TOPLEFT", exitOnCombat, "TOPLEFT", RIGHT_COLUMN, 0)
	returnAfterCombat.label:SetText("Come back to it after the fight")

	local combatNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	combatNote:SetPoint("TOPLEFT", exitOnCombat, "BOTTOMLEFT", 28, 0)
	combatNote:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	combatNote:SetJustifyH("LEFT")
	combatNote:SetText("Only a key press can show or hide the interface safely, so for combat the addon does it "
		.. "itself. If errors mention Cinematic Azeroth after a fight, or chat stops sending, untick these and use "
		.. "your key.")

	local onFlight = CheckBox(panel, "cinematicOnFlight", nil, "Taking a flight master's flight turns cinematic "
		.. "mode on, and landing turns it off again (unless you changed it with your key or Escape during the "
		.. "flight). Like for combat, no key is pressed, so the addon hides and shows the interface itself; if "
		.. "errors mention Cinematic Azeroth after a flight, untick this.")
	onFlight:SetPoint("TOPLEFT", combatNote, "BOTTOMLEFT", -28, -6)
	onFlight.label:SetText("Turn cinematic mode on during flights (flight master)")

	local barsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	barsTitle:SetPoint("TOPLEFT", onFlight, "BOTTOMLEFT", 2, -14)
	barsTitle:SetText("Letterbox bars")

	local barSlider = Slider(panel, "Height of each bar (share of the screen height)", "barPercent",
		0, 25, 0.5, Percent, Changed)
	barSlider:SetPoint("TOPLEFT", barsTitle, "BOTTOMLEFT", 4, -26)

	local picture = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	picture:SetPoint("TOPLEFT", barSlider, "BOTTOMLEFT", -4, -16)
	picture.Refresh = function()
		local share = 1 - 2 * CA.db.barPercent / 100
		picture:SetText(("Picture left between the bars: %.2f:1 on this screen. Film formats:"):format(
			CA.ScreenAspect() / math.max(0.01, share)))
	end
	controls[#controls + 1] = picture

	local scope = PresetButton(panel, "2.39:1", 2.39)
	scope:SetPoint("TOPLEFT", picture, "BOTTOMLEFT", 0, -6)
	local wide = PresetButton(panel, "2.00:1", 2.00)
	wide:SetPoint("LEFT", scope, "RIGHT", 6, 0)
	local flat = PresetButton(panel, "1.85:1", 1.85)
	flat:SetPoint("LEFT", wide, "RIGHT", 6, 0)

	local duration = Slider(panel, "Time for the bars to slide in or out", "duration", 0, 2, 0.1, Seconds)
	duration:SetPoint("TOPLEFT", scope, "BOTTOMLEFT", 4, -32)

	local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	preview:SetSize(160, 22)
	preview:SetPoint("LEFT", flat, "RIGHT", 24, 0)
	preview:SetScript("OnClick", function() CA.SetPreview(not CA.preview) end)
	preview.Refresh = function() preview:SetText(CA.preview and "Stop the preview" or "Preview the bars") end
	controls[#controls + 1] = preview
	CA.OnPreviewChanged = function() preview.Refresh() end

	local footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footer:SetPoint("TOPLEFT", duration, "BOTTOMLEFT", -4, -20)
	footer:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	footer:SetJustifyH("LEFT")
	footer:SetText("/cinema test shows the bars for 3 seconds. /cinema debug saves what is on screen into "
		.. "the addon's saved variables, for bug reports. /cinema help lists every command.")

	panel:SetScript("OnShow", Refresh)
	panel:SetScript("OnHide", function()
		if CA.preview then CA.SetPreview(false) end
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "Cinematic Azeroth")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function CA.OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

CA.OnBindingsChanged = function()
	if panel and panel:IsShown() then Refresh() end
end

function CinematicAzeroth_OnAddonCompartmentClick()
	CA.OpenOptions()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
	local ok, err = pcall(SetupOptionsPage)
	if not ok then CA.Print("options page failed: " .. tostring(err)) end
end)
