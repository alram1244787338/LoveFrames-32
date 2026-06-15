--[[
	Regression tests for frame docking system.
	Run with: lua tests/test_dock.lua
	Requires a minimal LOVE mock (provided inline).
]]

------------------------------------------------------------------------
-- 1. LOVE framework mock
------------------------------------------------------------------------

-- Mock mouse position (mutable for test control)
local mock_mx, mock_my = 0, 0

-- Helper: list directory entries using OS commands
local function list_dir(dir)
	local items = {}
	-- Try to use ls (works on macOS/Linux)
	local handle = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
	if handle then
		for line in handle:lines() do
			table.insert(items, line)
		end
		handle:close()
	end
	return items
end

-- Helper: check if path is a directory
local function is_dir(path)
	-- Try to cd into it; if it works, it's a directory
	local handle = io.popen('test -d "' .. path .. '" && echo "yes" 2>/dev/null')
	if handle then
		local result = handle:read("*l")
		handle:close()
		return result == "yes"
	end
	return false
end

love = {
	mouse = {
		getPosition = function() return mock_mx, mock_my end,
		getSystemCursor = function() return {} end,
		getCursor = function() return {} end,
		setCursor = function() end,
	},
	graphics = {
		newFont = function(size)
			return {
				getWidth = function() return 0 end,
				getHeight = function() return size or 12 end,
				setFilter = function() end,
			}
		end,
		newImage = function()
			return {
				setFilter = function() end,
				getWidth = function() return 0 end,
				getHeight = function() return 0 end,
			}
		end,
		getWidth = function() return 800 end,
		getHeight = function() return 600 end,
		getDimensions = function() return 800, 600 end,
		getFont = function() return nil end,
		getColor = function() return 1, 1, 1, 1 end,
		setColor = function() end,
		setFont = function() end,
	},
	keyboard = {
		setKeyRepeat = function() end,
		isDown = function() return false end,
	},
	timer = {
		getDelta = function() return 0.016 end,
		getFPS = function() return 60 end,
	},
	filesystem = {
		getDirectoryItems = function(dir)
			return list_dir(dir)
		end,
		getInfo = function(path)
			if is_dir(path) then
				return {type = "directory"}
			end
			-- Check if file exists
			local f = io.open(path, "r")
			if f then
				f:close()
				return {type = "file"}
			end
			return nil
		end,
	},
	_os = "Linux",
	_version = "11.4",
}

------------------------------------------------------------------------
-- 2. Load loveframes
------------------------------------------------------------------------

-- Adjust package path so require("loveframes") works
package.path = "../?.lua;../?/init.lua;" .. package.path

local loveframes = require("loveframes")

------------------------------------------------------------------------
-- 3. Test harness
------------------------------------------------------------------------

local pass_count, fail_count = 0, 0

local function assert_eq(name, got, expected)
	if got == expected then
		pass_count = pass_count + 1
	else
		fail_count = fail_count + 1
		io.write(string.format("  FAIL: %s  (got=%s, expected=%s)\n",
			name, tostring(got), tostring(expected)))
	end
end

local function assert_true(name, val)
	assert_eq(name, not not val, true)
end

local function assert_false(name, val)
	assert_eq(name, not not val, false)
end

local function assert_nil_or_false(name, val)
	if val == nil or val == false then
		pass_count = pass_count + 1
	else
		fail_count = fail_count + 1
		io.write(string.format("  FAIL: %s  (got=%s, expected false/nil)\n",
			name, tostring(val)))
	end
end

------------------------------------------------------------------------
-- 4. Helper: create a dockable frame at (x,y) with given size
------------------------------------------------------------------------

-- Remove all frames from base.children to avoid cross-test contamination
local function clear_frames()
	local base = loveframes.base
	local i = #base.children
	while i >= 1 do
		if base.children[i].type == "frame" then
			base.children[i]:Remove()
		end
		i = i - 1
	end
end

local function make_frame(x, y, w, h, dockable)
	local f = loveframes.Create("frame")
	f:SetPos(x, y)
	f:SetSize(w or 200, h or 150)
	f:SetDockable(dockable ~= false)
	-- Make sure it's parented to base so dock logic runs
	f.parent = loveframes.base
	return f
end

-- Simulate one update tick with mouse at (mx, my)
local function tick(mx, my, dt)
	mock_mx = mx or mock_mx
	mock_my = my or mock_my
	loveframes.update(dt or 0.016)
end

-- Put a frame into "dragging" state as if user grabbed its title bar
local function start_drag(f, mx, my)
	mock_mx = mx or (f.x + 10)
	mock_my = my or (f.y + 10)
	f.clickx = mock_mx - f.x
	f.clicky = mock_my - f.y
	f.dragging = true
	loveframes.dragobject = f
