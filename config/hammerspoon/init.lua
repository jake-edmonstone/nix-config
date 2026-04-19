---@diagnostic disable: undefined-global

hs.window.animationDuration = 0

-- Right Option is remapped to F19 by nix-darwin's system.keyboard.userKeyMapping.
-- Press-and-hold F19 to enter the modal; release exits it. Keys bound via
-- hyper:bind() below fire while F19 is held.
local hyper = hs.hotkey.modal.new()
hs.hotkey.bind({}, "F19", function()
	hyper:enter()
end, function()
	hyper:exit()
end)

local pendingTimer = nil
local pendingPoll = nil

local POLL_INTERVAL = 0.1 -- 100ms between readiness checks
local POLL_TIMEOUT = 10 -- give up after 10 seconds

-- App registry: key = hotkey letter, value = bundle ID
local apps = {
	t = "com.mitchellh.ghostty",
	s = "com.tinyspeck.slackmacgap",
	b = "com.apple.Safari",
	e = "com.microsoft.Outlook",
	m = "com.apple.MobileSMS",
	a = "com.openai.chat",
	p = "info.sioyek.sioyek", -- Sioyek
	v = "com.microsoft.teams2", -- MS Teams
	f = "net.ankiweb.dtop", -- Anki (nixpkgs anki-bin; .dmg-distributed Anki uses net.ankiweb.launcher)
	c = "com.apple.Safari.WebApp.DDBDA633-CD00-46AB-A16B-1EAB56EA281F", -- Confluence
	j = "com.apple.Safari.WebApp.89AA9B93-DC53-4A4D-947E-794889FB7A06", -- Jira
	g = "com.apple.Safari.WebApp.841C2873-A061-48FA-82F5-9C6C29EE33B7", -- GitHub
}

-- Split views: key = hotkey letter, value = {left, right, ratio}
local splits = {
	n = { left = "com.mitchellh.ghostty", right = "com.kagi.kagimacOS", ratio = 0.6 },
}

local function getUsableWindow(app)
	local win = app:mainWindow()
	if win then
		return win
	end
	for _, w in ipairs(app:allWindows()) do
		if w:isStandard() then
			return w
		end
	end
	return nil
end

local function hideOthersExcept(...)
	local keep = {}
	for _, id in ipairs({ ... }) do
		keep[id] = true
	end
	for _, a in ipairs(hs.application.runningApplications()) do
		local bid = a:bundleID()
		if bid and not keep[bid] and a:kind() == 1 and not a:isHidden() then
			a:hide()
		end
	end
end

-- Cancel any in-flight polling or deferred timers
local function cancelPending()
	if pendingTimer then
		pendingTimer:stop()
		pendingTimer = nil
	end
	if pendingPoll then
		pendingPoll:stop()
		pendingPoll = nil
	end
end

-- Ensure an app is running; launch it if not. Returns true if already windowed.
local function ensureRunning(bundleID)
	local app = hs.application.get(bundleID)
	-- isRunning() is needed: get() can return stale objects for dead processes
	if app and app:isRunning() then
		return true
	end
	if not hs.application.launchOrFocusByBundleID(bundleID) then
		hs.printf("no app found for bundle ID %s", bundleID)
	end
	return false
end

-- Poll until a bundle ID has a usable window, then return the app via callback.
-- Returns the timer so the caller can cancel it.
local function waitForWindow(bundleID, callback)
	local start = hs.timer.secondsSinceEpoch()
	return hs.timer.waitUntil(function()
		if hs.timer.secondsSinceEpoch() - start > POLL_TIMEOUT then
			return true
		end
		local app = hs.application.get(bundleID)
		return app and app:isRunning() and getUsableWindow(app) ~= nil
	end, function()
		local app = hs.application.get(bundleID)
		if app and app:isRunning() and getUsableWindow(app) then
			callback(app)
		end
	end, POLL_INTERVAL)
end

-- Focus a single app, maximize it, hide everything else
local function switchTo(bundleID)
	cancelPending()

	local function apply(app)
		app:activate(true)
		local win = getUsableWindow(app)
		if win then
			win:maximize()
		end
		hideOthersExcept(bundleID)
	end

	if ensureRunning(bundleID) then
		local app = hs.application.get(bundleID)
		apply(app)
	else
		hideOthersExcept(bundleID)
		pendingPoll = waitForWindow(bundleID, apply)
	end
end

-- Show two apps side by side, hide everything else
local function splitView(leftID, rightID, ratio)
	cancelPending()
	ratio = ratio or 0.5

	local leftReady = ensureRunning(leftID)
	local rightReady = ensureRunning(rightID)

	-- Pre-compute geometry outside polling loops
	local leftUnit = hs.geometry.rect(0, 0, ratio, 1)
	local rightUnit = hs.geometry.rect(ratio, 0, 1 - ratio, 1)

	local function layout()
		local leftApp = hs.application.get(leftID)
		local rightApp = hs.application.get(rightID)
		if not leftApp or not rightApp then
			return
		end

		leftApp:unhide()
		rightApp:unhide()
		leftApp:activate(true)
		rightApp:activate(true)
		hideOthersExcept(leftID, rightID)

		-- Poll until both windows are visible, then position them.
		-- moveToUnit uses each window's own screen and respects dock/menu bar.
		local layoutStart = hs.timer.secondsSinceEpoch()
		pendingTimer = hs.timer.waitUntil(function()
			if hs.timer.secondsSinceEpoch() - layoutStart > POLL_TIMEOUT then
				return true
			end
			if not leftApp:isRunning() or not rightApp:isRunning() then
				return true
			end
			local lwin = getUsableWindow(leftApp)
			local rwin = getUsableWindow(rightApp)
			return lwin and rwin and lwin:isVisible() and rwin:isVisible()
		end, function()
			pendingTimer = nil
			if not leftApp:isRunning() or not rightApp:isRunning() then
				return
			end
			local lwin = getUsableWindow(leftApp)
			local rwin = getUsableWindow(rightApp)
			if lwin then
				lwin:moveToUnit(leftUnit)
			end
			if rwin then
				rwin:moveToUnit(rightUnit)
			end
			leftApp:activate()
		end, 0.05)
	end

	if leftReady and rightReady then
		layout()
	else
		-- Poll until both apps have usable windows, then lay them out
		local start = hs.timer.secondsSinceEpoch()
		pendingPoll = hs.timer.waitUntil(function()
			if hs.timer.secondsSinceEpoch() - start > POLL_TIMEOUT then
				return true
			end
			local l = hs.application.get(leftID)
			local r = hs.application.get(rightID)
			return l
				and l:isRunning()
				and getUsableWindow(l) ~= nil
				and r
				and r:isRunning()
				and getUsableWindow(r) ~= nil
		end, function()
			pendingPoll = nil
			layout()
		end, POLL_INTERVAL)
	end
end

-- Bind single-app hotkeys
for key, bundleID in pairs(apps) do
	hyper:bind({}, key, function()
		switchTo(bundleID)
	end)
end

-- Bind split-view hotkeys
for key, split in pairs(splits) do
	hyper:bind({}, key, function()
		splitView(split.left, split.right, split.ratio)
	end)
end
