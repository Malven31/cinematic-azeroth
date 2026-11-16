-- Cinematic Azeroth: one key hides the interface and the nameplates and slides in letterbox bars.
--
-- The hiding is Blizzard's, not this addon's. Every key bound to "Toggle cinematic mode" is
-- redirected, with an override binding, to Blizzard's Toggle UI binding (TOGGLEUI, Alt+Z by
-- default; Bindings_Camelot.xml runs CloseMenus, CloseAllWindows, SetUIVisibility(false)).
-- A key press runs that binding securely, so:
--   * every frame's OnHide and OnShow runs untainted. SetUIVisibility or UIParent:Hide() called
--     from addon code would run them all tainted, and on Forever tainted Blizzard code fails on
--     secret values and can't send chat any more;
--   * it works in combat;
--   * the nameplates go too: UI visibility "controls whether nameplates are visible"
--     (Blizzard_Commentator.lua);
--   * Escape brings the interface back, as after Alt+Z (Game.lua's "Framework" Escape handler).
-- This addon watches UIParent being hidden and shown, tells from the keys held down at that moment
-- whether its own key did it, and draws the bars on a frame parented to WorldFrame, which stays
-- visible without UIParent (Blizzard's FramerateFrame and CommentatorFadeToBlackFrame live there).
-- What it does itself: hide the names above heads, the interaction icons and the text in the world
-- (CVars, put back afterwards), optionally bring the in-world interface back for nameplates or quest marks
-- (KeepInWorld), move interaction windows out of the hidden interface, open the bags (Blizzard refuses
-- to while the interface is hidden), and, from its own code, show the interface again when combat
-- starts (ExitForCombat) and hide or show it for flight master flights (Flights).

local ADDON, ns = ...
local CA = {}
ns.CA = CA

local issecretvalue = issecretvalue or function() return false end

CA.BINDING = "CINEMATICAZEROTH_TOGGLE"
BINDING_HEADER_CINEMATICAZEROTH = "Cinematic Azeroth"
BINDING_NAME_CINEMATICAZEROTH_TOGGLE = "Toggle cinematic mode"

CA.DEFAULTS = {
	barPercent = 12,         -- height of each bar, in % of the screen height
	duration = 0.6,          -- seconds for the bars to slide in or out
	withToggleUIKey = false, -- also when Blizzard's own Toggle UI key (Alt+Z) hides the interface
	hidePlates = true,       -- off: show the nameplates again after Blizzard's hide
	hideNames = true,        -- also hide Blizzard's names above heads (NPCs, players, pets...)
	hideBubbles = true,      -- also hide speech bubbles (off: the chat typing bar works too)
	hideCombatText = true,   -- also hide the damage and healing numbers shown on units
	hideInteractIcons = true, -- also hide the interaction icons over NPCs and objects (fishing bobber too)
	exitOnCombat = true,    -- show the interface again when combat starts
	returnAfterCombat = true, -- and come back to cinematic mode when that combat is over
	cinematicOnFlight = true, -- cinematic mode during flight master flights, off again on landing
	keepInteraction = true,  -- show interaction windows (NPC dialog, loot, vendors...) over the scene
	keepBags = true,         -- show the bags over the scene when they open
	keepTooltips = false,    -- show tooltips while one of those windows is open
	keepQuestMarks = true,   -- keep the ! and ? over quest givers (brings the in-world interface back)
	watch = false,           -- diagnostics (/cinema watch): a snapshot in every cinematic mode, chat buttons watch
}

local RETURN_DELAY = 3 -- seconds out of combat before cinematic mode comes back
CA.RETURN_DELAY = RETURN_DELAY

local LOG_SIZE = 40

---------------------------------------------------------------------------------------------------
-- Helpers

function CA.Print(msg)
	print("|cffd9b45aCinematic Azeroth|r: " .. msg)
end

local function CallMethod(obj, method, ...)
	return obj[method](obj, ...)
end

-- obj:method(...)'s first result, or nil when the call fails or the result is secret.
local function Read(obj, method, ...)
	if obj == nil then return nil end
	local ok, value = pcall(CallMethod, obj, method, ...)
	if not ok or issecretvalue(value) then return nil end
	return value
end
CA.Read = Read

-- The non-empty strings among the arguments (binding keys).
local function Keys(...)
	local keys = {}
	for i = 1, select("#", ...) do
		local key = select(i, ...)
		if type(key) == "string" and key ~= "" then keys[#keys + 1] = key end
	end
	return keys
end
CA.Keys = Keys

function CA.Log(msg)
	if not CA.db then return end
	local log = CA.db.log
	log[#log + 1] = ("%s (%.2f) %s"):format(date("%Y-%m-%d %H:%M:%S"), GetTime(), msg)
	while #log > LOG_SIZE do table.remove(log, 1) end
end

local function InitDB()
	if type(CinematicAzerothDB) ~= "table" then CinematicAzerothDB = {} end
	local db = CinematicAzerothDB
	if type(db.hideText) == "boolean" then -- split into bubbles and combat numbers (2026-11-09)
		if db.hideBubbles == nil then db.hideBubbles = db.hideText end
		db.hideText = nil
	end
	for key, value in pairs(CA.DEFAULTS) do
		if type(db[key]) ~= type(value) then db[key] = value end
	end
	if type(db.log) ~= "table" then db.log = {} end
	if type(db.snapshots) ~= "table" then db.snapshots = {} end
	if type(db.hiddenCVars) ~= "table" then db.hiddenCVars = {} end
	if type(db.combatLockedCVars) ~= "table" then db.combatLockedCVars = {} end -- seen blocked in combat
	if type(db.chatButtons) ~= "table" then db.chatButtons = {} end -- chat buttons watch (diagnostic)
	if type(db.chatButtons.log) ~= "table" then db.chatButtons.log = {} end
	if type(db.hiddenNames) == "table" then -- saved by the build that only hid names (2026-11-09)
		for key, values in pairs(db.hiddenNames) do
			local into = db.hiddenCVars[key] or {}
			db.hiddenCVars[key] = into
			for cvar, value in pairs(values) do
				if into[cvar] == nil then into[cvar] = value end
			end
		end
	end
	db.hiddenNames = nil
	db.keepDialog, db.keepLoot = nil, nil -- replaced by keepInteraction (2026-11-09)
	CA.db = db
end

---------------------------------------------------------------------------------------------------
-- Letterbox bars

local box = CreateFrame("Frame", "CinematicAzerothLetterbox", WorldFrame)
box:SetAllPoints(WorldFrame)
-- Lowest strata: above the 3D world but below the interface, so a preview from the options page,
-- or the bars sliding out as the interface comes back, never covers a window.
box:SetFrameStrata("BACKGROUND")
box:EnableMouse(false)
box:Hide()

local function NewBar(edge)
	local bar = box:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(0, 0, 0, 1)
	bar:SetPoint(edge .. "LEFT")
	bar:SetPoint(edge .. "RIGHT")
	bar:SetHeight(1)
	bar:Hide()
	return bar
end
local topBar, bottomBar = NewBar("TOP"), NewBar("BOTTOM")

local progress, target = 0, 0 -- 0: bars away, 1: bars fully in

local function Smooth(t)
	return t * t * (3 - 2 * t)
end

local function ScreenSize()
	local width, height = Read(box, "GetWidth"), Read(box, "GetHeight")
	if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
		width, height = GetScreenWidth(), GetScreenHeight()
	end
	return width, height
end

-- Width / height of the screen.
function CA.ScreenAspect()
	local width, height = ScreenSize()
	return width / height
end

local function Layout()
	local _, height = ScreenSize()
	local percent = CA.db and CA.db.barPercent or CA.DEFAULTS.barPercent
	local barHeight = height * percent / 100 * Smooth(progress)
	if barHeight < 0.5 then
		topBar:Hide()
		bottomBar:Hide()
	else
		topBar:SetHeight(barHeight)
		bottomBar:SetHeight(barHeight)
		topBar:Show()
		bottomBar:Show()
	end
end
CA.Layout = Layout

box:SetScript("OnUpdate", function(self, elapsed)
	if progress == target then return end
	local duration = CA.db and CA.db.duration or CA.DEFAULTS.duration
	local step = duration > 0 and elapsed / duration or 1
	if progress < target then
		progress = math.min(target, progress + step)
	else
		progress = math.max(target, progress - step)
	end
	Layout()
	if progress == 0 then self:Hide() end
end)
box:SetScript("OnSizeChanged", Layout)

local function UpdateBars()
	target = (CA.active or CA.preview) and 1 or 0
	if target > 0 or progress > 0 then
		box:Show()
	else
		box:Hide()
	end
	Layout()
end

---------------------------------------------------------------------------------------------------
-- What hiding the interface leaves in the world, each group switched off by CVars:
--   * names above heads (NPCs, players, pets...): Blizzard's Names options
--     (Blizzard_SettingsDefinitions_Frame/Nameplates.lua) and the ones Blizzard_Commentator.lua sets;
--   * text in the world: speech bubbles (Interface.lua) and the damage and healing numbers shown
--     on units (Mainline/CombatOverrides.lua; their sub-options don't show while these are off);
--   * interaction icons: soft targeting's icon over the NPC or object the player would interact with
--     (vendor, trainer, flight master, mailbox... and the fishing bobber).
-- In cinematic mode, the CVars of each group whose option is on go to 0, and the previous values
-- come back afterwards. Previous values are saved first, per character, in
-- CinematicAzerothDB.hiddenCVars, so a crash in cinematic mode is undone at the next login.
-- Leaving the world (logout, /reload, loading screens) puts them back too, before !ConfigSaver
-- saves CVars at PLAYER_LOGOUT.

-- combatLocked: an addon can't change these during combat lockdown (see LockedNow below).
local CVAR_GROUPS = {
	{ option = "hideNames", combatLocked = true, cvars = {
		"UnitNameOwn",
		"UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
		"UnitNameNonCombatCreatureName",
		"UnitNameFriendlyPlayerName", "UnitNameFriendlyMinionName", "UnitNameFriendlyPetName",
		"UnitNameFriendlyGuardianName", "UnitNameFriendlyTotemName",
		"UnitNameEnemyPlayerName", "UnitNameEnemyMinionName", "UnitNameEnemyPetName",
		"UnitNameEnemyGuardianName", "UnitNameEnemyTotemName",
	} },
	{ option = "hideBubbles", cvars = { "chatBubbles", "chatBubblesParty", "chatBubblesRaid" } },
	{ option = "hideCombatText", cvars = {
		"floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
		"floatingCombatTextSpellMechanics_v2",
	} },
	-- Interaction icons, and the plate soft targeting can put on that NPC. They show over the scene
	-- because the in-world interface comes back for the quest marks (KeepInWorld). Better Fishing
	-- switches the icons on with SetCVar at the start of every fishing cast and puts its own copy of
	-- the values back at the end (2026-11-11), so in cinematic mode they go back to 0 each time
	-- something switches them on (follow, CA.FollowCVars). Values read during a cast may be Better
	-- Fishing's temporary ones, so a CVar whose real value isn't known yet waits for the channel to end
	-- (notWhileChanneling). SoftTargetInteract itself stays as it is: Better Fishing's key needs it to
	-- click the bobber. Combat-locked: Threat Plates' CVarsManager lists the SoftTarget... CVars.
	{ option = "hideInteractIcons", combatLocked = true, follow = true, notWhileChanneling = true, cvars = {
		"SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetIconFriend",
		"SoftTargetNameplateInteract", "SoftTargetNameplateFriend",
	} },
	-- Nameplates' own visibility settings: only when the in-world interface is brought back for the
	-- quest marks while nameplates are to stay hidden (see KeepInWorld). Combat-locked (Threat Plates'
	-- CVarsManager lists them in COMBAT_PROTECTED); Threat Plates doesn't react to them changing.
	{ option = "platesByCVars", combatLocked = true, cvars = {
		"nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs", "nameplateShowSelf",
	} },
}

local function GroupOn(group)
	if not CA.db then return false end
	if group.option == "platesByCVars" then return CA.db.hidePlates and CA.db.keepQuestMarks end
	return CA.db[group.option]
end

local GetCVarInfo = C_CVar and C_CVar.GetCVarInfo
local SetCVarValue = C_CVar and C_CVar.SetCVar or SetCVar

local cvarsHidden = false  -- this session set CVars to 0
local cvarsPending = false -- some refused (combat?): try again after combat
-- busy: this addon is changing CVars (CA.FollowCVars must not run in the middle: a CVar it set to
-- 0 before ApplyCVars reached it would never be saved). channelWait: CVars left until the player's
-- channel ends. followed: how many times this cinematic mode set a "follow" CVar back to 0.
local cvarWork = { busy = false, channelWait = false, followed = 0 }

-- Whether the player is channeling a spell (fishing is one). A secret result still means one.
local function Channeling()
	local ok, name = pcall(UnitChannelInfo, "player")
	return ok and (issecretvalue(name) or name ~= nil)
end

local function CharacterKey()
	local name, realm = UnitName("player"), GetRealmName()
	if issecretvalue(name) or type(name) ~= "string" then name = "?" end
	if issecretvalue(realm) or type(realm) ~= "string" then realm = "?" end
	return name .. "-" .. realm
end

-- The CVar's value when this addon may change it; nil when it's missing, locked, secure or read-only.
local function CVarValue(cvar)
	if not GetCVarInfo then
		local ok, value = pcall(GetCVar, cvar)
		if ok and not issecretvalue(value) and type(value) == "string" then return value end
		return nil
	end
	local ok, value, _, _, _, locked, secure, readOnly = pcall(GetCVarInfo, cvar)
	if not ok or issecretvalue(value) or type(value) ~= "string" then return nil end
	if issecretvalue(locked) or issecretvalue(secure) or issecretvalue(readOnly) then return nil end
	if locked or secure or readOnly then return nil end
	return value
end

-- Combat lockdown: an addon can't change some CVars then, and a blocked SetCVar raises no Lua error
-- (pcall can't catch it): the game fires ADDON_ACTION_BLOCKED and BugSack shows "CinematicAzeroth
-- tried to call the protected function UNKNOWN()" (2026-11-09, cinematic mode entered in combat).
-- Nothing in the API says which CVars (C_CVar.GetCVarInfo has no such flag). Threat Plates'
-- CVarsManager lists the nameplate visibility CVars and the friendly UnitName... ones as
-- combat-protected, so the whole names group and the nameplate group are left alone during combat
-- and done when it ends (cvarsPending, and the restore at PLAYER_REGEN_ENABLED). ADDON_ACTION_BLOCKED
-- is a synchronous event: it fires inside the blocked call, so a CVar the game blocks anyway is
-- named, remembered in CinematicAzerothDB.combatLockedCVars, and not tried in combat again.
local COMBAT_LOCKED = {}
for _, group in ipairs(CVAR_GROUPS) do
	if group.combatLocked then
		for _, cvar in ipairs(group.cvars) do COMBAT_LOCKED[cvar] = true end
	end
end

local function LockedNow(cvar)
	if not InCombatLockdown() then return false end
	return COMBAT_LOCKED[cvar] or (CA.db and CA.db.combatLockedCVars[cvar]) or false
end

local cvarCall = {} -- name: the CVar being set right now; blocked: the game blocked that call

local function SetCVarSafe(cvar, value)
	if LockedNow(cvar) then return false end
	cvarCall.name, cvarCall.blocked = cvar, false
	local ok, result = pcall(SetCVarValue, cvar, value)
	local blocked = cvarCall.blocked
	cvarCall.name, cvarCall.blocked = nil, false
	return ok and not blocked and result ~= false
end

-- ADDON_ACTION_BLOCKED for this addon (event handler below).
function CA.OnActionBlocked(func)
	local cvar = cvarCall.name
	if not cvar then
		CA.Log(("the game blocked an action of this addon: %s (combat lockdown %s)"):format(tostring(func),
			tostring(InCombatLockdown() and true or false)))
		return
	end
	cvarCall.blocked = true
	local inCombat = InCombatLockdown() and true or false
	if inCombat and CA.db then CA.db.combatLockedCVars[cvar] = true end
	CA.Log(("%s: the game blocked changing it (%s, combat lockdown %s)%s"):format(cvar, tostring(func),
		tostring(inCombat), inCombat and ": no longer tried during combat" or ""))
end

-- The value a CVar gets in cinematic mode.
local function TargetValue(cvar)
	return "0"
end
-- Values an earlier build gave: the 2026-11-09 build that set the quest NPCs' names to 1 for the
-- quest marks (wrong: in-game, that showed those NPCs' names and still no marks). Accepted when
-- restoring, so a value it left behind is still put back.
local LEGACY_TARGETS = { UnitNameFriendlySpecialNPCName = "1" }

-- This character's saved values (created when asked), and its key.
local function SavedCVars(create)
	local key = CharacterKey()
	local saved = CA.db.hiddenCVars[key]
	if not saved and create then
		saved = {}
		CA.db.hiddenCVars[key] = saved
	end
	return saved, key
end

-- Puts one saved CVar back. A CVar no longer at the value this addon gave it was changed by someone
-- else since, and is left as it is.
local function RestoreOne(saved, cvar)
	local current = CVarValue(cvar)
	if current ~= TargetValue(cvar) and current ~= LEGACY_TARGETS[cvar] then
		saved[cvar] = nil
		return "dropped"
	elseif SetCVarSafe(cvar, saved[cvar]) then
		saved[cvar] = nil
		return "restored"
	end
	return "refused"
end

-- In cinematic mode: the groups whose option is on go to 0 (each previous value saved before it is
-- changed), the others are put back. Safe to call again: CVars already at 0 are left alone.
local function ApplyCVars()
	if not CA.db then return end
	cvarWork.busy = true
	local saved, key = SavedCVars(true)
	local channeling = Channeling()
	local hidden, restored, refused, waiting, afterChannel = 0, 0, 0, 0, 0
	for _, group in ipairs(CVAR_GROUPS) do
		for _, cvar in ipairs(group.cvars) do
			if GroupOn(group) then
				local value, target = CVarValue(cvar), TargetValue(cvar)
				if value and value ~= target then
					if LockedNow(cvar) then
						waiting = waiting + 1 -- not touched, nor saved, until combat ends
					elseif group.notWhileChanneling and channeling and saved[cvar] == nil then
						-- Not touched either: setting it now would also make Better Fishing keep 0 as
						-- the value to put back after its cast. CA.OnChannel applies it afterwards.
						afterChannel = afterChannel + 1
					else
						if saved[cvar] == nil then saved[cvar] = value end
						if SetCVarSafe(cvar, target) then hidden = hidden + 1 else refused = refused + 1 end
					end
				end
			elseif saved[cvar] ~= nil then
				local result = RestoreOne(saved, cvar)
				if result == "restored" then
					restored = restored + 1
				elseif result == "refused" then
					refused = refused + 1
				end
			end
		end
	end
	if next(saved) == nil then CA.db.hiddenCVars[key] = nil end
	cvarsHidden = true
	cvarsPending = refused + waiting > 0
	cvarWork.channelWait = afterChannel > 0
	cvarWork.busy = false
	CA.Log(("CVars: %d changed for cinematic mode, %d put back%s%s%s"):format(hidden, restored,
		waiting > 0 and (", " .. waiting .. " left for the end of combat (can't change during combat)") or "",
		afterChannel > 0 and (", " .. afterChannel .. " left until the spell being channeled ends") or "",
		refused > 0 and (", " .. refused .. " refused, retried after combat") or ""))
end

-- Puts back everything saved for this character.
local function RestoreCVars(reason)
	cvarsHidden, cvarsPending = false, false
	cvarWork.channelWait = false
	if not CA.db then return end
	local saved, key = SavedCVars(false)
	if not saved then return end
	cvarWork.busy = true
	local restored, refused = 0, 0
	for cvar in pairs(saved) do
		local result = RestoreOne(saved, cvar)
		if result == "restored" then
			restored = restored + 1
		elseif result == "refused" then
			refused = refused + 1
		end
	end
	cvarWork.busy = false
	if next(saved) == nil then CA.db.hiddenCVars[key] = nil end
	CA.Log(("CVars put back (%s): %d%s"):format(reason, restored,
		refused > 0 and (", " .. refused .. " refused, kept for the next try") or ""))
	if refused > 0 and InCombatLockdown() then
		CA.Print("some settings (nameplates, names or icons) can't change during combat: they come back when combat ends.")
	end
	return restored
end

-- After an option changes.
function CA.UpdateCVars()
	if CA.active then ApplyCVars() end
end

-- In cinematic mode, a CVar of a "follow" group that something else switched back on (Better Fishing
-- at the start of each cast, and at its end the value it kept) goes back to 0. Its saved value stays:
-- it is still the one to put back afterwards. A CVar waiting for the channel to end (its real value
-- not known yet) is left alone. Run on CVAR_UPDATE and after the player's channels start or stop.
function CA.FollowCVars()
	if cvarWork.busy or cvarCall.name or not (CA.active and cvarsHidden and CA.db) then return end
	cvarWork.busy = true
	local saved = SavedCVars(false) or {}
	for _, group in ipairs(CVAR_GROUPS) do
		if group.follow and GroupOn(group) then
			for _, cvar in ipairs(group.cvars) do
				local value, target = CVarValue(cvar), TargetValue(cvar)
				local unknown = group.notWhileChanneling and cvarWork.channelWait and saved[cvar] == nil
				if value and value ~= target and not unknown and not LockedNow(cvar) and SetCVarSafe(cvar, target) then
					cvarWork.followed = cvarWork.followed + 1
					if cvarWork.followed == 1 then
						CA.Log(("%s was switched back on (%s) by something else: set to 0 again (only counted after this, "
							.. "cvars.followed in the snapshots)"):format(cvar, value))
					end
				end
			end
		end
	end
	cvarWork.busy = false
end

-- The player's channel started or stopped (Better Fishing changes the icons then): next frame, after
-- every handler of the event. A cast that was already on when cinematic mode started has ended: the
-- CVars that waited for it are applied now, with their real values.
function CA.OnChannel(stopped)
	if not CA.active then return end
	C_Timer.After(0, function()
		if not CA.active then return end
		if stopped and cvarWork.channelWait and not Channeling() then
			ApplyCVars()
		else
			CA.FollowCVars()
		end
	end)
end

local function CVarsInfo()
	local values = {}
	for _, group in ipairs(CVAR_GROUPS) do
		for _, cvar in ipairs(group.cvars) do
			values[#values + 1] = ("%s (%s) = %s"):format(cvar, group.option,
				tostring(CVarValue(cvar) or "missing or not changeable"))
		end
	end
	local learned = {}
	for cvar in pairs(CA.db and CA.db.combatLockedCVars or {}) do learned[#learned + 1] = cvar end
	table.sort(learned)
	return { hidden = cvarsHidden, pending = cvarsPending, values = values,
		seenBlockedInCombat = table.concat(learned, " "),
		followed = cvarWork.followed, waitingForChannel = cvarWork.channelWait, channeling = Channeling() }
end

-- The in-world interface (nameplates, quest marks): Blizzard's SetUIVisibility(false) hides it with
-- the interface. SetInWorldUIVisibility(true) brings it back without the interface ("enables
-- nameplates, etc. but doesn't affect the actual UI frames", Blizzard_Commentator.lua), when the
-- nameplates are wanted (hidePlates off) or the quest marks are (keepQuestMarks). The ! and ? have
-- no setting of their own (none in Wow.exe's strings) and don't come with the names (2026-11-09:
-- Blizzard's "Quest NPCs" names showed those names but no marks), so they are taken to belong to
-- the in-world interface. With nameplates to stay hidden, their visibility CVars (platesByCVars)
-- must be at 0 first; they are combat-locked, and if they couldn't change, the in-world interface
-- stays hidden rather than bring the plates back. Called from this addon's code, so the plates'
-- show code may run tainted. A frame later, so it comes after the whole of Blizzard's hide.
local function PlateCVarsOff()
	for _, group in ipairs(CVAR_GROUPS) do
		if group.option == "platesByCVars" then
			for _, cvar in ipairs(group.cvars) do
				local value = CVarValue(cvar)
				if value ~= nil and value ~= "0" then return false end
			end
		end
	end
	return true
end

local function KeepInWorld()
	C_Timer.After(0, function()
		if not (CA.active and CA.db) then return end
		local wantPlates, wantMarks = not CA.db.hidePlates, CA.db.keepQuestMarks
		if not (wantPlates or wantMarks) then return end
		if not wantPlates and not PlateCVarsOff() then
			CA.Log("quest marks: the nameplate settings couldn't be switched off (combat?), so the in-world interface stays hidden")
			return
		end
		local ok, err = pcall(SetInWorldUIVisibility, true)
		CA.Log(ok and ("in-world interface shown again (" .. (wantPlates and "nameplates" or "quest marks, nameplates switched off") .. ")")
			or ("SetInWorldUIVisibility failed: " .. tostring(err)))
	end)
end

local function ChatBubblesInfo()
	local getBubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles
	local ok, bubbles = pcall(getBubbles)
	if not ok or type(bubbles) ~= "table" then return { note = "C_ChatBubbles.GetAllChatBubbles failed" } end
	local visible = 0
	for _, bubble in ipairs(bubbles) do
		if Read(bubble, "IsVisible") then visible = visible + 1 end
	end
	return { count = #bubbles, visible = visible }
end

---------------------------------------------------------------------------------------------------
-- Interaction windows shown over the cinematic scene (option keepInteraction): NPC dialog, quests,
-- loot, vendors, flight master, trainers, bank, mail, auction house, stable... They are children of
-- UIParent, so they would open hidden. In cinematic mode they are moved under `holder`, a WorldFrame
-- child with UIParent's effective scale: they keep their size and place (they stay anchored to
-- UIParent, whose geometry doesn't depend on it being shown). They go back when cinematic mode ends.
--   * Moved while closed: when cinematic mode starts (Blizzard's Toggle UI has just closed every
--     window) and as load-on-demand windows are created. Nothing of theirs runs then, and when an
--     NPC opens one, Blizzard shows it with its own code.
--   * A window found already open (created and shown in one go, or open when the addon hid the
--     interface after combat) is moved while open: its OnShow then runs from this addon's code.
--     Never closed to be moved: QuestFrame_OnHide calls CloseQuest, LootFrameMixin:OnHide CloseLoot.
--   * Bags are moved only while closed (moving an open one would run its OnShow from here). Blizzard
--     can't open them while the interface is hidden, so in cinematic mode this addon does (Bags, below).
--   * Tooltips and confirmation pop-ups only while one of these windows is on screen (otherwise
--     hovering a unit in the world would show a tooltip), and only while closed.
--   * Protected frames aren't moved in combat lockdown; one that can't go back waits for its end.

local WINDOWS = {} -- { name, option, closedOnly }
for _, name in ipairs({
	"GossipFrame", "QuestFrame", "ItemTextFrame", "LootFrame", "MerchantFrame", "TaxiFrame",
	"FlightMapFrame", "ClassTrainerFrame", "PetStableFrame", "BankFrame", "GuildBankFrame",
	"MailFrame", "OpenMailFrame", "AuctionHouseFrame", "BlackMarketFrame", "GuildRegistrarFrame",
	"PetitionFrame", "TabardFrame", "TradeFrame", "ItemUpgradeFrame", "ItemInteractionFrame",
	"ScrappingMachineFrame", "TransmogFrame", "AlliedRacesFrame", "ChromieTimeFrame",
	"DelvesDifficultyPickerFrame",
}) do WINDOWS[#WINDOWS + 1] = { name = name, option = "keepInteraction" } end
WINDOWS[#WINDOWS + 1] = { name = "ContainerFrameCombinedBags", option = "keepBags", closedOnly = true }
for i = 1, 13 do
	WINDOWS[#WINDOWS + 1] = { name = "ContainerFrame" .. i, option = "keepBags", closedOnly = true }
end

-- Moved only while one of the windows above is open, and only while closed.
local HELPERS = {
	{ name = "GameTooltip", option = "keepTooltips" },
	{ name = "ShoppingTooltip1", option = "keepTooltips" },
	{ name = "ShoppingTooltip2", option = "keepTooltips" },
	{ name = "StackSplitFrame", option = "keepInteraction" },
	{ name = "StaticPopup1", option = "keepInteraction" },
	{ name = "StaticPopup2", option = "keepInteraction" },
	{ name = "StaticPopup3", option = "keepInteraction" },
	{ name = "StaticPopup4", option = "keepInteraction" },
}
-- Blizzard re-parents a pop-up to UIParent each time it shows one (StaticPopup_Show:
-- dialog:SetParent(GetAppropriateTopLevelParent()), then dialog:Show()), which undoes the move.
local POPUPS = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }

local holder = CreateFrame("Frame", "CinematicAzerothWindows", WorldFrame)
holder:SetAllPoints(WorldFrame)

local function UpdateHolderScale()
	-- A protected window moved into it would make it protected too: no SetScale in combat then.
	if InCombatLockdown() and Read(holder, "IsProtected") ~= false then return end
	local uiScale, worldScale = Read(UIParent, "GetEffectiveScale"), Read(WorldFrame, "GetEffectiveScale")
	if type(uiScale) == "number" and type(worldScale) == "number" and uiScale > 0 and worldScale > 0 then
		holder:SetScale(uiScale / worldScale)
	end
end

local lifted = {}       -- frame -> { name, strata, helper }: moved under holder
local pendingDrops = {} -- frames that couldn't go back during combat lockdown

-- The chat typing bar goes into its own container (see the chat section below): invisible when
-- cinematic mode starts, faded in while a moved chat box has the keyboard (the player is typing),
-- faded out again after. Only this container's alpha changes: the boxes' own alpha belongs to
-- Blizzard, Prat and Kong, and hiding a box would run its OnHide from this addon's code.
local CHAT_FADE = 0.15 -- seconds
local chatHolder = CreateFrame("Frame", "CinematicAzerothChat", holder)
chatHolder:SetAllPoints(holder)
chatHolder:SetAlpha(0)
chatHolder.shownAlpha = 0

local function TypingInMovedBox()
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	return focus ~= nil and not issecretvalue(focus) and lifted[focus] ~= nil
end

chatHolder:SetScript("OnUpdate", function(self, elapsed)
	local target = (CA.active and TypingInMovedBox()) and 1 or 0
	local alpha = self.shownAlpha
	if alpha == target then return end
	local step = elapsed / CHAT_FADE
	if target > alpha then
		alpha = math.min(target, alpha + step)
	else
		alpha = math.max(target, alpha - step)
	end
	self.shownAlpha = alpha
	self:SetAlpha(alpha)
end)

local function HideChatHolder()
	chatHolder.shownAlpha = 0
	chatHolder:SetAlpha(0)
end

-- Moving a frame changes its frame level, and its children's absolute levels don't follow: bag
-- item buttons are declared with frameLevel="10" (ContainerFrame.xml) while the bag window, a
-- toplevel frame, is raised by Blizzard on every show, so after a move the window's own
-- background ended up drawn over its items (seen in-game, 2026-11-09). So every move records
-- the level of the frame and of everything inside it, and puts those exact levels back after.

local function Children(frame)
	return { frame:GetChildren() }
end

-- The frame and everything inside it, parents before children, each with its frame level.
local function CollectLevels(frame, out, depth)
	local level = Read(frame, "GetFrameLevel")
	if type(level) == "number" then out[#out + 1] = { frame = frame, level = level } end
	if depth < 12 then
		local ok, children = pcall(Children, frame)
		if ok and type(children) == "table" then
			for _, child in ipairs(children) do
				if not issecretvalue(child) and type(child) == "table" then CollectLevels(child, out, depth + 1) end
			end
		end
	end
	return out
end

local function MoveCalls(frame, parent, strata)
	local levels = CollectLevels(frame, {}, 0)
	frame:SetParent(parent)
	if strata then frame:SetFrameStrata(strata) end
	for _, entry in ipairs(levels) do
		pcall(CallMethod, entry.frame, "SetFrameLevel", entry.level)
	end
end

-- Addon code can't re-parent a protected frame in combat lockdown. Unknown counts as protected.
local function Blocked(frame)
	return InCombatLockdown() and Read(frame, "IsProtected") ~= false
end

local moving = false -- this addon is re-parenting a frame (the pop-up hook below ignores that)

-- silent: moved while UIParent is still visible, so no script of the frame ran.
-- parent: holder unless given (chat boxes go into chatHolder).
local function Lift(frame, name, helper, silent, parent)
	if lifted[frame] or Blocked(frame) then return false end
	local strata = Read(frame, "GetFrameStrata")
	local open = Read(frame, "IsShown")
	-- Put back under the same parent later: the individual bags' parent is ContainerFrameContainer
	-- (ContainerFrame.xml), not UIParent.
	local before = Read(frame, "GetParent")
	if before == holder or before == chatHolder then before = nil end
	moving = true
	local ok, err = pcall(MoveCalls, frame, parent or holder, strata)
	moving = false
	lifted[frame] = { name = name, strata = strata, helper = helper, parent = before } -- even on failure: no retry every frame
	if not ok then
		CA.Log(name .. ": moving it out of the hidden interface failed: " .. tostring(err))
	elseif open and not helper and not silent then
		CA.Log(name .. " was already open: now shown over the scene (its OnShow ran from this addon)")
	end
	return ok
end

local function Drop(frame)
	local info = lifted[frame]
	if not info then return end
	if Blocked(frame) then
		pendingDrops[frame] = true
		return
	end
	lifted[frame], pendingDrops[frame] = nil, nil
	moving = true
	local ok, err = pcall(MoveCalls, frame, info.parent or UIParent, info.strata)
	moving = false
	if not ok then CA.Log(info.name .. ": putting it back failed: " .. tostring(err)) end
end

local function DropAll()
	for frame in pairs(lifted) do Drop(frame) end
end

-- The windows that exist now and aren't moved yet; the closed-only ones only if closed.
local function LiftWindows(reason)
	if not CA.db then return end
	local count = 0
	for _, window in ipairs(WINDOWS) do
		local frame = _G[window.name]
		if CA.db[window.option] and type(frame) == "table" and not lifted[frame]
			and not (window.closedOnly and Read(frame, "IsShown")) then
			if Lift(frame, window.name, false) then count = count + 1 end
		end
	end
	if count > 0 then CA.Log(("%d interaction windows moved out of the hidden interface (%s)"):format(count, reason)) end
end

-- Whether one of the moved interaction windows (bags included) is open.
local function InteractionOpen()
	for _, window in ipairs(WINDOWS) do
		local frame = _G[window.name]
		if type(frame) == "table" and lifted[frame] and Read(frame, "IsShown") then return true end
	end
	return false
end

-- Pop-ups: hooksecurefunc on each one's SetParent runs right after Blizzard's re-parenting to
-- UIParent and before its Show(). While the pop-up is still closed, it goes back out of the hidden
-- interface (no script of its own runs), and Blizzard's Show() then displays it with its own code.
-- Only in cinematic mode, while an interaction window is open (the vendor's "sell junk" confirmation,
-- bind-on-pickup, purchases...); other pop-ups stay with the hidden interface as before.
local function OnPopupReparented(self, parent, name)
	if moving or not CA.active or parent ~= UIParent then return end
	if not (CA.db and CA.db.keepInteraction) or not InteractionOpen() or Blocked(self) then return end
	if lifted[self] then
		moving = true
		local ok, err = pcall(MoveCalls, self, holder, Read(self, "GetFrameStrata"))
		moving = false
		if not ok then CA.Log(name .. ": moving it back out failed: " .. tostring(err)) end
	else
		Lift(self, name, true, true)
	end
end

for _, name in ipairs(POPUPS) do
	local popup = _G[name]
	if type(popup) == "table" then
		pcall(hooksecurefunc, popup, "SetParent", function(self, parent)
			OnPopupReparented(self, parent, name)
		end)
	end
end

local watcher = CreateFrame("Frame", nil, WorldFrame) -- shown only in cinematic mode
watcher:Hide()
watcher:SetScript("OnUpdate", function()
	if not (CA.db and (CA.db.keepInteraction or CA.db.keepBags)) then return end
	LiftWindows("created or closed since")
	local anyOpen = InteractionOpen()
	for _, helper in ipairs(HELPERS) do
		local frame = _G[helper.name]
		if type(frame) == "table" and not Read(frame, "IsShown") then
			local wanted = anyOpen and CA.db[helper.option]
			if wanted and not lifted[frame] then
				Lift(frame, helper.name, true)
			elseif not wanted and lifted[frame] then
				Drop(frame)
			end
		end
	end
end)

local function LiftedInfo()
	local names = {}
	for _, info in pairs(lifted) do names[#names + 1] = info.name end
	table.sort(names)
	return names
end

---------------------------------------------------------------------------------------------------
-- Bags in cinematic mode (option keepBags). Every Blizzard function that opens or toggles bags starts
-- with ContainerFrame_AllowedToOpenBags(), which requires its full-screen frame, UIParent, to be shown
-- (Mainline ContainerFrame.lua; that frame is a file local only ContainerFrame_SetFullScreenFrame
-- changes, and no Blizzard code calls it). So while the interface is hidden, the bag key does nothing,
-- and neither do the windows that open the bags (vendor, bank, mail, trade, auction house all call
-- OpenAllBags(self) on show and CloseAllBags(self) on hide). A hook after each of those functions does
-- what Blizzard's would have done past that check, with the same Blizzard functions
-- (ContainerFrame_GenerateFrame, CloseBag). The bag windows are already moved out of the hidden
-- interface (LiftWindows), so they appear over the scene, at their usual place: they anchor to their
-- parent, which covers the screen like UIParent.
--   * Their OnShow runs from this addon's code, as when any addon opens the bags. Blizzard gives each
--     item button its bag through an attribute ("Prevent bagID from tainting all interaction with
--     items", ContainerFrameItemButtonMixin:SetBagID); whether using an item from them stays allowed
--     is checked in-game.
--   * CloseAllBags is never called from here: it writes the file local FRAME_THAT_OPENED_BAGS, which
--     Blizzard reads on every OpenAllBags. Bags are closed with CloseBackpack and CloseBag, and the
--     window that opened them is remembered here, so its CloseAllBags(self) closes them, as Blizzard's
--     does.
--   * Setting ContainerFrame_SetFullScreenFrame from here instead would taint that local for the
--     whole session (as StaticPopup_SetFullScreenFrame would).
do
	local opener      -- name of the window whose OpenAllBags(self) opened the bags here
	local busy = false -- this addon is opening or closing bags
	local hooked = {}

	local function Backpack()
		return Enum.BagIndex and Enum.BagIndex.Backpack or 0
	end

	-- In cinematic mode, Blizzard's function just refused because the interface is hidden.
	local function Ours()
		if busy or not (CA.active and CA.db and CA.db.keepBags) then return false end
		if Read(UIParent, "IsShown") ~= false then return false end -- Blizzard's own code did it
		local isRuleActive = C_GameRules and C_GameRules.IsGameRuleActive
		local rule = Enum.GameRule and Enum.GameRule.BagsUIDisabled
		if isRuleActive and rule then
			local ok, disabled = pcall(isRuleActive, rule)
			if ok and not issecretvalue(disabled) and disabled then return false end
		end
		return true
	end

	local function Combined(id)
		return ContainerFrameSettingsManager:IsUsingCombinedBags(id) and true or false
	end

	local function IsOpen(id)
		return IsBagOpen(id) and true or false
	end

	-- OpenBag past its check (OpenBag_Combined, OpenBag_Individual). 1 if it opened a window.
	local function OpenOne(id)
		if IsOpen(id) then return 0 end
		if Combined(id) then
			ContainerFrame_GenerateFrame(ContainerFrameCombinedBags, 0, Backpack())
			return 1
		end
		local size = ContainerFrame_GetContainerNumSlots(id) -- the keyring's size too
		if issecretvalue(size) or type(size) ~= "number" or size <= 0 then return 0 end
		ContainerFrame_GenerateFrame(ContainerFrame_GetOpenFrame(id), size, id)
		return 1
	end

	-- OpenAllBagsInternal: the backpack, then the bags not shown in the combined window.
	local function OpenAll()
		local count = OpenOne(Backpack())
		local first = Combined() and (Constants.InventoryConstants.NumBagSlots + 1) or 1
		for i = first, NUM_TOTAL_BAG_FRAMES do count = count + OpenOne(i) end
		return count
	end

	-- CloseAllBags without its FRAME_THAT_OPENED_BAGS write and its event.
	local function CloseAll()
		opener = nil
		CloseBackpack()
		for i = 1, NUM_TOTAL_BAG_FRAMES do CloseBag(i) end
		if KEYRING_CONTAINER and C_ActionBar and C_ActionBar.ShouldShowKeyring and C_ActionBar.ShouldShowKeyring() then
			CloseBag(KEYRING_CONTAINER)
		end
	end

	-- ToggleBag past its check (ToggleBag_Combined, ToggleBag_Individual).
	local function ToggleOne(id)
		if Combined(id) then
			if IsAnyStandardHeldBagOpen() then ContainerFrameCombinedBags:Hide() else OpenOne(Backpack()) end
		elseif IsOpen(id) then
			if id == Backpack() then CloseAll() else CloseBag(id) end
		else
			OpenOne(id)
		end
	end

	-- ToggleAllBags past its check: everything open closes, otherwise everything opens.
	local function ToggleAll()
		if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
			ToggleOne(Backpack())
			return
		end
		local open, total = IsOpen(Backpack()) and 1 or 0, 1
		local combined = Combined()
		for i = 1, NUM_TOTAL_BAG_FRAMES do
			if not (combined and i <= ENDING_BAG_INDEX) then -- shown in the combined window
				local slots = C_Container.GetContainerNumSlots(i)
				if not issecretvalue(slots) and type(slots) == "number" and slots > 0 then total = total + 1 end
				if IsOpen(i) then open = open + 1 end
			end
		end
		if open < total then OpenAll() else CloseAll() end
	end

	-- The bag windows open now; one not moved out of the hidden interface can't be seen.
	local function BagsShown()
		local names = {}
		for _, window in ipairs(WINDOWS) do
			local frame = _G[window.name]
			if window.option == "keepBags" and type(frame) == "table" and Read(frame, "IsShown") then
				names[#names + 1] = window.name .. (lifted[frame] and "" or " (not moved out: can't be seen)")
			end
		end
		return #names > 0 and table.concat(names, ", ") or "none"
	end

	local function Run(what, fn, ...)
		LiftWindows("bags opening") -- bag windows closed since cinematic mode started
		busy = true
		local ok, err = pcall(fn, ...)
		busy = false
		CA.Log(("bags (%s): %s, open: %s"):format(what, ok and "done by this addon" or ("failed: " .. tostring(err)),
			BagsShown()))
	end

	local HANDLERS = {
		ToggleAllBags = function() Run("bag key", ToggleAll) end,
		ToggleBackpack = function() Run("backpack key", ToggleOne, Backpack()) end,
		ToggleBag = function(id)
			if type(id) ~= "number" then return end
			if id == KEYRING_CONTAINER and GetCVarBool("showKeyring") == false then return end
			Run("bag " .. id .. " key", ToggleOne, id)
		end,
		OpenBackpack = function() Run("OpenBackpack", OpenOne, Backpack()) end,
		OpenBag = function(id)
			if type(id) == "number" then Run("OpenBag " .. id, OpenOne, id) end
		end,
		OpenAllBags = function(frame)
			if IsAnyBagOpen() then return end -- Blizzard's: a window opening while bags are open doesn't own them
			local name = frame and Read(frame, "GetName")
			Run("opened by " .. tostring(name or "a call without a window"), function()
				if type(name) == "string" and not opener then opener = name end
				OpenAll()
			end)
		end,
	}

	-- CloseAllBags(window): Blizzard's closes nothing unless that window opened the bags past its check.
	-- Closing the window that opened them here closes them. CloseAllBags() with no window (Blizzard's
	-- CloseAllWindows, Toggle UI...) closes everything itself and forgets the opener.
	local function OnCloseAllBags(frame)
		if busy then return end
		if frame == nil then
			opener = nil
			return
		end
		if not opener or Read(frame, "GetName") ~= opener then return end
		local name = opener
		busy = true
		local ok, err = pcall(CloseAll)
		busy = false
		CA.Log(("bags: %s closed, so its bags closed%s"):format(name, ok and "" or (" (failed: " .. tostring(err) .. ")")))
	end

	-- At load and again at PLAYER_LOGIN, in case a bag function didn't exist yet.
	function CA.HookBags()
		for name, handler in pairs(HANDLERS) do
			if not hooked[name] and type(_G[name]) == "function" then
				hooked[name] = true
				hooksecurefunc(name, function(...)
					if Ours() then handler(...) end
				end)
			end
		end
		if not hooked.CloseAllBags and type(CloseAllBags) == "function" then
			hooked.CloseAllBags = true
			hooksecurefunc("CloseAllBags", OnCloseAllBags)
		end
	end
	CA.HookBags()

	function CA.BagsInfo()
		local names = {}
		for name in pairs(hooked) do names[#names + 1] = name end
		table.sort(names)
		return { hooked = table.concat(names, " "), opener = opener, open = BagsShown() }
	end
end

---------------------------------------------------------------------------------------------------
-- Cinematic mode

CA.active = false  -- cinematic mode: the interface hidden by our key, bars in
CA.preview = false -- bars shown from the options page or /cinema test

local plateEvents = { added = 0, removed = 0 } -- counted while in cinematic mode, for the diagnostic

-- Combat (see ExitForCombat and ReturnAfterCombat below).
local endedByCombat = false     -- the last cinematic mode was ended by combat starting
local exitingForCombat = false  -- this addon is showing the interface because combat started
local hidingFor = nil           -- this addon is hiding the interface itself: why ("after combat", "flight")
local returnToken = 0           -- a newer combat cancels a pending return

function CA.SetActive(on)
	on = on and true or false
	if CA.active == on then return end
	CA.active = on
	UpdateBars()
	if not on then
		CA.flightOwned = false -- whatever ended it, landing no longer has anything to end
		watcher:Hide()
		DropAll()
		HideChatHolder()
		RestoreCVars("cinematic mode off")
	else
		endedByCombat = false
		HideChatHolder()
		UpdateHolderScale()
		LiftWindows("cinematic mode on")
		watcher:Show()
		cvarWork.followed = 0
		ApplyCVars()
		KeepInWorld()
		plateEvents.added, plateEvents.removed = 0, 0
		-- Chat can't be typed while the interface is hidden, so with /cinema watch on the diagnostic
		-- is taken now. Off by default: it goes through every frame on screen.
		if CA.db and CA.db.watch then
			C_Timer.After(1, function()
				if CA.active then CA.Snapshot("cinematic", "1 s after entering cinematic mode") end
			end)
		end
	end
end

local previewToken = 0
function CA.SetPreview(on, seconds)
	previewToken = previewToken + 1
	CA.preview = on and true or false
	UpdateBars()
	if on and seconds then
		local token = previewToken
		C_Timer.After(seconds, function()
			if previewToken == token then CA.SetPreview(false) end
		end)
	end
	if CA.OnPreviewChanged then CA.OnPreviewChanged() end
end

---------------------------------------------------------------------------------------------------
-- Keys

local bindingIndex

-- Keys bound to "Toggle cinematic mode", read from the binding table: the player's own bindings,
-- not the override bindings this addon puts on top of them.
function CA.OurKeys()
	if not (bindingIndex and GetBinding(bindingIndex) == CA.BINDING) then
		bindingIndex = nil
		for i = 1, GetNumBindings() do
			if GetBinding(i) == CA.BINDING then
				bindingIndex = i
				break
			end
		end
	end
	if not bindingIndex then return Keys(GetBindingKey(CA.BINDING)) end
	return Keys(select(3, GetBinding(bindingIndex)))
end

-- false where the client has no such function, so the name still counts as a modifier.
local MODIFIERS = {
	ALT = IsAltKeyDown,
	CTRL = IsControlKeyDown,
	SHIFT = IsShiftKeyDown,
	META = rawget(_G, "IsMetaKeyDown") or false,
}
-- Mouse buttons by binding name, and the names IsKeyDown may know them by instead.
local MOUSE_NAMES = {
	BUTTON1 = "LeftButton", BUTTON2 = "RightButton", BUTTON3 = "MiddleButton",
	BUTTON4 = "Button4", BUTTON5 = "Button5",
}

local function IsDown(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, down = pcall(fn, ...)
	return ok and not issecretvalue(down) and down and true or false
end

-- For a binding such as "SHIFT-F12": how many modifiers it has, if it is held down right now, and
-- what was tested (for the log). The whole binding is tried first: 2026-11-09, "ALT-W" was never
-- seen as held by testing ALT and then "W" alone, while "<" (no modifier) was.
local function HeldModifiers(binding)
	local key, count, modifiersDown = binding, 0, true
	while true do
		local modifier, rest = key:match("^(%u+)%-(.+)$")
		if not (modifier and MODIFIERS[modifier] ~= nil) then break end
		if not IsDown(MODIFIERS[modifier]) then modifiersDown = false end
		count = count + 1
		key = rest
	end
	local whole = IsDown(IsKeyDown, binding)
	local base = IsDown(IsKeyDown, key) or (MOUSE_NAMES[key] and IsDown(IsKeyDown, MOUSE_NAMES[key])) or false
	local detail = ("%s: whole %s, %s %s, modifiers %s"):format(binding, tostring(whole), key, tostring(base),
		count == 0 and "none" or tostring(modifiersDown))
	if whole or (modifiersDown and base) then return count, detail end
	return nil, detail
end

-- The most specific of these bindings held down right now (the one with most modifiers).
local function MostSpecificHeld(keys)
	local best, bestKey
	local tests = {}
	for _, key in ipairs(keys) do
		local count, detail = HeldModifiers(key)
		tests[#tests + 1] = detail
		if count and (not best or count > best) then best, bestKey = count, key end
	end
	return best, bestKey, table.concat(tests, "; ")
end

-- What hid the interface, from the keys held down at that moment: "ours", "toggleui", or nil
-- (a movie, a full-screen window, another addon such as DynamicCam). With both held, the binding
-- with more modifiers wins (Alt+Z over Z); a tie goes to ours.
local function HideSource()
	local ours, ourKey, ourTests = MostSpecificHeld(CA.OurKeys())
	local blizz, blizzKey, blizzTests = MostSpecificHeld(Keys(GetBindingKey("TOGGLEUI")))
	local detail = ("our key %s, Toggle UI key %s"):format(ourKey or "not held", blizzKey or "not held")
	if ours and (not blizz or ours >= blizz) then return "ours", detail end
	if blizz then return "toggleui", detail end
	return nil, ("%s [tested %s | %s]"):format(detail, ourTests, blizzTests)
end

---------------------------------------------------------------------------------------------------
-- Redirecting our keys to Blizzard's Toggle UI

local events = CreateFrame("Frame") -- event handler, and owner of the override bindings
local applied = ""                  -- the keys redirected now, space-separated
local pendingApply = false
local recentChanges = {}            -- when the redirect last changed, to stop a feedback loop
local loopStopped = false

-- Our own override calls fire UPDATE_BINDINGS too, which lands back here and finds nothing to do.
function CA.ApplyBindings()
	if loopStopped then return false end
	local keys = CA.OurKeys()
	local wanted = table.concat(keys, " ")
	if wanted == applied then return true end
	if InCombatLockdown() then
		pendingApply = true
		return false
	end
	local now = GetTime()
	recentChanges[#recentChanges + 1] = now
	while recentChanges[1] and recentChanges[1] < now - 2 do table.remove(recentChanges, 1) end
	if #recentChanges > 6 then
		loopStopped = true
		CA.Log("the key redirect changed more than 6 times in 2 s: stopped until /reload")
		CA.Print("stopped updating your key because it kept changing. /reload to try again.")
		return false
	end
	pendingApply = false
	ClearOverrideBindings(events)
	for _, key in ipairs(keys) do
		SetOverrideBinding(events, true, key, "TOGGLEUI")
	end
	applied = wanted
	CA.Log("keys redirected to Blizzard's Toggle UI: " .. (wanted ~= "" and wanted or "none"))
	return true
end

-- Bindings.xml: only runs when a key is pressed before its redirect is in place.
function CinematicAzeroth_OnKey()
	if CA.ApplyBindings() then
		CA.Print("your key is ready now. Press it again.")
	elseif loopStopped then
		CA.Print("your key isn't set up. /reload to try again.")
	else
		CA.Print("your key can't be set up during combat. It will work after combat.")
	end
end

-- Binds key (a binding such as "SHIFT-F12") to cinematic mode, replacing our previous keys.
-- With key nil, only unbinds.
function CA.SetKey(key)
	if InCombatLockdown() then
		CA.Print("key bindings can't change during combat.")
		return false
	end
	for _, old in ipairs(CA.OurKeys()) do SetBinding(old) end
	if key then
		local previous = GetBindingAction(key)
		if type(previous) == "string" and previous ~= "" and previous ~= CA.BINDING then
			CA.Print(("%s was bound to \"%s\". It now toggles cinematic mode."):format(
				GetBindingText(key), _G["BINDING_NAME_" .. previous] or previous))
		end
		if not SetBinding(key, CA.BINDING) then
			CA.Print("couldn't bind " .. GetBindingText(key) .. ".")
		end
	end
	SaveBindings(GetCurrentBindingSet())
	CA.ApplyBindings()
	return true
end

---------------------------------------------------------------------------------------------------
-- Diagnostic, saved in CinematicAzerothDB.snapshots: what is still on screen.

local function Number(value)
	return type(value) == "number" and ("%.0f"):format(value) or "?"
end

local function FrameLabel(frame)
	local name = Read(frame, "GetName")
	if type(name) ~= "string" then name = Read(frame, "GetDebugName") end
	if type(name) ~= "string" then name = "(" .. tostring(Read(frame, "GetObjectType") or "?") .. ")" end
	return name
end

-- Visible frames whose parent is nothing or WorldFrame: hiding UIParent doesn't hide those.
local function FramesOutsideUIParent()
	local result = { total = 0, plateFrames = 0, list = {} }
	if type(EnumerateFrames) ~= "function" then
		result.note = "EnumerateFrames missing"
		return result
	end
	local ok, frame = pcall(EnumerateFrames)
	local guard = 0
	while ok and frame and guard < 200000 do
		guard = guard + 1
		if frame ~= box and frame ~= WorldFrame and frame ~= UIParent and not Read(frame, "IsForbidden") then
			local okParent, parent = pcall(CallMethod, frame, "GetParent")
			if okParent and not issecretvalue(parent) and (parent == nil or parent == WorldFrame)
				and Read(frame, "IsVisible") then
				local name = FrameLabel(frame)
				-- Only what can be seen: hundreds of helper frames of 0x0 or 2x2 have no parent.
				local width, height = Read(frame, "GetWidth"), Read(frame, "GetHeight")
				local alpha = Read(frame, "GetEffectiveAlpha")
				local seen = not (type(width) == "number" and type(height) == "number" and (width < 8 or height < 8))
					and not (type(alpha) == "number" and alpha < 0.01)
				if name:match("^NamePlate%d") then
					result.plateFrames = result.plateFrames + 1
				elseif seen then
					result.total = result.total + 1
					if #result.list < 80 then
						result.list[#result.list + 1] = ("%s | parent %s | %s | %sx%s | alpha %s"):format(
							name, parent and "WorldFrame" or "none", tostring(Read(frame, "GetFrameStrata")),
							Number(width), Number(height),
							type(alpha) == "number" and ("%.2f"):format(alpha) or "?")
					end
				end
			end
		end
		ok, frame = pcall(EnumerateFrames, frame)
	end
	return result
end

local function ThreatPlatesFrame(plate)
	return plate.TPFrame
end

local function PlateParts(plate)
	local unitFrame = plate.UnitFrame
	local icon = unitFrame and unitFrame.SoftTargetFrame and unitFrame.SoftTargetFrame.Icon
	return unitFrame, icon, plate.TPFrame
end

-- What draws the interaction icon (flight master, vendor...) over the NPC the player faces: the
-- soft-target CVars, and for each soft or real target, its nameplate, Blizzard's unit frame on it,
-- the icon Blizzard puts on that frame (Blizzard_NamePlates.lua, SoftTargetFrame.Icon), and Threat
-- Plates' frame.
local SOFT_TARGET_CVARS = {
	"SoftTargetInteract", "SoftTargetIconInteract", "SoftTargetNameplateInteract", "SoftTargetIconFriend",
	"SoftTargetNameplateFriend", "SoftTargetIconGameObject", "SoftTargetNameplateSize", "SoftTargetWorldtextSize",
	"nameplateShowFriendlyNpcs",
	-- Better Fishing sets these during a cast (with SoftTargetInteract 3 and the two icons above at 1).
	"SoftTargetInteractRange", "SoftTargetInteractArc", "SoftTargetIconEnemy", "SoftTargetNameplateEnemy",
}
local function SoftTargetInfo()
	local info = { cvars = {}, units = {} }
	for _, cvar in ipairs(SOFT_TARGET_CVARS) do
		local ok, value = pcall(GetCVar, cvar)
		info.cvars[#info.cvars + 1] = cvar .. " = " .. tostring(ok and not issecretvalue(value) and value or "?")
	end
	local getPlate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	for _, unit in ipairs({ "softinteract", "softfriend", "target", "mouseover" }) do
		local okExists, exists = pcall(UnitExists, unit)
		if okExists and not issecretvalue(exists) and exists then
			local entry = { unit = unit }
			local okName, name = pcall(UnitName, unit)
			entry.name = okName and not issecretvalue(name) and name or "?"
			local okPlate, plate = pcall(getPlate, unit)
			if okPlate and type(plate) == "table" then
				entry.plateVisible = Read(plate, "IsVisible")
				local okParts, unitFrame, icon, tpFrame = pcall(PlateParts, plate)
				if okParts then
					entry.blizzardFrameVisible = Read(unitFrame, "IsVisible")
					local parent = unitFrame and Read(unitFrame, "GetParent")
					entry.blizzardFrameParent = parent and FrameLabel(parent) or "none (Threat Plates detached it?)"
					entry.softTargetIconShown = Read(icon, "IsShown")
					entry.softTargetIconVisible = Read(icon, "IsVisible")
					entry.softTargetIconTexture = tostring(Read(icon, "GetTexture"))
					entry.threatPlatesVisible = Read(tpFrame, "IsVisible")
				end
			else
				entry.plate = "none"
			end
			info.units[#info.units + 1] = entry
		end
	end
	return info
end

local function Nameplates()
	local info = { addedWhileCinematic = plateEvents.added, removedWhileCinematic = plateEvents.removed }
	local getPlates = C_NamePlate and C_NamePlate.GetNamePlates
	local ok, plates = pcall(getPlates)
	if not ok or type(plates) ~= "table" then
		info.note = "C_NamePlate.GetNamePlates failed"
		return info
	end
	info.count = #plates
	info.visible, info.threatPlates, info.threatPlatesVisible = 0, 0, 0
	for _, plate in ipairs(plates) do
		if Read(plate, "IsVisible") then info.visible = info.visible + 1 end
		local okFrame, tpFrame = pcall(ThreatPlatesFrame, plate)
		if okFrame and type(tpFrame) == "table" then
			info.threatPlates = info.threatPlates + 1
			if Read(tpFrame, "IsVisible") then info.threatPlatesVisible = info.threatPlatesVisible + 1 end
		end
	end
	return info
end

function CA.Snapshot(slot, reason)
	if not CA.db then return end
	local width, height = ScreenSize()
	local keys = {}
	for _, key in ipairs(CA.OurKeys()) do
		-- The action the key runs now, overrides included: should be TOGGLEUI.
		keys[#keys + 1] = key .. " -> " .. tostring(GetBindingAction(key, true))
	end
	local snapshot = {
		time = date("%Y-%m-%d %H:%M:%S"),
		reason = reason,
		cinematic = CA.active,
		preview = CA.preview,
		uiParentShown = Read(UIParent, "IsShown"),
		inCombat = InCombatLockdown() and true or false,
		letterbox = {
			shown = Read(box, "IsShown"),
			visible = Read(box, "IsVisible"),
			alpha = Read(box, "GetEffectiveAlpha"),
			strata = Read(box, "GetFrameStrata"),
			screen = Number(width) .. "x" .. Number(height),
			barHeight = Read(topBar, "IsShown") and Number(Read(topBar, "GetHeight")) or "hidden",
			progress = progress,
		},
		keys = {
			ours = keys,
			redirected = applied,
			toggleUI = table.concat(Keys(GetBindingKey("TOGGLEUI")), " "),
			withToggleUIKey = CA.db.withToggleUIKey,
		},
		nameplates = Nameplates(),
		cvars = CVarsInfo(),
		chatBubbles = ChatBubblesInfo(),
		softTarget = SoftTargetInfo(),
		options = {
			hidePlates = CA.db.hidePlates, hideNames = CA.db.hideNames, hideBubbles = CA.db.hideBubbles,
			hideCombatText = CA.db.hideCombatText, hideInteractIcons = CA.db.hideInteractIcons,
			exitOnCombat = CA.db.exitOnCombat,
			keepQuestMarks = CA.db.keepQuestMarks, keepBags = CA.db.keepBags, keepTooltips = CA.db.keepTooltips,
			returnAfterCombat = CA.db.returnAfterCombat, keepInteraction = CA.db.keepInteraction,
			cinematicOnFlight = CA.db.cinematicOnFlight,
		},
		flight = CA.FlightInfo and CA.FlightInfo() or nil,
		windowsMoved = LiftedInfo(),
		bags = CA.BagsInfo(),
		mail = CA.MailInfo and CA.MailInfo() or nil,
		framesOutsideUIParent = FramesOutsideUIParent(),
	}
	CA.db.snapshots[slot] = snapshot
	return snapshot
end

---------------------------------------------------------------------------------------------------
-- Following the interface. Kept short: these run in the middle of Blizzard's own hide and show.

UIParent:HookScript("OnHide", function()
	if not CA.db then return end
	if hidingFor then
		CA.Log(("interface hidden by this addon (%s): cinematic mode on"):format(hidingFor))
		CA.SetActive(true)
		return
	end
	local source, detail = HideSource()
	local enter = source == "ours" or (source == "toggleui" and CA.db.withToggleUIKey)
	CA.Log(("interface hidden (%s): %s"):format(detail, enter and "cinematic mode on" or "ignored"))
	if enter then CA.SetActive(true) end
end)

UIParent:HookScript("OnShow", function()
	if not exitingForCombat then endedByCombat = false end
	if CA.active then
		CA.Log("interface shown: cinematic mode off")
		CA.SetActive(false)
	end
end)

---------------------------------------------------------------------------------------------------
-- Minimap mail icon. Blizzard's Forever minimap hides the envelope in the mail frame's OnHide
-- (MiniMapMailFrameMixin:OnHide -> ResetMailIcon -> MailIcon:SetShown(false), Mainline/Minimap.lua),
-- which also runs when the interface is hidden. Nothing shows it again when the interface comes
-- back: the Camelot template (Camelot/MinimapMailFrameTemplate.xml) has no OnShow and none of
-- Mainline's animations, whose OnFinished restores it there. Only the next UPDATE_PENDING_MAIL does
-- (2026-11-11: gone after every cinematic mode until a /reload; Alt+Z and DynamicCam's hide do the
-- same). So when the mail frame or the interface shows again, the envelope is shown again if mail is
-- waiting. One frame later, so Blizzard's own handling of new mail goes first. Only a texture is
-- shown: no script of Blizzard's runs from this addon's code.
do
	local hooked = false

	local function MailFrame()
		local cluster = rawget(_G, "MinimapCluster")
		local indicator = type(cluster) == "table" and cluster.IndicatorFrame
		local frame = type(indicator) == "table" and indicator.MailFrame
		if type(frame) == "table" and type(frame.MailIcon) == "table" then return frame end
		return nil
	end

	local function HasMail()
		local ok, has = pcall(HasNewMail)
		return ok and not issecretvalue(has) and has and true or false
	end

	local function Check()
		local frame = MailFrame()
		if not frame or not Read(frame, "IsShown") then return end -- no mail: Blizzard hid the frame
		if Read(frame.MailIcon, "IsShown") ~= false or not HasMail() then return end
		local ok, err = pcall(CallMethod, frame.MailIcon, "Show")
		CA.Log(ok and "mail icon: shown again (Blizzard hides it with the interface and doesn't bring it back)"
			or ("mail icon: showing it again failed: " .. tostring(err)))
	end

	local function CheckSoon()
		C_Timer.After(0, Check)
	end

	-- At load and again at PLAYER_LOGIN, in case the minimap didn't exist yet.
	function CA.HookMailIcon()
		if hooked then return end
		local frame = MailFrame()
		if not frame then return end
		hooked = true
		frame:HookScript("OnShow", CheckSoon)
		UIParent:HookScript("OnShow", CheckSoon)
	end
	CA.HookMailIcon()

	function CA.MailInfo()
		local frame = MailFrame()
		if not frame then return { note = "MinimapCluster.IndicatorFrame.MailFrame not found" } end
		return { hooked = hooked, frameShown = Read(frame, "IsShown"), frameVisible = Read(frame, "IsVisible"),
			iconShown = Read(frame.MailIcon, "IsShown"), hasNewMail = HasMail() }
	end
end

---------------------------------------------------------------------------------------------------
-- Chat typing bar, when speech bubbles stay on (hideBubbles off), so the player can talk in
-- cinematic mode. The edit boxes are children of UIParent, and this addon must never make them
-- show or hide: their OnShow runs ResetChatType, which sets the chat type, and a chat type set from
-- addon code gets the send blocked on Forever; their OnHide can deactivate the chat. So they are
-- moved while UIParent is still visible, which fires neither: from a hook on CloseAllWindows,
-- which Blizzard's Toggle UI calls just before it hides the interface (Bindings_Camelot.xml), or
-- just before this addon hides it after combat. A closed box can also move later (no script runs
-- either), never an open one under the hidden interface. They go back once the interface shows
-- again (DropAll in SetActive), and not when leaving the world, which would hide them.

local function ChatBoxes()
	local boxes = {}
	for i = 1, tonumber(NUM_CHAT_WINDOWS) or 10 do
		local name = "ChatFrame" .. i .. "EditBox"
		if type(_G[name]) == "table" then boxes[#boxes + 1] = { frame = _G[name], name = name } end
	end
	return boxes
end

local function WantChat()
	return CA.db and CA.db.hideBubbles == false
end

local function LiftChat(interfaceVisible)
	if not WantChat() then return end
	local moved = 0
	for _, box in ipairs(ChatBoxes()) do
		if not lifted[box.frame] and (interfaceVisible or not Read(box.frame, "IsShown")) then
			HideChatHolder() -- invisible from the first frame of cinematic mode
			if Lift(box.frame, box.name, false, true, chatHolder) then moved = moved + 1 end
		end
	end
	if moved > 0 then CA.Log(("chat typing bar: %d edit boxes moved out of the interface"):format(moved)) end
end

local function DropChat()
	for _, box in ipairs(ChatBoxes()) do
		if lifted[box.frame] then Drop(box.frame) end
	end
end

if type(CloseAllWindows) == "function" then
	hooksecurefunc("CloseAllWindows", function()
		if CA.active or not WantChat() or not Read(UIParent, "IsShown") then return end
		local source = HideSource()
		if source == "ours" or (source == "toggleui" and CA.db.withToggleUIKey) then
			LiftChat(true)
			-- If the interface didn't go after all, put them back while it's still visible.
			C_Timer.After(0, function()
				if not CA.active and Read(UIParent, "IsShown") then DropChat() end
			end)
		end
	end)
end

-- Whether the chat globals that tainted show or hide code could write are still secure. Written to
-- the log after this addon showed or hid the interface itself.
local function LogChatTaint(when)
	if type(issecurevariable) ~= "function" then return end
	local parts = {}
	for _, name in ipairs({ "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX" }) do
		local ok, secure, taintedBy = pcall(issecurevariable, name)
		parts[#parts + 1] = name .. " " .. (not ok and "?" or secure and "secure" or ("tainted by " .. tostring(taintedBy)))
	end
	CA.Log("chat taint " .. when .. ": " .. table.concat(parts, ", "))
end

-- The interface hidden or shown by this addon's code, without a key press (after combat, for a
-- flight): every frame's OnHide or OnShow then runs tainted by this addon. The chat boxes are moved
-- out first while the interface is still visible (LiftChat), so theirs don't run. Hiding skips
-- Blizzard's CloseAllWindows; showing is what Blizzard's Escape handler does (Game.lua:
-- UIParent:Show(), then SetUIVisibility(true)). Our UIParent hooks turn cinematic mode on and off.
local function HideInterface(reason)
	LiftChat(true)
	hidingFor = reason
	local ok, err = pcall(SetUIVisibility, false)
	hidingFor = nil
	if not ok then CA.Log("hiding the interface failed: " .. tostring(err)) end
	LogChatTaint("after hiding the interface (" .. reason .. ")")
	return CA.active
end

local function ShowInterface(reason)
	local ok, err = pcall(UIParent.Show, UIParent)
	if ok then ok, err = pcall(SetUIVisibility, true) end
	if not ok then CA.Log("showing the interface failed: " .. tostring(err)) end
	if CA.active and Read(UIParent, "IsShown") then CA.SetActive(false) end
	LogChatTaint("after showing the interface (" .. reason .. ")")
end

---------------------------------------------------------------------------------------------------
-- Combat start. Only a key press brings the interface back securely: a secure snippet can't do
-- it either, because frame handles may show only explicitly protected frames in combat, and
-- UIParent isn't one (RestrictedInfrastructure.lua). So this is addon code doing what Blizzard's
-- Escape handler does (Game.lua: UIParent:Show(), then SetUIVisibility(true)), as DynamicCam does
-- on Forever. PLAYER_REGEN_DISABLED comes just before combat lockdown, the last moment UIParent
-- can still be shown. The interface's OnShow handlers then run tainted by this addon (for one,
-- the chat edit box's ResetChatType): BugGrabber will say if that breaks anything.

local function ExitForCombat()
	if not (CA.active and CA.db and CA.db.exitOnCombat) then return end
	if InCombatLockdown() then
		CA.Log("combat started, but combat lockdown was already on: the interface stays hidden")
		return
	end
	CA.Log("combat started: showing the interface")
	exitingForCombat = true
	ShowInterface("for combat")
	exitingForCombat = false
	if not CA.active then endedByCombat = true end
end

-- Combat over (option returnAfterCombat): when combat ended cinematic mode, it comes back
-- RETURN_DELAY seconds later, unless combat starts again first. Hiding the interface without a
-- key press is addon code too (SetUIVisibility(false), without Blizzard's CloseAllWindows), so its
-- OnHide handlers run tainted. Not while typing or with a chat box still active (the chat edit
-- box's OnHide would deactivate it from addon code): it waits, up to 30 s. Not when dead.
local function TryReturn(token, tries)
	if token ~= returnToken or not endedByCombat or not (CA.db and CA.db.returnAfterCombat) then return end
	if InCombatLockdown() or CA.active then return end
	if not Read(UIParent, "IsShown") then
		endedByCombat = false -- hidden by something else meanwhile
		return
	end
	if UnitIsDeadOrGhost("player") then
		endedByCombat = false
		CA.Log("combat over, but dead: not back to cinematic mode")
		return
	end
	if GetCurrentKeyBoardFocus() or ACTIVE_CHAT_EDIT_BOX then
		if tries < 30 then
			C_Timer.After(1, function() TryReturn(token, tries + 1) end)
		else
			endedByCombat = false
			CA.Log("combat over, but still typing after 30 s: not back to cinematic mode")
		end
		return
	end
	endedByCombat = false
	CA.Log("combat over: back to cinematic mode")
	HideInterface("after combat")
end

local function ScheduleReturn()
	if not (endedByCombat and CA.db and CA.db.returnAfterCombat) then return end
	returnToken = returnToken + 1
	local token = returnToken
	C_Timer.After(RETURN_DELAY, function() TryReturn(token, 0) end)
end

---------------------------------------------------------------------------------------------------
-- Flights (option cinematicOnFlight): a flight master's flight turns cinematic mode on, and landing
-- turns it off again, unless the player changed it meanwhile (CA.flightOwned, cleared whenever
-- cinematic mode ends). PLAYER_CONTROL_LOST starts a flight: Blizzard's own handler reads
-- UnitOnTaxi("player") as true then (GameEvent.HandlePlayerControlLost, Shared/EventImplementation.lua).
-- PLAYER_CONTROL_GAINED ends it; while the flight owns cinematic mode, UnitOnTaxi is also checked
-- every 2 s in case that event is missed. No key is pressed, so the interface is hidden and shown by
-- this addon's code (HideInterface, ShowInterface). Not while typing or dead; combat lockdown makes
-- it wait (UIParent can't be shown then).
do
	local flightToken = 0 -- a newer control change cancels what an older one scheduled
	local Land

	local function OnTaxi()
		local ok, onTaxi = pcall(UnitOnTaxi, "player")
		return ok and not issecretvalue(onTaxi) and onTaxi and true or false
	end

	local function Watch(token)
		C_Timer.After(2, function()
			if token ~= flightToken or not (CA.active and CA.flightOwned) then return end
			if OnTaxi() then Watch(token) else Land(token) end
		end)
	end

	local function TakeOff(token, tries)
		if token ~= flightToken or not (CA.db and CA.db.cinematicOnFlight) or CA.active then return end
		if not OnTaxi() then
			-- Control lost for another reason (stun, fear...), or the taxi state comes a moment later.
			if tries < 4 then C_Timer.After(0.5, function() TakeOff(token, tries + 1) end) end
			return
		end
		if not Read(UIParent, "IsShown") then return end -- hidden by something else
		if UnitIsDeadOrGhost("player") then return end
		if InCombatLockdown() or GetCurrentKeyBoardFocus() or ACTIVE_CHAT_EDIT_BOX then
			if tries == 0 then CA.Log("flight started: waiting (in combat, or typing)") end
			C_Timer.After(1, function() TakeOff(token, tries + 1) end)
			return
		end
		CA.Log("flight started: cinematic mode on")
		if HideInterface("flight") then
			CA.flightOwned = true
			Watch(token)
		end
	end

	Land = function(token)
		if token ~= flightToken or not (CA.active and CA.flightOwned) or OnTaxi() then return end
		if InCombatLockdown() then
			CA.Log("landed in combat: the interface comes back when combat ends")
			return -- CA.FlightCheck at PLAYER_REGEN_ENABLED
		end
		CA.Log("landed: cinematic mode off")
		ShowInterface("landed")
	end

	function CA.OnControlLost()
		flightToken = flightToken + 1
		local token = flightToken
		C_Timer.After(0, function() TakeOff(token, 0) end) -- after every handler of the event
	end

	function CA.OnControlGained()
		flightToken = flightToken + 1
		local token = flightToken
		C_Timer.After(0, function() Land(token) end)
	end

	-- After combat: a landing that had to wait. After a loading screen or /reload: also a flight
	-- still going on (takeOff), whose cinematic mode the reload ended.
	-- A new token only when acting, so a landing watch or a waiting take-off isn't cancelled for nothing.
	function CA.FlightCheck(takeOff)
		if CA.active and CA.flightOwned then
			if OnTaxi() then return end -- still flying: Watch goes on
			flightToken = flightToken + 1
			Land(flightToken)
		elseif takeOff and not CA.active and OnTaxi() then
			flightToken = flightToken + 1
			TakeOff(flightToken, 0)
		end
	end

	function CA.FlightInfo()
		return { onTaxi = OnTaxi(), ownedByFlight = CA.flightOwned and true or false }
	end
end

---------------------------------------------------------------------------------------------------
-- Chat buttons watch (diagnostic, 2026-11-12). The buttons beside the chat (friends, chat channels,
-- chat menu) sometimes go missing, seen around a flight, and which addon does it isn't known:
-- DynamicCam's taxi situation, Kong, Prat-3.0, this addon's flight mode and Blizzard's chat dock all
-- touch them. Nothing is changed here; CinematicAzerothDB.chatButtons records:
--   log: each Show/Hide/SetShown/SetParent call on a watched frame (and on UIParent) that changes
--        it, with the code that made the call (debugstack), plus every change of what is hidden,
--        checked 4 times a second, and the selected chat tab;
--   snapshot: the full state of those frames, saved by /cinema chat;
--   landing: the same, 3 s after the player gets control back (the end of a flight).
-- Only method hooks (hooksecurefunc), no HookScript: Prat-3.0 calls SetScript("OnShow") on some of
-- these buttons, which would wipe a hooked script.
-- Off by default (option watch, /cinema watch). Hooks can't be removed, so once installed they stay
-- until /reload but record nothing while the watch is off; the poll stops.
do
	local WATCHED = {
		"QuickJoinToastButton",     -- friends
		"ChatFrameChannelButton",   -- chat channels, a child of ChatFrame1ButtonFrame
		"ChatFrameMenuButton",      -- chat menu, a child of ChatFrame1ButtonFrame
		"ChatFrame1ButtonFrame",    -- a child of ChatFrame1
		"ChatFrame1",
		"ChatAlertFrame",           -- lays out the friends and text-to-speech buttons above the column
		"TextToSpeechButtonFrame",
		"ChatFrameToggleVoiceDeafenButton",
		"ChatFrameToggleVoiceMuteButton",
		"GeneralDockManager",       -- the chat tabs
	}
	local DYNAMICCAM_MARKS = { "ludius_shownBeforeFadeOut", "ludius_alphaBeforeFadeOut",
		"ludius_alreadyOnIt", "ludius_parentBeforeFadeOut" }
	local LOG_MAX = 150
	local hooked = {}    -- frame -> true
	local lastShown = {} -- frame -> its own shown flag, as last seen
	local lastState = {} -- name -> what State() said last
	local ticker = nil

	local function Name(frame)
		if frame == nil then return "nil" end
		local name = Read(frame, "GetName")
		return type(name) == "string" and name or tostring(frame)
	end

	local function Num(value)
		return type(value) == "number" and ("%.2f"):format(value) or tostring(value)
	end

	local function Log(msg)
		local store = CA.db and CA.db.chatButtons
		if not store then return end
		local log = store.log
		log[#log + 1] = ("%s (%.2f) %s"):format(date("%Y-%m-%d %H:%M:%S"), GetTime(), msg)
		while #log > LOG_MAX do table.remove(log, 1) end
	end

	-- Up to four stack lines of the code that called the hooked method. Level 3 skips Caller and
	-- the hook; [C] lines (the hook wrapper, pcall) carry no file and are left out.
	local function Caller()
		local ok, stack = pcall(debugstack, 3, 12, 0)
		if not ok or type(stack) ~= "string" then return "?" end
		local found = {}
		for line in stack:gmatch("[^\n]+") do
			local file, lineNo = line:match("AddOns/([^%]\"]+)\"?%]:(%d+)")
			if file then
				local func = line:match("in function [`']([^']+)'")
				found[#found + 1] = file .. ":" .. lineNo .. (func and (" " .. func) or "")
				if #found == 4 then break end
			end
		end
		return #found > 0 and table.concat(found, " < ") or "the game itself (no Lua caller)"
	end

	local function IsShownFlag(frame)
		local shown = Read(frame, "IsShown")
		if shown == nil then return nil end
		return shown and true or false
	end

	-- What hides a frame, apart from alpha and UIParent: itself, or the first hidden frame above it.
	local function State(frame)
		local shown = IsShownFlag(frame)
		if shown == nil then return "unknown (secret)" end
		if not shown then return "hidden" end
		local parent, depth = Read(frame, "GetParent"), 0
		while parent ~= nil and parent ~= UIParent and depth < 10 do
			if IsShownFlag(parent) == false then return "inside hidden " .. Name(parent) end
			parent, depth = Read(parent, "GetParent"), depth + 1
		end
		return "shown"
	end

	local function SelectedTab()
		local ok, frame = pcall(function() return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) end)
		return ok and Name(frame) or "?"
	end

	local function Watching()
		return CA.db and CA.db.watch and true or false
	end

	local function OnCall(method)
		return function(frame, arg)
			if not Watching() then return end
			if method == "SetParent" then
				Log(("%s:SetParent(%s) by %s"):format(Name(frame), Name(arg), Caller()))
				return
			end
			local shown = IsShownFlag(frame)
			if shown == lastShown[frame] then return end -- Blizzard's dock hides hidden windows again and again
			lastShown[frame] = shown
			Log(("%s %s by %s (%s)"):format(Name(frame), shown and "shown" or "hidden", Caller(), method))
		end
	end

	local function Hook(frame)
		if hooked[frame] then return end
		hooked[frame] = true
		for _, method in ipairs({ "Show", "Hide", "SetShown", "SetParent" }) do
			hooksecurefunc(frame, method, OnCall(method))
		end
		lastShown[frame] = IsShownFlag(frame)
	end

	local function Poll()
		local changes = {}
		local function Note(key, value)
			if value ~= lastState[key] then
				if lastState[key] ~= nil then
					changes[#changes + 1] = ("%s: %s -> %s"):format(key, lastState[key], value)
				end
				lastState[key] = value
			end
		end
		for _, name in ipairs(WATCHED) do
			local frame = _G[name]
			if type(frame) == "table" and hooked[frame] then
				Note(name, State(frame))
				lastShown[frame] = IsShownFlag(frame) -- also changes made without the hooked methods
			end
		end
		Note("selected chat tab", SelectedTab())
		if #changes > 0 then Log("now " .. table.concat(changes, "; ")) end
	end

	local function Describe(frame)
		local parts = {
			"shown " .. tostring(IsShownFlag(frame)),
			"visible " .. tostring(Read(frame, "IsVisible")),
			"alpha " .. Num(Read(frame, "GetAlpha")),
			"effective alpha " .. Num(Read(frame, "GetEffectiveAlpha")),
			"parent " .. Name(Read(frame, "GetParent")),
			"ignores parent alpha " .. tostring(Read(frame, "IsIgnoringParentAlpha")),
			"OnShow script " .. (Read(frame, "GetScript", "OnShow") and "yes" or "none"),
			"state " .. State(frame),
		}
		-- DynamicCam's hide-UI marks: it shows a frame again only if it saw it shown when hiding it.
		for _, key in ipairs(DYNAMICCAM_MARKS) do
			local ok, value = pcall(function() return frame[key] end)
			if ok and value ~= nil then
				parts[#parts + 1] = key .. " " .. (type(value) == "table" and Name(value) or tostring(value))
			end
		end
		return table.concat(parts, ", ")
	end

	function CA.ChatWatchSnapshot(key, reason)
		local store = CA.db and CA.db.chatButtons
		if not store then return end
		local snap = { time = date("%Y-%m-%d %H:%M:%S"), reason = reason, frames = {} }
		for _, name in ipairs(WATCHED) do
			local frame = _G[name]
			snap.frames[name] = type(frame) == "table" and Describe(frame) or "doesn't exist"
		end
		snap.selectedChatTab = SelectedTab()
		snap.uiParent = ("shown %s, alpha %s"):format(tostring(IsShownFlag(UIParent)), Num(Read(UIParent, "GetAlpha")))
		local hideModule = _G.ludius_UiHideModule -- DynamicCam's hide-UI state
		if type(hideModule) == "table" then
			snap.dynamicCamUiHidden = (hideModule.uiHiddenTime or 0) ~= 0
		end
		snap.cinematicMode = CA.active and true or false
		snap.flight = CA.FlightInfo and CA.FlightInfo() or nil
		store[key] = snap
	end

	-- PLAYER_LOGIN and later: hooks every watched frame that exists (load-on-demand ones next time).
	function CA.ChatWatchInstall()
		for _, name in ipairs(WATCHED) do
			local frame = _G[name]
			if type(frame) == "table" and type(frame.GetObjectType) == "function" then Hook(frame) end
		end
		Hook(UIParent) -- who shows the interface again during a flight
		if not ticker then
			ticker = C_Timer.NewTicker(0.25, function() pcall(Poll) end)
		end
	end

	-- /cinema watch off: the poll stops; the hooks stay but record nothing.
	function CA.ChatWatchStop()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		wipe(lastState) -- a later watch starts afresh instead of logging the changes since
	end

	function CA.ChatWatchControl(gained)
		if not Watching() then return end
		local ok, onTaxi = pcall(UnitOnTaxi, "player")
		Log(("player control %s (on a taxi: %s)"):format(gained and "back" or "lost",
			tostring(ok and not issecretvalue(onTaxi) and onTaxi)))
		if gained then
			C_Timer.After(3, function() CA.ChatWatchSnapshot("landing", "3 s after the player got control back") end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Events

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "CVAR_UPDATE" then
		if CA.active then CA.FollowCVars() end -- another addon switching icons back on (Better Fishing)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		CA.OnChannel(event == "UNIT_SPELLCAST_CHANNEL_STOP")
	elseif event == "ADDON_ACTION_BLOCKED" then
		if arg1 == ADDON then CA.OnActionBlocked(arg2) end
	elseif event == "PLAYER_CONTROL_LOST" then
		CA.ChatWatchControl(false)
		CA.OnControlLost()
	elseif event == "PLAYER_CONTROL_GAINED" then
		CA.ChatWatchControl(true)
		CA.OnControlGained()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		if CA.active then plateEvents.added = plateEvents.added + 1 end
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if CA.active then plateEvents.removed = plateEvents.removed + 1 end
	elseif event == "ADDON_LOADED" then
		if arg1 == ADDON then
			InitDB()
		elseif CA.active then
			-- A load-on-demand window (trainer, flight map...) may have just been created, still closed.
			LiftWindows(tostring(arg1) .. " loaded")
		end
	elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		UpdateHolderScale()
	elseif event == "PLAYER_LOGIN" then
		-- Settings left changed by a crash, or by a session that ended in cinematic mode.
		if (RestoreCVars("left over from the last session") or 0) > 0 then
			CA.Print("put back the names and text settings that were still hidden from your last session.")
		end
		CA.HookBags()
		CA.HookMailIcon()
		CA.ApplyBindings()
		if CA.db and CA.db.watch then CA.ChatWatchInstall() end
	elseif event == "UPDATE_BINDINGS" then
		CA.ApplyBindings()
		if CA.OnBindingsChanged then CA.OnBindingsChanged() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		returnToken = returnToken + 1 -- cancels a return still waiting from the previous fight
		ExitForCombat()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingApply then CA.ApplyBindings() end
		if not CA.active and next(pendingDrops) then DropAll() end
		ScheduleReturn()
		CA.FlightCheck(false) -- a landing that waited for the end of combat
		if CA.active and cvarsPending then
			ApplyCVars()
			KeepInWorld() -- the nameplate settings may have been the ones refused
		elseif not CA.active and CA.db and CA.db.hiddenCVars[CharacterKey()] then
			RestoreCVars("after combat")
		end
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- Logout, /reload or a loading screen: settings back before anything saves CVars.
		if cvarsHidden then RestoreCVars("leaving the world") end
		-- Moved windows stay moved: putting them back under a hidden UIParent would hide them from
		-- this addon's code. PLAYER_ENTERING_WORLD ends cinematic mode if the interface is back.
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- After a loading screen the interface may be back without its OnShow reaching us.
		if CA.active and Read(UIParent, "IsShown") then
			CA.SetActive(false)
		elseif CA.active then
			ApplyCVars()
			KeepInWorld()
		end
		CA.FlightCheck(true) -- a /reload or loading screen during a flight
		if arg1 or arg2 then -- login or /reload
			C_Timer.After(5, function()
				if #CA.OurKeys() == 0 then CA.Print("no key chosen yet. Type /cinema to pick one.") end
			end)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Slash commands

local function PrintHelp()
	CA.Print("/cinema: options (choose your key there). /cinema test: show the bars for 3 seconds. "
		.. "/cinema debug: save what is on screen, for troubleshooting. "
		.. "/cinema watch: also save it in every cinematic mode, and log who shows or hides the buttons "
		.. "beside the chat (on or off, saved). /cinema chat: save the state of those buttons.")
	CA.Print("Cinematic mode itself only comes from your key: the key runs Blizzard's own Toggle UI, "
		.. "which an addon command can't run safely.")
end

-- /cinema watch [on|off]: the diagnostics that run on their own (option watch).
local function SetWatch(arg)
	if not CA.db then return end
	local on
	if arg == "on" then
		on = true
	elseif arg == "off" then
		on = false
	else
		on = not CA.db.watch
	end
	CA.db.watch = on
	if on then
		CA.ChatWatchInstall()
		CA.Print("diagnostics on: a record of what is on screen 1 second into every cinematic mode, and a log "
			.. "of the buttons beside the chat. They go into the saved variables (CinematicAzerothDB) on logout "
			.. "or /reload. /cinema watch again turns them off.")
	else
		CA.ChatWatchStop()
		CA.Print("diagnostics off.")
	end
end

SLASH_CINEMATICAZEROTH1 = "/cinema"
SLASH_CINEMATICAZEROTH2 = "/cinematicazeroth"
SlashCmdList.CINEMATICAZEROTH = function(msg)
	local command, arg = (msg or ""):match("^%s*(%S*)%s*(%S*)")
	command, arg = (command or ""):lower(), (arg or ""):lower()
	if command == "test" then
		CA.SetPreview(true, 3)
		CA.Print("showing the bars for 3 seconds.")
	elseif command == "debug" then
		CA.Snapshot("manual", "/cinema debug")
		local keys = CA.OurKeys()
		if #keys == 0 then
			CA.Print("no key chosen yet.")
		end
		for _, key in ipairs(keys) do
			local action = GetBindingAction(key, true)
			CA.Print(("key %s runs %s%s."):format(GetBindingText(key), tostring(action),
				action == "TOGGLEUI" and " (Blizzard's Toggle UI, as it should)" or " (expected TOGGLEUI)"))
		end
		CA.Print("saved in CinematicAzerothDB.snapshots.manual, written to disk on logout or /reload. "
			.. "With /cinema watch on, one is also taken in every cinematic mode (snapshots.cinematic).")
	elseif command == "watch" then
		SetWatch(arg)
	elseif command == "chat" then
		if CA.db and CA.db.watch then CA.ChatWatchInstall() end -- frames created since login
		CA.ChatWatchSnapshot("snapshot", "/cinema chat")
		CA.Print("chat buttons saved. Type /reload so they are written to disk.")
	elseif command == "help" then
		PrintHelp()
	elseif CA.OpenOptions then
		CA.OpenOptions()
	else
		PrintHelp()
	end
end