end

-- Release the drag
local function end_drag(f)
	f.dragging = false
	loveframes.dragobject = false
end

------------------------------------------------------------------------
-- 5. Tests
------------------------------------------------------------------------

print("=== Frame Dock Regression Tests ===\n")

------------------------------------------------------------------------
-- Test 1: OnDock callback fires for all 4 directions
------------------------------------------------------------------------
print("Test 1: OnDock callback fires for all 4 directions")

do
	clear_frames()

	local directions = {
		-- {label, start_x, start_y, snap_mouse_x, snap_mouse_y}
		-- For "top" dock: dragging frame's bottom zone must overlap target's top zone.
		-- Target top zone: y = 300 - 10 = 290, height = 10 → y range [290, 300]
		-- Dragging frame bottom zone: y = f.y + f.height, height = 10 → [f.y+150, f.y+160]
		-- We need f.y+150 ~= 290 → f.y ~= 140. Place dragging frame at y=135.
		{"top",    350, 135, 360, 145},
		-- For "bottom": dragging frame's top zone overlaps target's bottom zone.
		-- Target bottom zone: y = 300+150=450, height=10 → [450, 460]
		-- Dragging frame top zone: y = f.y - 10, height=10 → [f.y-10, f.y]
		-- Need f.y-10 ~= 450 → f.y ~= 460
		{"bottom", 350, 460, 360, 470},
		-- For "left": dragging frame's right zone overlaps target's left zone.
		-- Target left zone: x = 300-10=290, width=10 → [290, 300]
		-- Dragging frame right zone: x = f.x + f.width, width=10 → [f.x+200, f.x+210]
		-- Need f.x+200 ~= 290 → f.x ~= 90
		{"left",    90, 320, 100, 330},
		-- For "right": dragging frame's left zone overlaps target's right zone.
		-- Target right zone: x = 300+200=500, width=10 → [500, 510]
		-- Dragging frame left zone: x = f.x - 10, width=10 → [f.x-10, f.x]
		-- Need f.x-10 ~= 500 → f.x ~= 510
		{"right",  510, 320, 520, 330},
	}

	for _, d in ipairs(directions) do
		local dir, sx, sy, mx, my = d[1], d[2], d[3], d[4], d[5]

		-- Fresh target for each sub-test
		local tgt = make_frame(300, 300, 200, 150, true)
		local f = make_frame(sx, sy, 200, 150, true)

		local dock_called = false
		local dock_self, dock_target, dock_dir
		f.OnDock = function(s, t, direction)
			dock_called = true
			dock_self = s
			dock_target = t
			dock_dir = direction
		end

		start_drag(f, mx, my)
		tick(mx, my)

		assert_eq("OnDock fires for " .. dir, dock_called, true)
		assert_eq("OnDock direction for " .. dir, dock_dir, dir)
		assert_eq("OnDock self for " .. dir, dock_self, f)
		assert_eq("OnDock target for " .. dir, dock_target, tgt)

		end_drag(f)
		tgt:Remove()
		f:Remove()
	end
end

------------------------------------------------------------------------
-- Test 2: OnUndock callback fires and dockobject is cleared
------------------------------------------------------------------------
print("\nTest 2: OnUndock callback fires and dockobject is cleared")

do
	clear_frames()
	for _, dir in ipairs({"top", "bottom", "left", "right"}) do
		local tgt = make_frame(300, 300, 200, 150, true)
		local f = make_frame(300, 300, 200, 150, true)

		-- Manually set up docked state
		if dir == "top" then
			f.dockedtop = true
			f.topdockobject = tgt
			f.docky = 145
			f.y = tgt.y - f.height  -- snapped position
		elseif dir == "bottom" then
			f.dockedbottom = true
			f.bottomdockobject = tgt
			f.docky = 470
			f.y = tgt.y + tgt.height
		elseif dir == "left" then
			f.dockedleft = true
			f.leftdockobject = tgt
			f.dockx = 100
			f.x = tgt.x - f.width
		elseif dir == "right" then
			f.dockedright = true
			f.rightdockobject = tgt
			f.dockx = 520
			f.x = tgt.x + tgt.width
		end

		local undock_called = false
		local undock_self, undock_target, undock_dir
		f.OnUndock = function(s, t, direction)
			undock_called = true
			undock_self = s
			undock_target = t
			undock_dir = direction
		end

		start_drag(f, 300, 300)

		-- Move mouse far enough to trigger undock (>20px threshold)
		if dir == "top" or dir == "bottom" then
			tick(300, f.docky + 25)  -- vertical undock
		else
			tick(f.dockx + 25, 300)  -- horizontal undock
		end

		assert_eq("OnUndock fires for " .. dir, undock_called, true)
		assert_eq("OnUndock direction for " .. dir, undock_dir, dir)
		assert_eq("OnUndock self for " .. dir, undock_self, f)
		assert_eq("OnUndock target for " .. dir, undock_target, tgt)

		-- Verify dockobject reference is cleared
		if dir == "top" then
			assert_false("topdockobject cleared after undock", f.topdockobject)
			assert_false("dockedtop cleared after undock", f.dockedtop)
		elseif dir == "bottom" then
			assert_false("bottomdockobject cleared after undock", f.bottomdockobject)
			assert_false("dockedbottom cleared after undock", f.dockedbottom)
		elseif dir == "left" then
			assert_false("leftdockobject cleared after undock", f.leftdockobject)
			assert_false("dockedleft cleared after undock", f.dockedleft)
		elseif dir == "right" then
			assert_false("rightdockobject cleared after undock", f.rightdockobject)
			assert_false("dockedright cleared after undock", f.dockedright)
		end

		end_drag(f)
		tgt:Remove()
		f:Remove()
	end
