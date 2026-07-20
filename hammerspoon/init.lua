-- -- Helper: get screen by position
-- function getScreenByIndex(index)
--     local screens = hs.screen.allScreens()
--     table.sort(screens, function(a, b)
--         return a:frame().x < b:frame().x
--     end)
--     return screens[index] or hs.screen.primaryScreen()
-- end

-- -- Helper: move and resize window
-- function moveAndResize(appName, screen, positionFn)
--     local app = hs.appfinder.appFromName(appName)
--     if app then
--         local win = app:mainWindow()
--         if win and screen then
--             win:moveToScreen(screen)
--             positionFn(win)
--         end
--     end
-- end

-- function startWorkflow()
--     local screen1 = getScreenByIndex(1)
--     local screen2 = getScreenByIndex(2)
--     local screen3 = getScreenByIndex(3)
--     local screen4 = getScreenByIndex(4)

--     -- Quit Chrome if running
--     local chrome = hs.application.find("Google Chrome")
--     if chrome then chrome:kill() end

--     -- Open apps and files
--     hs.execute([[open -a "Visual Studio Code" "/Users/ianburke/Library/Mobile Documents/iCloud~md~obsidian/Documents/2nd Brain/hi.md"]])
--     hs.execute([[open -a "Kiro" "/Users/ianburke/Documents/GitHub/shopify_projects/shop-test-7"]])
--     hs.execute([[open "https://open.spotify.com/playlist/37i9dQZF1DX5trt9i14X7j?si=3be539fccbf64985"]])
--     hs.application.launchOrFocus("Spiffy")
    
    
--     -- Open specific Chrome tabs
--     local chromeTabs = {
--         "https://admin.shopify.com/store/parallax-variant-manager-test-store/apps/parallax-variant-editor-dev/",
--         "https://parallax-variant-manager-test-store.myshopify.com/collections/all",
--         "https://www.upwork.com/ab/messages/rooms/room_3797a1ef903ec4072b0e8e3039a022ef?sidebar=true"
--     }

--     for _, url in ipairs(chromeTabs) do
--         hs.execute([[open -na "Google Chrome" --args --new-tab "]] .. url .. [["]])
--     end

--     -- Window positioning after launch delay
--     hs.timer.doAfter(4, function()
--         moveAndResize("Visual Studio Code", screen1, function(win) win:maximize() end)
--         moveAndResize("Google Chrome", screen2, function(win) win:maximize() end)
--         moveAndResize("Kiro", screen1, function(win) end)
--         moveAndResize("Spotify", screen3, function(win) win:maximize() end)
--         moveAndResize("Spiffy", screen4, function(win) win:maximize() end)

--         local spiffy = hs.appfinder.appFromName("Spiffy")
--         if spiffy then spiffy:activate() end
--     end)
-- end

-- hs.hotkey.bind({"cmd", "alt", "ctrl"}, "K", function()
--     startWorkflow()
-- end)

-- hs.urlevent.bind("startWorkflow", function()
--     startWorkflow()
-- end)






-- local appName = "Google Chrome"  -- change to any app you want

