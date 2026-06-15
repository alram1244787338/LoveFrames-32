#!/usr/bin/env lua
--[[
Standalone unit tests for the scroll wheel fixes.

Run with:  lua test_scroll_fixes.lua

These tests do NOT require LOVE2D.  They mock the minimal API surface
needed by loveframes' update and wheel-handling code and then exercise
the logic directly.
]]

--------------------------------------------------------------
-- Minimal mock framework
--------------------------------------------------------------
local function scandir(path)
	local items = {}
	local handle = io.popen('ls "' .. path .. '" 2>/dev/null')
	if handle then
		for line in handle:lines() do
			items[#items + 1] = line
		end
		handle:close()
	end
	return items
end

local love = {
	mouse = {
		_x = 0, _y = 0,
		getPosition = function() return love.mouse._x, love.mouse._y end,
		getSystemCursor = function() return {} end,
		getCursor = function() return nil end,
		setCursor = function() end,
	},
	graphics = {
		getWidth      = function() return 800 end,
		getHeight     = function() return 600 end,
		getDimensions = function() return 800, 600 end,
		newFont       = function() return {} end,
		setFont       = function() end,
		newImage      = function() return {setFilter = function() end, getWidth = function() return 16 end, getHeight = function() return 16 end} end,
	},
	timer = {
		getDelta = function() return 0.016 end,
		getTime  = function() return 1.0 end,
	},
	keyboard = {
		setKeyRepeat = function() end,
		isDown       = function() return false end,
	},
	filesystem = {
		getDirectoryItems = function(path) return scandir(path) end,
		getInfo = function(path)
			-- Check dir FIRST (on macOS io.open succeeds on directories too)
			local h = io.popen('test -d "' .. path .. '" && echo 1')
			if h then
				local r = h:read("*l"); h:close()
				if r == "1" then return {type = "directory"} end
			end
			local f = io.open(path)
			if f then f:close(); return {type = "file"} end
			return nil
		end,
	},
	_version = "11.4",
	_os = "Linux",
}

_G.love = love

--------------------------------------------------------------
-- Load loveframes
--------------------------------------------------------------
package.path = "./?.lua;./?/init.lua;" .. package.path
local ok, loveframes = pcall(require, "loveframes")
if not ok then
	print("SKIP: cannot load loveframes (" .. tostring(loveframes) .. ")")
	os.exit(0)
end

--------------------------------------------------------------
-- Test helpers
--------------------------------------------------------------
local passed = 0
local failed = 0
local tests  = {}

local function test(name, func)
	tests[#tests + 1] = {name = name, func = func}
end

local unpack = unpack or table.unpack

local function assert_eq(a, b, msg)
	if a ~= b then
		error(string.format("ASSERT FAILED: %s  (expected %s, got %s)",
			msg or "values differ", tostring(b), tostring(a)), 2)
	end
end

local function assert_true(v, msg)
	if not v then
		error("ASSERT FAILED: " .. (msg or "expected true, got " .. tostring(v)), 2)
	end
end

local function assert_false(v, msg)
	if v then
		error("ASSERT FAILED: " .. (msg or "expected false, got " .. tostring(v)), 2)
	end
end

local function runframe()
	loveframes.update(0.016)
end

local function setmouse(x, y)
	love.mouse._x = x
	love.mouse._y = y
	-- hoverobject is set from the PREVIOUS frame's collisions,
	-- so we need two frames for the hover state to fully propagate.
	runframe()
	runframe()
end

--------------------------------------------------------------
-- Setup
--------------------------------------------------------------
loveframes.RemoveAll()
loveframes.SetState("none")

local function make_frame_with_columnlist(name, fx, fy, fw, fh, nrows, ncols)
	local frame = loveframes.Create("frame")
	frame:SetName(name)
	frame:SetSize(fw, fh)
	frame:SetPos(fx, fy)

	local cl = loveframes.Create("columnlist", frame)
	cl:SetPos(5, 30)
	cl:SetSize(fw - 10, fh - 35)
	for c = 1, (ncols or 2) do
		cl:AddColumn("Col" .. c)
	end
	for r = 1, (nrows or 20) do
		local args = {}
		for c = 1, (ncols or 2) do
			args[c] = "R" .. r .. "C" .. c
		end
		cl:AddRow(unpack(args))
	end
	return frame, cl
end

local function make_frame_with_list(name, fx, fy, fw, fh, nitems)
	local frame = loveframes.Create("frame")
	frame:SetName(name)
	frame:SetSize(fw, fh)
	frame:SetPos(fx, fy)

	local lst = loveframes.Create("list", frame)
	lst:SetPos(5, 30)
	lst:SetSize(fw - 10, fh - 35)
	lst:SetPadding(2)
	lst:SetSpacing(2)
	for i = 1, (nitems or 20) do
		local btn = loveframes.Create("button")
		btn:SetText("Item " .. i)
		btn:SetWidth(fw - 40)
		lst:AddItem(btn)
	end
	return frame, lst
end

-- Let things stabilize
runframe()
runframe()

--------------------------------------------------------------
-- Test 1: IsTopList — object under cursor
--------------------------------------------------------------
test("IsTopList: object under cursor returns true", function()
	local frame, cl = make_frame_with_columnlist("T1", 10, 10, 200, 200, 20)
	runframe()
	runframe()

	local area = cl.internals[1]  -- columnlistarea
	setmouse(50, 80)
	runframe()

	assert_true(area:IsTopList(), "columnlistarea should be top list when mouse is over it")
end)

test("IsTopList: object NOT under cursor returns false", function()
	local frame, cl = make_frame_with_columnlist("T1b", 10, 10, 200, 200, 20)
	runframe()
	runframe()

	local area = cl.internals[1]
	setmouse(700, 500)
	runframe()

	assert_false(area:IsTopList(), "columnlistarea should NOT be top list when mouse is elsewhere")
end)

--------------------------------------------------------------
-- Test 2: Overlapping frames — only front scrolls
--------------------------------------------------------------
test("Overlapping: front frame's list is top, back frame's list is not", function()
	local fA, clA = make_frame_with_columnlist("Back", 100, 100, 200, 200, 20)
	local fB, clB = make_frame_with_columnlist("Front", 150, 120, 200, 200, 20)
	runframe()
	runframe()

	setmouse(200, 180)
	runframe()

	local areaA = clA.internals[1]
	local areaB = clB.internals[1]

	assert_false(areaA:IsTopList(), "back frame's list should NOT be top in overlap area")
	assert_true(areaB:IsTopList(),  "front frame's list should be top in overlap area")
end)

--------------------------------------------------------------
-- Test 3: MakeTop not called from wheelmoved
--------------------------------------------------------------
test("MakeTop: scrolling does NOT change frame z-order", function()
	local fA = loveframes.Create("frame")
	fA:SetName("FrameA_scroll")
	fA:SetSize(200, 200)
	fA:SetPos(50, 50)

	local fB = loveframes.Create("frame")
	fB:SetName("FrameB_scroll")
	fB:SetSize(200, 200)
	fB:SetPos(100, 80)

	runframe()
	runframe()

	local base = loveframes.base
	local bchildren = base.children

	-- Click fA to bring it to front
	setmouse(80, 120)
	runframe()
	loveframes.mousepressed(80, 120, 1)
	loveframes.mousereleased(80, 120, 1)
	runframe()
	assert_eq(bchildren[#bchildren], fA, "fA should be topmost after click")

	-- Click fB to bring it to front (use a position ONLY in fB, not in fA)
	-- fA covers x:50-249, fB covers x:100-299. x=260 is only in fB.
	setmouse(260, 200)
	loveframes.mousepressed(260, 200, 1)
	loveframes.mousereleased(260, 200, 1)
	runframe()
	assert_eq(bchildren[#bchildren], fB, "fB should be topmost after clicking it")

	-- Scroll over a position ONLY in fA (fA is behind fB)
	-- x=60 is only in fA (fA:50-249, fB:100-299)
	setmouse(60, 120)
	loveframes.wheelmoved(0, -3)
	runframe()

	-- fB should STILL be topmost
	assert_eq(bchildren[#bchildren], fB, "fB should still be topmost after scroll (no MakeTop on wheel)")
end)

--------------------------------------------------------------
-- Test 4: Scroll direction — columnlistarea with both bars
--------------------------------------------------------------
test("Scroll direction: vbar uses y, hbar uses x", function()
	local frame = loveframes.Create("frame")
	frame:SetName("T4_bothbars")
	frame:SetSize(200, 200)
	frame:SetPos(400, 10)

	local cl = loveframes.Create("columnlist", frame)
	cl:SetPos(5, 30)
	cl:SetSize(190, 165)
	cl:AddColumn("WideCol1")
	cl:AddColumn("WideCol2")
	cl:AddColumn("WideCol3")
	cl:SetColumnWidth(1, 200)
	cl:SetColumnWidth(2, 200)
	cl:SetColumnWidth(3, 200)
	cl:PositionColumns()
	-- Use non-dt scrolling for predictable test values
	cl:SetDTScrolling(false)
	cl:SetMouseWheelScrollAmount(50)
	cl.internals[1]:CalculateSize()
	cl.internals[1]:RedoLayout()
	for i = 1, 30 do
		cl:AddRow("R" .. i .. "C1", "R" .. i .. "C2", "R" .. i .. "C3")
	end

	runframe()
	runframe()

	local area = cl.internals[1]
	assert_true(area.vbar, "vertical scrollbar should exist")
	assert_true(area.hbar, "horizontal scrollbar should exist")

	setmouse(450, 80)
	runframe()
	assert_true(area:IsTopList(), "area should be top list")

	local vbody = area:GetVerticalScrollBody()
	local hbody = area:GetHorizontalScrollBody()
	assert_true(vbody ~= false, "vbody should exist")
	assert_true(hbody ~= false, "hbody should exist")

	local vbar = vbody:GetScrollBar()
	local hbar = hbody:GetScrollBar()

	-- y wheel only
	local hBefore = hbar.staticx
	loveframes.wheelmoved(0, -5)
	runframe()
	assert_eq(hbar.staticx, hBefore, "hbar should NOT change after y-only wheel")

	-- x wheel only (positive to scroll right from position 0)
	local vBefore = vbar.staticy
	loveframes.wheelmoved(5, 0)
	runframe()
	assert_eq(vbar.staticy, vBefore, "vbar should NOT change after x-only wheel")
	assert_true(hbar.staticx ~= hBefore, "hbar SHOULD change after x wheel")
end)

--------------------------------------------------------------
-- Test 5: List bounds check
--------------------------------------------------------------
test("List: scroll only when mouse is within bounds", function()
	local frame, lst = make_frame_with_list("T5_list", 500, 300, 200, 200, 30)
	runframe()
	runframe()

	assert_true(lst.vbar, "list should have vertical scrollbar")

	local vbody = lst:GetVerticalScrollBody()
	assert_true(vbody ~= false, "vbody should exist for list")
	local vbar = vbody:GetScrollBar()

	-- Mouse INSIDE
	setmouse(550, 380)
	runframe()
	local vBefore = vbar.staticy
	loveframes.wheelmoved(0, -5)
	runframe()
	assert_true(vbar.staticy ~= vBefore, "list should scroll when mouse is inside")

	-- Mouse OUTSIDE
	setmouse(10, 10)
	runframe()
	local vBefore2 = vbar.staticy
	loveframes.wheelmoved(0, -5)
	runframe()
	assert_eq(vbar.staticy, vBefore2, "list should NOT scroll when mouse is outside")
end)

--------------------------------------------------------------
-- Test 6: hbar-only columnlist
--------------------------------------------------------------
test("hbar-only: y wheel does not move horizontal bar", function()
	local frame = loveframes.Create("frame")
	frame:SetName("T6_hbar")
	frame:SetSize(200, 200)
	frame:SetPos(600, 300)

	local cl = loveframes.Create("columnlist", frame)
	cl:SetPos(5, 30)
	cl:SetSize(190, 165)
	cl:AddColumn("Wide1")
	cl:AddColumn("Wide2")
	cl:SetColumnWidth(1, 250)
	cl:SetColumnWidth(2, 250)
	cl:PositionColumns()
	-- Use non-dt scrolling for predictable test values
	cl:SetDTScrolling(false)
	cl:SetMouseWheelScrollAmount(50)
	cl.internals[1]:CalculateSize()
	cl.internals[1]:RedoLayout()
	cl:AddRow("a", "b")
	cl:AddRow("c", "d")

	runframe()
	runframe()

	local area = cl.internals[1]
	assert_false(area.vbar, "vbar should NOT exist (few rows)")
	assert_true(area.hbar,  "hbar should exist (wide columns)")

	local hbody = area:GetHorizontalScrollBody()
	assert_true(hbody ~= false, "hbody should exist")
	local hbar = hbody:GetScrollBar()

	setmouse(650, 380)
	runframe()

	local hBefore = hbar.staticx
	loveframes.wheelmoved(0, -5)
	runframe()
	assert_eq(hbar.staticx, hBefore, "y wheel should not move hbar")

	-- Positive x to scroll right from position 0
	loveframes.wheelmoved(5, 0)
	runframe()
	assert_true(hbar.staticx ~= hBefore, "x wheel should move hbar")
end)

--------------------------------------------------------------
-- Run all tests
--------------------------------------------------------------
print(string.rep("=", 60))
print("Scroll wheel regression tests")
print(string.rep("=", 60))

for _, t in ipairs(tests) do
	io.write("  " .. t.name .. " ... ")
	local ok2, err = pcall(t.func)
	if ok2 then
		passed = passed + 1
		print("PASS")
	else
		failed = failed + 1
		print("FAIL: " .. tostring(err))
	end
end

print(string.rep("-", 60))
print(string.format("Results: %d passed, %d failed, %d total",
	passed, failed, passed + failed))

if failed > 0 then
	os.exit(1)
else
	print("All tests passed!")
end