end

------------------------------------------------------------------------
-- Test 3: GetDocked() and GetDockInfo() work correctly
------------------------------------------------------------------------
print("\nTest 3: GetDocked() and GetDockInfo()")

do
	clear_frames()
	local tgt = make_frame(300, 300, 200, 150, true)
	local f = make_frame(100, 300, 200, 150, true)

	-- Initially not docked
	assert_false("GetDocked() initially false", f:GetDocked())
	local info = f:GetDockInfo()
	assert_false("GetDockInfo().dockedleft initially false", info.dockedleft)
	assert_false("GetDockInfo().leftdockobject initially false", info.leftdockobject)

	-- Manually set docked state
	f.dockedleft = true
	f.leftdockobject = tgt

	assert_true("GetDocked() true after dock", f:GetDocked())
	info = f:GetDockInfo()
	assert_true("GetDockInfo().dockedleft true", info.dockedleft)
	assert_eq("GetDockInfo().leftdockobject is target", info.leftdockobject, tgt)
	assert_false("GetDockInfo().dockedright still false", info.dockedright)

	tgt:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 4: Non-dockable target does not trigger dock
------------------------------------------------------------------------
print("\nTest 4: Non-dockable target is ignored")

do
	clear_frames()
	local tgt = make_frame(300, 300, 200, 150, false)  -- NOT dockable
	local f = make_frame(90, 320, 200, 150, true)

	local dock_called = false
	f.OnDock = function() dock_called = true end

	start_drag(f, 100, 330)
	tick(100, 330)

	assert_false("OnDock NOT called for non-dockable target", dock_called)
	assert_false("frame not docked", f:GetDocked())

	end_drag(f)
	tgt:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 5: Non-dockable self does not dock
------------------------------------------------------------------------
print("\nTest 5: Non-dockable self does not dock")

do
	clear_frames()
	local tgt = make_frame(300, 300, 200, 150, true)
	local f = make_frame(90, 320, 200, 150, false)  -- self NOT dockable

	local dock_called = false
	f.OnDock = function() dock_called = true end

	start_drag(f, 100, 330)
	tick(100, 330)

	assert_false("OnDock NOT called when self is non-dockable", dock_called)

	end_drag(f)
	tgt:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 6: Re-dock to different frame after undock
------------------------------------------------------------------------
print("\nTest 6: Re-dock to different frame after undock")