-- hs.hotkey.bind({"cmd", "alt"}, "C", function()
--   local app = hs.application.find(appName)
--   if not app then return end

--   local win = hs.window.focusedWindow()
--   if not win then return end

--   if win:application():name() ~= appName then
--     app:activate()
--   else
--     local windows = app:allWindows()
--     if #windows <= 1 then return end

--     local current = hs.fnutils.indexOf(windows, win)
--     local nextWin = windows[(current % #windows) + 1]
--     if nextWin then nextWin:focus() end
--   end
-- end)

-- -- ============================================
-- -- Universal Window Cycler
-- -- Hyper+Tab cycles through windows of focused app
-- -- Works with ANY app - no need to configure individually
-- -- ============================================

-- hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, "enter", function()
--   local app = hs.application.frontmostApplication()
--   if not app then return end
  
--   local windows = app:allWindows()
--   windows = hs.fnutils.filter(windows, function(win)
--     return win:isStandard() and not win:isMinimized()
--   end)
  
--   if #windows <= 1 then
--     hs.alert.show(app:name() .. " - 1 window", 0.5)
--     return
--   end
  
--   local currentWin = hs.window.focusedWindow()
--   local currentIndex = 1
  
--   for i, win in ipairs(windows) do
--     if win:id() == currentWin:id() then
--       currentIndex = i
--       break
--     end
--   end
  
--   local nextIndex = (currentIndex % #windows) + 1
--   windows[nextIndex]:focus()
--   hs.alert.show(app:name() .. " (" .. nextIndex .. "/" .. #windows .. ")", 0.3)
-- end)

-- ============================================
-- SMART APP SWITCHER (Improved)
-- Hyper+Key focuses app. Press again to cycle windows.
-- Add your apps here: [Key] = "App Name"
-- ============================================

local appShortcuts = {
  ["V"] = "Google Chrome",
  -- Add more: ["Key"] = "App Name",
}

local lastSwitch = {app = nil, time = 0}
local lastFocusedWindowId = {}  -- appName -> window id

local function appsNamed(appName)
    local apps = {}
    for _, app in ipairs(hs.application.runningApplications()) do
        if app:name() == appName then
            table.insert(apps, app)
        end
    end
    return apps
end

local function windowsForAppName(appName)
    local windows = {}
    for _, app in ipairs(appsNamed(appName)) do
        for _, win in ipairs(app:allWindows()) do
            if win:isStandard() and not win:isMinimized() then
                table.insert(windows, win)
            end
        end
    end

    table.sort(windows, function(a, b)
        local af = a:frame()
        local bf = b:frame()
        if af.x ~= bf.x then return af.x < bf.x end
        if af.y ~= bf.y then return af.y < bf.y end
        return a:id() < b:id()
    end)

    return windows
end

local function focusFirstAppWindow(appName)
    local windows = windowsForAppName(appName)
    if #windows > 0 then
        local rememberedId = lastFocusedWindowId[appName]
        if rememberedId then
            for _, win in ipairs(windows) do
                if win:id() == rememberedId then
                    win:focus()
                    return true
                end
            end
        end
        windows[1]:focus()
        return true
    end

    local apps = appsNamed(appName)
    if #apps > 0 then
        apps[1]:activate()
        return true
    end

    return false
end

local function newCycleOrFocus(appName)
    local apps = appsNamed(appName)
    if #apps == 0 then
        hs.application.launchOrFocus(appName)
        return
    end

    local frontApp = hs.application.frontmostApplication()
    local now = hs.timer.secondsSinceEpoch()

    -- If the app is already at the front and the last switch was recent, cycle windows
    if frontApp and frontApp:name() == appName and (now - lastSwitch.time) < 1.0 and lastSwitch.app == appName then
        local windows = windowsForAppName(appName)
        if #windows > 1 then
            local currentWin = hs.window.focusedWindow()
            local currentIndex = 0
            if currentWin then
                for i, win in ipairs(windows) do
                    if win:id() == currentWin:id() then
                        currentIndex = i
                        break
                    end
                end
            end

            local nextIndex = (currentIndex % #windows) + 1
            windows[nextIndex]:focus()
            hs.alert.show(appName .. " (" .. nextIndex .. "/" .. #windows .. ")", 0.3)
        else
            hs.alert.show(appName .. " - 1 window", 0.5)
        end
    else
        -- Otherwise, just bring the app to the front
        focusFirstAppWindow(appName)
    end

    -- Record the switch
    lastSwitch = {app = appName, time = now}
end


-- Bind all the app shortcuts
for key, appName in pairs(appShortcuts) do
  hs.hotkey.bind({"cmd", "alt", "ctrl", "shift"}, key, function()
    newCycleOrFocus(appName)
  end)
end

-- Remember which window was last focused for each shortcut app, so
-- switching away and back returns to that window instead of whichever
-- one sorts first by screen position.
local shortcutAppNames = {}
for _, appName in pairs(appShortcuts) do
    shortcutAppNames[appName] = true
end

local appWindowMemoryWatcher = hs.window.filter.new(function(win)
    local app = win:application()
    return app ~= nil and shortcutAppNames[app:name()] == true
end)
appWindowMemoryWatcher:subscribe(hs.window.filter.windowFocused, function(win)
    local appName = win:application():name()
    lastFocusedWindowId[appName] = win:id()
end)

hs.alert.show("Smart switcher loaded ✓", 1)

-- ============================================
-- EVENING SESSION STATE CHECK
-- After 6pm: 90-min timer starts on first Claude activation.
-- When it fires: say out loud what you're working on and what you're shipping.
-- If you can't say it clearly, close the laptop.
-- ============================================

local sessionCheckTimer = nil

local function startSessionTimer()
    if sessionCheckTimer then return end  -- timer already running, don't reset it

    sessionCheckTimer = hs.timer.doAfter(90 * 60, function()
        hs.notify.new({
            title = "Session State Check",
            informativeText = "Say out loud: 'I'm working on X and tonight I'm shipping Y.' If you can't say it clearly, close the laptop.",
            soundName = "Ping"
        }):send()
        sessionCheckTimer = nil
    end)

    hs.alert.show("Session check armed (90 min) ⏱", 1.5)
end

local claudeSessionWatcher = hs.application.watcher.new(function(name, event, app)
    if name ~= "Claude" and name ~= "Claude Code" then return end

    if event == hs.application.watcher.activated then
        local hour = tonumber(os.date("%H"))
        if hour >= 18 then
            startSessionTimer()
        end
    end
end)

claudeSessionWatcher:start()

-- ============================================
-- DJI MIC BUTTON — NOTES FOR NEXT TIME
--
-- The DJI wireless mic link button fires a systemDefined event (type 14),
-- NOT a standard keyDown. Intercept with:
--   hs.eventtap.new({hs.eventtap.event.types.systemDefined}, fn)
--   local data = event:systemKey()
--
-- Key name is "SOUND_UP" — NOT "VOLUME_UP" (wrong assumption, costs you an hour).
--
-- A single button press sends the full sequence immediately:
--   SOUND_UP down → SOUND_UP up → SOUND_DOWN down → SOUND_DOWN up
-- The SOUND_UP + SOUND_DOWN pairing distinguishes DJI from the MacBook
-- keyboard, which only ever sends SOUND_UP.
--
-- HOLD DOES NOT WORK. Physically holding the button disconnects the mic.
-- Only tap-based interactions (single tap, double tap) are viable.
--
-- MacBook keyboard conflict: consuming SOUND_UP also swallows the real
-- volume key. Fix: consume speculatively, re-emit via newSystemKeyEvent
-- if SOUND_DOWN doesn't follow within ~100ms. Re-emit guard pitfall:
-- set the flag BEFORE posting the synthetic event and reset it INSIDE
-- the tap callback — post() is async so resetting immediately after
-- post() means the flag is already false when the event comes back through.
--
-- For device-specific isolation without the re-emit complexity,
-- use Karabiner-Elements to filter by USB vendor/product ID and remap
-- only the DJI's events to a synthetic keycode first.
-- ============================================
