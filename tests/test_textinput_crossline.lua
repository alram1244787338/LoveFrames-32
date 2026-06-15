#!/usr/bin/env lua
-- Regression tests for textinput cross-line editing
-- Run: lua tests/test_textinput_crossline.lua

------------------------------------------------------------
-- Mock LOVE framework globals
------------------------------------------------------------

local mock_time = 0

love = {
	timer = {
		getTime = function() return mock_time end,
		getDelta = function() return 0.016 end,
	},
	graphics = {
		newFont = function(size)
			return {
				getHeight = function() return size or 12 end,
				getWidth = function(self, str)
					if type(self) == "string" then
						-- called as font:getWidth(str) where self is the string
						return (#self) * 8
					end
					return (str and #str or 0) * 8
				end,
			}
		end,
		setFont = function() end,
		getFont = function()
			return love.graphics.newFont(12)
		end,
	},
	keyboard = {
		isDown = function() return false end,
		setKeyRepeat = function() end,
	},
	system = {
		getClipboardText = function() return "" end,
		setClipboardText = function() end,
	},
}

------------------------------------------------------------
-- Minimal loveframes environment
------------------------------------------------------------

-- Load the utf8 library
local utf8lib = require("loveframes.third-party.utf8"):init()

-- Load middleclass
local classlib = require("loveframes.third-party.middleclass")

local loveframes = {}
loveframes.utf8 = utf8lib
loveframes.class = classlib
loveframes.objects = {}
loveframes.state = "none"
loveframes.inputobject = false
loveframes.base = { type = "base", state = "none" }
loveframes.basicfont = love.graphics.newFont(12)

-- BoundingBox stub (not needed for key tests)
function loveframes.BoundingBox() return false end

-- SplitString
function loveframes.SplitString(str, pat)
	local t = {}
	for s in string.gmatch(str, "([^" .. pat .. "]+)") do
		table.insert(t, s)
	end
	if #t == 0 then table.insert(t, "") end
	return t
end

-- IsCtrlDown stub
function loveframes.IsCtrlDown() return false end

-- TableHasValue
function loveframes.TableHasValue(tbl, val)
	for _, v in ipairs(tbl) do
		if v == val then return true end
	end
	return false
end

-- NewObject: create a class, optionally inheriting from base
function loveframes.NewObject(id, name, inherit_from_base)
	local object
	if inherit_from_base then
		-- Create a minimal base class if not already defined
		if not loveframes.objects["base"] then
			loveframes.objects["base"] = classlib("loveframes_object_base")
			loveframes.objects["base"].static.type = "base"
		end
		object = classlib(name, loveframes.objects["base"])
	else
		object = classlib(name)
	end
	loveframes.objects[id] = object
	return object
end

-- require helper
loveframes.require = function(name)
	local ret = require(name)
	if type(ret) == "function" then return ret(loveframes) end
	return ret
end

------------------------------------------------------------
-- Load the base object (textinput inherits from it)
------------------------------------------------------------

-- Create a minimal base object that textinput expects
local base = loveframes.NewObject("base", "loveframes_object_base", false)

function base:initialize()
	self.type = "base"
	self.x = 0
	self.y = 0
	self.width = 200
	self.height = 25
	self.staticx = 0
	self.staticy = 0
	self.visible = true
	self.state = "none"
	self.internals = {}
	self.parent = loveframes.base
	self.hover = false
	self.alwaysupdate = false
end

function base:SetDrawFunc() end
function base:SetDrawOrder() end
function base:CheckHover() end
function base:GetWidth() return self.width end
function base:GetHeight() return self.height end
function base:GetBaseParent() return self end
function base:MakeTop() end
function base:Remove() end

-- PositionText stub (used in update)
function base:PositionText()
	if self.multiline then
		self.textx = (self.x - self.offsetx) + self.textoffsetx
		self.texty = (self.y - self.offsety) + self.textoffsety
	else
		self.textx = (self.x - self.offsetx) + self.textoffsetx
		self.texty = (self.y - self.offsety) + self.textoffsety
	end
end

loveframes.objects["base"] = base

------------------------------------------------------------
-- Load textinput module
------------------------------------------------------------

local textinput_module = require("loveframes.objects.textinput")
textinput_module(loveframes)

------------------------------------------------------------
-- Test helpers
------------------------------------------------------------

local test_count = 0
local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
	test_count = test_count + 1
	if actual == expected then
		pass_count = pass_count + 1
	else
		fail_count = fail_count + 1
		io.stderr:write(string.format(
			"FAIL: %s\n  expected: %s\n  actual:   %s\n",
			msg, tostring(expected), tostring(actual)))
	end
end

local function assert_table_eq(actual, expected, msg)
	test_count = test_count + 1
	if type(actual) ~= "table" or type(expected) ~= "table" then
		if actual == expected then
			pass_count = pass_count + 1
		else
			fail_count = fail_count + 1
			io.stderr:write(string.format(
				"FAIL: %s\n  expected: %s\n  actual:   %s\n",
				msg, tostring(expected), tostring(actual)))
		end
		return
	end
	if #actual ~= #expected then
		fail_count = fail_count + 1
		io.stderr:write(string.format(
			"FAIL: %s\n  expected %d items, got %d\n",
			msg, #expected, #actual))
		return
	end
	for i = 1, #actual do
		if actual[i] ~= expected[i] then
			fail_count = fail_count + 1
			io.stderr:write(string.format(
				"FAIL: %s\n  item %d: expected '%s', got '%s'\n",
				msg, i, tostring(expected[i]), tostring(actual[i])))
			return
		end
	end
	pass_count = pass_count + 1
end

local function new_textinput(multiline)
	local ti = loveframes.objects["textinput"]:new()
	ti.multiline = multiline or false
	ti.focus = true
	ti.visible = true
	ti.state = "none"
	ti.editable = true
	loveframes.inputobject = ti
	loveframes.state = "none"
	return ti
end

local function lines_to_strings(lines)
	local result = {}
	for i, v in ipairs(lines) do
		result[i] = v
	end
	return result
end

------------------------------------------------------------
-- Tests
------------------------------------------------------------

print("=== Textinput Cross-Line Editing Regression Tests ===\n")

-- Test 1: Backspace at start of line merges with previous line (non-empty)
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 2
	ti.indicatornum = 0
	ti.offsetx = 0

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {"helloworld"},
		"Test 1: lines after backspace merge (non-empty current line)")
	assert_eq(ti.line, 1,
		"Test 1: line number after merge")
	assert_eq(ti.indicatornum, 5,
		"Test 1: cursor position after merge (should be at junction)")
end

-- Test 2: Backspace at start of empty line removes it
do
	local ti = new_textinput(true)
	ti.lines = {"hello", ""}
	ti.line = 2
	ti.indicatornum = 0
	ti.offsetx = 0

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hello"},
		"Test 2: lines after backspace on empty line")
	assert_eq(ti.line, 1,
		"Test 2: line number")
	assert_eq(ti.indicatornum, 5,
		"Test 2: cursor at end of previous line")
end

-- Test 3: Delete at end of line merges with next line
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("delete", false)

	assert_table_eq(lines_to_strings(ti.lines), {"helloworld"},
		"Test 3: lines after delete merge")
	assert_eq(ti.line, 1,
		"Test 3: line stays on first line")
	assert_eq(ti.indicatornum, 5,
		"Test 3: cursor stays at junction point")
end

-- Test 4: Delete at end of line with empty next line
do
	local ti = new_textinput(true)
	ti.lines = {"hello", ""}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("delete", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hello"},
		"Test 4: empty next line removed by delete")
	assert_eq(ti.line, 1,
		"Test 4: line number")
	assert_eq(ti.indicatornum, 5,
		"Test 4: cursor position")
end

-- Test 5: Select all + delete clears everything
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world", "foo"}
	ti.line = 2
	ti.indicatornum = 3
	ti.alltextselected = true
	ti.offsetx = 50

	ti:RunKey("delete", false)

	assert_table_eq(lines_to_strings(ti.lines), {""},
		"Test 5: all text cleared after select-all delete")
	assert_eq(ti.line, 1,
		"Test 5: line reset to 1")
	assert_eq(ti.indicatornum, 0,
		"Test 5: cursor reset to 0")
	assert_eq(ti.offsetx, 0,
		"Test 5: offsetx reset to 0")
	assert_eq(ti.alltextselected, false,
		"Test 5: alltextselected cleared")
end

-- Test 6: Select all + backspace clears everything
do
	local ti = new_textinput(true)
	ti.lines = {"abc", "def"}
	ti.line = 1
	ti.indicatornum = 2
	ti.alltextselected = true
	ti.offsetx = 10

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {""},
		"Test 6: all text cleared after select-all backspace")
	assert_eq(ti.line, 1,
		"Test 6: line reset to 1")
	assert_eq(ti.indicatornum, 0,
		"Test 6: cursor reset to 0")
	assert_eq(ti.alltextselected, false,
		"Test 6: alltextselected cleared")
end

-- Test 7: Backspace in single-line mode (no regression)
do
	local ti = new_textinput(false)
	ti.lines = {"hello"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hell"},
		"Test 7: single-line backspace works")
	assert_eq(ti.indicatornum, 4,
		"Test 7: cursor moved back")
end

-- Test 8: Delete in single-line mode (no regression)
do
	local ti = new_textinput(false)
	ti.lines = {"hello"}
	ti.line = 1
	ti.indicatornum = 0
	ti.offsetx = 0

	ti:RunKey("delete", false)

	assert_table_eq(lines_to_strings(ti.lines), {"ello"},
		"Test 8: single-line delete works")
	assert_eq(ti.indicatornum, 0,
		"Test 8: cursor stays at 0")
end

-- Test 9: Multiple consecutive backspaces across lines
do
	local ti = new_textinput(true)
	ti.lines = {"abc", "def", "ghi"}
	ti.line = 3
	ti.indicatornum = 0
	ti.offsetx = 0

	-- First backspace: merge line 3 into line 2
	ti:RunKey("backspace", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abc", "defghi"},
		"Test 9a: first backspace merge")
	assert_eq(ti.line, 2,
		"Test 9a: line after first merge")
	assert_eq(ti.indicatornum, 3,
		"Test 9a: cursor at junction")

	-- Second backspace: delete 'f' from "defghi"
	ti:RunKey("backspace", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abc", "deghi"},
		"Test 9b: second backspace removes char")
	assert_eq(ti.indicatornum, 2,
		"Test 9b: cursor moved back")

	-- Third backspace: delete 'e'
	ti:RunKey("backspace", false)
	assert_eq(ti.indicatornum, 1,
		"Test 9c: cursor moved back again")

	-- Fourth backspace: delete 'd'
	ti:RunKey("backspace", false)
	assert_eq(ti.indicatornum, 0,
		"Test 9d: cursor at start of line")

	-- Fifth backspace: merge line 2 ("ghi") into line 1 ("abc")
	ti:RunKey("backspace", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abcghi"},
		"Test 9e: third merge across lines")
	assert_eq(ti.line, 1,
		"Test 9e: now on line 1")
	assert_eq(ti.indicatornum, 3,
		"Test 9e: cursor at junction")
end

-- Test 10: Delete at end of last line (should be no-op)
do
	local ti = new_textinput(true)
	ti.lines = {"hello"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("delete", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hello"},
		"Test 10: delete at end of last line is no-op")
	assert_eq(ti.indicatornum, 5,
		"Test 10: cursor unchanged")
end

-- Test 11: Backspace at start of first line (should be no-op)
do
	local ti = new_textinput(true)
	ti.lines = {"hello"}
	ti.line = 1
	ti.indicatornum = 0
	ti.offsetx = 0

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hello"},
		"Test 11: backspace at start of first line is no-op")
	assert_eq(ti.indicatornum, 0,
		"Test 11: cursor unchanged")
end

-- Test 12: offsetx stays non-negative after cross-line backspace
do
	local ti = new_textinput(true)
	ti.lines = {"short", "a very long line of text here"}
	ti.line = 2
	ti.indicatornum = 0
	ti.offsetx = 100  -- scrolled right

	ti:RunKey("backspace", false)

	assert_table_eq(lines_to_strings(ti.lines), {"shorta very long line of text here"},
		"Test 12: lines merged correctly")
	assert_eq(ti.line, 1,
		"Test 12: on line 1")
	assert_eq(ti.indicatornum, 5,
		"Test 12: cursor at junction")
	-- offsetx should be adjusted so cursor is visible
	assert_eq(ti.offsetx >= 0, true,
		"Test 12: offsetx is non-negative")
end

-- Test 13: Tab still works in multiline mode (no regression)
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("tab", false)

	-- tabreplacement is 8 spaces by default
	local expected = "hello" .. ti.tabreplacement
	assert_eq(ti.lines[1], expected,
		"Test 13: tab inserts replacement text")
	assert_eq(ti.indicatornum, 5 + #ti.tabreplacement,
		"Test 13: cursor advanced by tab width")
end

-- Test 14: Enter in multiline mode creates new line (no regression)
do
	local ti = new_textinput(true)
	ti.lines = {"helloworld"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("return", false)

	assert_table_eq(lines_to_strings(ti.lines), {"hello", "world"},
		"Test 14: enter splits line correctly")
	assert_eq(ti.line, 2,
		"Test 14: cursor on new line")
	assert_eq(ti.indicatornum, 0,
		"Test 14: cursor at start of new line")
end

-- Test 15: Text input in multiline mode (no regression)
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 1
	ti.indicatornum = 5
	ti.offsetx = 0

	ti:RunKey("!", true)

	assert_eq(ti.lines[1], "hello!",
		"Test 15: character appended")
	assert_eq(ti.indicatornum, 6,
		"Test 15: cursor advanced")
end

-- Test 16: Backspace at middle of line (no cross-line, no regression)
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 1
	ti.indicatornum = 3
	ti.offsetx = 0

	ti:RunKey("backspace", false)

	assert_eq(ti.lines[1], "helo",
		"Test 16: char removed mid-line")
	assert_eq(ti.indicatornum, 2,
		"Test 16: cursor moved back")
	assert_eq(ti.line, 1,
		"Test 16: line unchanged")
end

-- Test 17: Delete at middle of line (no cross-line, no regression)
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "world"}
	ti.line = 1
	ti.indicatornum = 2
	ti.offsetx = 0

	ti:RunKey("delete", false)

	assert_eq(ti.lines[1], "helo",
		"Test 17: char removed mid-line by delete")
	assert_eq(ti.indicatornum, 2,
		"Test 17: cursor unchanged")
end

-- Test 18: Rapid delete at line boundary then type
do
	local ti = new_textinput(true)
	ti.lines = {"abc", "def"}
	ti.line = 1
	ti.indicatornum = 3
	ti.offsetx = 0

	-- Delete merges lines
	ti:RunKey("delete", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abcdef"},
		"Test 18a: lines merged")
	assert_eq(ti.indicatornum, 3,
		"Test 18a: cursor at junction")

	-- Type a character
	ti:RunKey("X", true)
	assert_eq(ti.lines[1], "abcXdef",
		"Test 18b: char inserted at correct position")
	assert_eq(ti.indicatornum, 4,
		"Test 18b: cursor advanced")
end

-- Test 19: Backspace merge then immediate delete
do
	local ti = new_textinput(true)
	ti.lines = {"abc", "def"}
	ti.line = 2
	ti.indicatornum = 0
	ti.offsetx = 0

	-- Backspace merges lines
	ti:RunKey("backspace", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abcdef"},
		"Test 19a: lines merged by backspace")
	assert_eq(ti.indicatornum, 3,
		"Test 19a: cursor at junction")

	-- Delete removes char at cursor (should remove 'd')
	ti:RunKey("delete", false)
	assert_eq(ti.lines[1], "abcef",
		"Test 19b: delete removed correct char after merge")
	assert_eq(ti.indicatornum, 3,
		"Test 19b: cursor unchanged after delete")
end

-- Test 20: Three lines, delete at boundaries, then navigate
do
	local ti = new_textinput(true)
	ti.lines = {"a", "b", "c"}
	ti.line = 1
	ti.indicatornum = 1  -- at end of "a"
	ti.offsetx = 0

	-- Delete at end of line 1 merges with line 2
	ti:RunKey("delete", false)
	assert_table_eq(lines_to_strings(ti.lines), {"ab", "c"},
		"Test 20a: first merge")
	assert_eq(ti.indicatornum, 1,
		"Test 20a: cursor at junction (not at end of 'ab')")

	-- Move cursor to end of "ab" (position 2)
	ti.indicatornum = 2

	-- Delete at end of line 1 merges with line 2 ("c")
	ti:RunKey("delete", false)
	assert_table_eq(lines_to_strings(ti.lines), {"abc"},
		"Test 20b: second merge after navigating to end")
	assert_eq(ti.indicatornum, 2,
		"Test 20b: cursor at junction")

	-- Normal delete: remove 'c' at position 2
	ti:RunKey("delete", false)
	assert_eq(ti.lines[1], "ab",
		"Test 20c: normal delete after merges")
	assert_eq(ti.indicatornum, 2,
		"Test 20c: cursor at end")
end

-- Test 21: Empty lines in the middle
do
	local ti = new_textinput(true)
	ti.lines = {"hello", "", "world"}
	ti.line = 2
	ti.indicatornum = 0
	ti.offsetx = 0

	-- Backspace on empty line 2: should merge into line 1
	ti:RunKey("backspace", false)
	assert_table_eq(lines_to_strings(ti.lines), {"hello", "world"},
		"Test 21a: empty line removed by backspace")
	assert_eq(ti.line, 1,
		"Test 21a: on line 1")
	assert_eq(ti.indicatornum, 5,
		"Test 21a: cursor at end of line 1")

	-- Now we have {"hello", "world"}, cursor at line 1 pos 5
	-- Delete at end of line 1: merge with "world"
	ti:RunKey("delete", false)
	assert_table_eq(lines_to_strings(ti.lines), {"helloworld"},
		"Test 21b: second merge")
	assert_eq(ti.indicatornum, 5,
		"Test 21b: cursor at junction")
end

------------------------------------------------------------
-- Summary
------------------------------------------------------------

print(string.format("\n=== Results: %d/%d passed, %d failed ===",
	pass_count, test_count, fail_count))

if fail_count > 0 then
	os.exit(1)
else
	print("All tests passed!")
	os.exit(0)
end
