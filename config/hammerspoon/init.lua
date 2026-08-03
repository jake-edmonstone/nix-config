---@diagnostic disable: undefined-global

hs.window.animationDuration = 0

local log = hs.logger.new("hyper")

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

local POLL_INTERVAL = 0.05 -- only used while an app is launching or reopening
local POLL_TIMEOUT = 10 -- give up after 10 seconds

-- App registry: key = hotkey letter, value = bundle ID
local apps = {
	t = "com.mitchellh.ghostty",
	b = "com.apple.Safari",
	-- e = "com.microsoft.Outlook",
	e = "com.apple.mail",
	m = "com.apple.MobileSMS",
	a = "com.openai.codex",
	d = "com.hnc.Discord",
	p = "info.sioyek.sioyek", -- Sioyek
	v = "com.microsoft.teams2", -- MS Teams
	f = "net.ankiweb.dtop", -- Anki (nixpkgs anki-bin; .dmg-distributed Anki uses net.ankiweb.launcher)
	c = "com.apple.iCal", -- Calendar
	r = "com.apple.reminders", -- Reminders
	g = "com.apple.Safari.WebApp.84A4B68F-5EF2-4BD8-AE52-65B41EAFC9CA", -- GitHub
}

-- Split views: key = hotkey letter, value = {left, right, ratio}
local splits = {
	n = { left = "com.mitchellh.ghostty", right = "net.imput.helium", ratio = 0.6 },
}

local function getUsableWindow(app)
	local win = app:mainWindow()
	if win and win:isStandard() then
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
end

local function resolveTarget(bundleID)
	local app = hs.application.get(bundleID)
	-- isRunning() is needed: get() can return stale objects for dead processes
	if not app or not app:isRunning() then
		return nil
	end

	local win = getUsableWindow(app)
	if not win then
		return nil
	end

	return { app = app, win = win }
end

local function resolveTargets(bundleIDs)
	local targets = {}
	for _, bundleID in ipairs(bundleIDs) do
		local target = resolveTarget(bundleID)
		if not target then
			return nil
		end
		targets[bundleID] = target
	end
	return targets
end

local function runWhenReady(bundleIDs, callback)
	local targets = resolveTargets(bundleIDs)
	if targets then
		callback(targets)
		return
	end

	for _, bundleID in ipairs(bundleIDs) do
		if not resolveTarget(bundleID) and not hs.application.launchOrFocusByBundleID(bundleID) then
			log.ef("no app found for bundle ID %s", bundleID)
			return
		end
	end

	-- A running windowless app may create a window synchronously when reopened.
	targets = resolveTargets(bundleIDs)
	if targets then
		callback(targets)
		return
	end

	local deadline = hs.timer.absoluteTime() + POLL_TIMEOUT * 1000000000
	pendingTimer = hs.timer.waitUntil(function()
		targets = resolveTargets(bundleIDs)
		return targets ~= nil or hs.timer.absoluteTime() >= deadline
	end, function()
		pendingTimer = nil
		if targets then
			callback(targets)
		else
			log.ef("timed out waiting for %s", table.concat(bundleIDs, ", "))
		end
	end, POLL_INTERVAL)
end

-- Focus a single app, maximize it, hide everything else
local function switchTo(bundleID)
	cancelPending()

	runWhenReady({ bundleID }, function(targets)
		local target = targets[bundleID]
		if target.win:isMinimized() then
			target.win:unminimize()
		end
		if not target.app:activate(true) then
			log.ef("failed to activate %s", bundleID)
			return
		end
		target.win:maximize()
		hideOthersExcept(bundleID)
	end)
end

-- Show two apps side by side, hide everything else
local function splitView(leftID, rightID, ratio)
	cancelPending()
	ratio = ratio or 0.5
	local targetScreen = hs.screen.mainScreen()
	if not targetScreen then
		log.e("no screen available for split view")
		return
	end

	-- Pre-compute geometry outside polling loops
	local leftUnit = hs.geometry.rect(0, 0, ratio, 1)
	local rightUnit = hs.geometry.rect(ratio, 0, 1 - ratio, 1)

	runWhenReady({ leftID, rightID }, function(targets)
		local left = targets[leftID]
		local right = targets[rightID]

		left.app:unhide()
		right.app:unhide()
		if left.win:isMinimized() then
			left.win:unminimize()
		end
		if right.win:isMinimized() then
			right.win:unminimize()
		end
		if not left.app:activate(true) then
			log.ef("failed to activate %s", leftID)
			return
		end

		left.win:move(leftUnit, targetScreen)
		right.win:move(rightUnit, targetScreen)
		hideOthersExcept(leftID, rightID)
	end)
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