do
	clear_frames()
	local tgt1 = make_frame(300, 300, 200, 150, true)
	local tgt2 = make_frame(300, 600, 200, 150, true)  -- second target below
	local f = make_frame(350, 460, 200, 150, true)

	local dock_log = {}
	f.OnDock = function(s, t, dir)
		table.insert(dock_log, {target = t, dir = dir})
	end
	local undock_log = {}
	f.OnUndock = function(s, t, dir)
		table.insert(undock_log, {target = t, dir = dir})
	end

	-- First: dock bottom to tgt1
	f.dockedbottom = true
	f.bottomdockobject = tgt1
	f.docky = 470
	f.y = tgt1.y + tgt1.height  -- 450

	start_drag(f, 360, 470)
	tick(360, 470)

	-- Now undock by moving mouse far away vertically
	tick(360, 500)  -- 500 > 470+20 = 490

	assert_eq("undock from tgt1 happened", #undock_log, 1)
	assert_eq("undock target was tgt1", undock_log[1].target, tgt1)
	assert_eq("undock direction was bottom", undock_log[1].dir, "bottom")
	assert_false("bottomdockobject cleared", f.bottomdockobject)

	-- Now move near tgt2's top zone to dock top
	-- tgt2 top zone: y = 600-10 = 590, height=10 → [590, 600]
	-- f bottom zone: y = f.y+150, height=10
	-- We need f.y ~= 440 for bottom zone to be at 590
	f.y = 440
	f.x = 350
	tick(360, 450)

	assert_true("docked to tgt2", f.dockedtop)
	assert_eq("topdockobject is tgt2", f.topdockobject, tgt2)
	assert_true("dock_log has entry", #dock_log >= 1)

	end_drag(f)
	tgt1:Remove()
	tgt2:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 7: Undock threshold is exactly 20px (not less)
------------------------------------------------------------------------
print("\nTest 7: Undock threshold boundary (20px)")

do
	clear_frames()
	local tgt = make_frame(300, 300, 200, 150, true)
	local f = make_frame(300, 150, 200, 150, true)

	-- Set up docked top state
	f.dockedtop = true
	f.topdockobject = tgt
	f.docky = 160
	f.y = tgt.y - f.height  -- 150

	local undock_called = false
	f.OnUndock = function() undock_called = true end

	start_drag(f, 310, 160)

	-- Move exactly 20px (should NOT undock, boundary is > 20)
	tick(310, 180)  -- 180 - 160 = 20
	assert_false("NOT undocked at exactly 20px", undock_called)

	-- Move 21px (should undock)
	tick(310, 181)  -- 181 - 160 = 21
	assert_true("undocked at 21px", undock_called)

	end_drag(f)
	tgt:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 8: dockx/docky reset to 0 on undock
------------------------------------------------------------------------
print("\nTest 8: dockx/docky reset on undock")

do
	clear_frames()
	local tgt = make_frame(300, 300, 200, 150, true)
	local f = make_frame(300, 150, 200, 150, true)

	f.dockedtop = true
	f.topdockobject = tgt
	f.docky = 160
	f.y = tgt.y - f.height

	start_drag(f, 310, 160)

	-- Trigger undock
	tick(310, 200)  -- 200 - 160 = 40 > 20

	assert_eq("docky reset to 0", f.docky, 0)

	-- Now test horizontal dock
	f.dockedtop = false
	f.topdockobject = false
	f.dockedleft = true
	f.leftdockobject = tgt
	f.dockx = 100
	f.x = tgt.x - f.width

	tick(100, 310)
	tick(140, 310)  -- 140 - 100 = 40 > 20

	assert_eq("dockx reset to 0", f.dockx, 0)

	end_drag(f)
	tgt:Remove()
	f:Remove()
end

------------------------------------------------------------------------
-- Test 9: OnDock/OnUndock symmetry - every dock has matching undock
------------------------------------------------------------------------
print("\nTest 9: OnDock/OnUndock symmetry across all directions")

do
	clear_frames()
	for _, dir in ipairs({"top", "bottom", "left", "right"}) do
		local tgt = make_frame(300, 300, 200, 150, true)
		local f

		if dir == "top" then
			f = make_frame(350, 135, 200, 150, true)
		elseif dir == "bottom" then
			f = make_frame(350, 460, 200, 150, true)
		elseif dir == "left" then
			f = make_frame(90, 320, 200, 150, true)
		elseif dir == "right" then
			f = make_frame(510, 320, 200, 150, true)
		end

		local dock_count = 0
		local undock_count = 0
		f.OnDock = function(s, t, d) dock_count = dock_count + 1 end
		f.OnUndock = function(s, t, d) undock_count = undock_count + 1 end

		-- Start drag near the target to trigger dock
		if dir == "top" then
			start_drag(f, 360, 145)
			tick(360, 145)
		elseif dir == "bottom" then
			start_drag(f, 360, 470)
			tick(360, 470)
		elseif dir == "left" then
			start_drag(f, 100, 330)
			tick(100, 330)
		elseif dir == "right" then
			start_drag(f, 520, 330)
			tick(520, 330)
		end

		assert_eq("dock happened for " .. dir, dock_count, 1)

		-- Now undock
		if dir == "top" or dir == "bottom" then
			tick(360, f.docky + 25)
		else
			tick(f.dockx + 25, 330)
		end

		assert_eq("undock happened for " .. dir, undock_count, 1)
		assert_eq("dock/undock symmetric for " .. dir, dock_count, undock_count)

		end_drag(f)
		tgt:Remove()
		f:Remove()
	end
end

------------------------------------------------------------------------
-- Summary
------------------------------------------------------------------------
print(string.format("\n=== Results: %d passed, %d failed ===",
	pass_count, fail_count))

if fail_count > 0 then
	os.exit(1)
else
	print("All tests passed!")
	os.exit(0)
end
