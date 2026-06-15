--[[------------------------------------------------------------
	Regression tests for the multiline textinput edit paths.

	Focus: cross-line merging via backspace / delete and the
	consistency of (lines, current line, indicator position,
	horizontal offset) afterwards. Also guards single-line mode
	and multibyte (UTF-8) input/merging.

	Run from the repository root:
		lua tests/textinput_multiline_test.lua

	Exits with a non-zero status if any assertion fails.
--]]------------------------------------------------------------

-- ----------------------------------------------------------------
-- minimal, UTF-8 correct shim for the loveframes.utf8 surface that
-- the textinput object actually uses (len / sub). Built on Lua's
-- built-in utf8 library so multibyte characters are handled.
-- ----------------------------------------------------------------
local builtin = utf8
local utf8shim = {}

function utf8shim.len(s)
	return builtin.len(s) or #s
end

function utf8shim.sub(s, i, j)
	local n = builtin.len(s) or 0
	if i == nil then i = 1 end
	if i < 0 then i = n + i + 1 end
	if i < 1 then i = 1 end
	if j == nil then j = n end
	if j < 0 then j = n + j + 1 end
	if j > n then j = n end
	if i > j or n == 0 then
		return ""
	end
	local sb = builtin.offset(s, i)
	local eb = builtin.offset(s, j + 1)
	if eb then
		return string.sub(s, sb, eb - 1)
	end
	return string.sub(s, sb)
end

-- best-effort stubs (not exercised by these tests, but present so an
-- accidental call does not blow up with a nil index)
utf8shim.gsub = string.gsub
utf8shim.find = string.find
utf8shim.char = string.char
utf8shim.codes = builtin.codes

-- ----------------------------------------------------------------
-- fake LOVE + font so UpdateIndicator can run headless
-- ----------------------------------------------------------------
local fakefont = {}
function fakefont:getWidth(s) return utf8shim.len(s) end
function fakefont:getHeight() return 10 end

love = {
	timer = { getTime = function() return 0 end },
	keyboard = { isDown = function() return false end },
	graphics = { newFont = function() return fakefont end },
	system = {
		setClipboardText = function() end,
		getClipboardText = function() return "" end,
	},
}

-- ----------------------------------------------------------------
-- load the textinput object factory and capture the object table
-- ----------------------------------------------------------------
local sep = package.config:sub(1, 1)
local scriptpath = (arg and arg[0]) or ""
local scriptdir = scriptpath:match("^(.*" .. sep .. ")") or ("." .. sep)
local root = scriptdir .. ".." .. sep

local newobject
local loveframes = {
	state = "none",
	utf8 = utf8shim,
	basicfont = fakefont,
	NewObject = function()
		newobject = {}
		return newobject
	end,
	IsCtrlDown = function() return false end,
}

local factory = dofile(root .. "loveframes" .. sep .. "objects" .. sep .. "textinput.lua")
factory(loveframes)

assert(newobject and newobject.RunKey, "failed to load textinput object")

-- ----------------------------------------------------------------
-- build a headless textinput instance
-- ----------------------------------------------------------------
local function newinput(opts)
	local inst = setmetatable({}, { __index = newobject })
	inst.type = "textinput"
	inst.state = loveframes.state
	inst.visible = true
	inst.focus = true
	inst.editable = true
	inst.x = 0
	inst.y = 0
	inst.width = 200
	inst.height = 100
	inst.offsetx = opts.offsetx or 0
	inst.offsety = 0
	inst.textoffsetx = 5
	inst.textoffsety = 5
	inst.textx = 0
	inst.texty = 0
	inst.indicatorx = 0
	inst.indicatory = 0
	inst.indincatortime = 0
	inst.showindicator = true
	inst.font = fakefont
	inst.multiline = (opts.multiline ~= false)
	inst.alltextselected = opts.alltextselected or false
	inst.masked = false
	inst.maskchar = "*"
	-- turn off scroll tracking so UpdateIndicator stays headless and
	-- offsetx is whatever the edit logic leaves it as
	inst.trackindicator = false
	inst.tabreplacement = "        "
	inst.limit = 0
	inst.usable = {}
	inst.unusable = {}
	inst.linenumberspanel = false
	inst.vbar = false
	inst.hbar = false
	inst.lines = opts.lines
	inst.line = opts.line
	inst.indicatornum = opts.indicatornum
	-- harmless stubs for accessors that some paths reach for
	inst.GetHorizontalScrollBody = function() return false end
	inst.GetVerticalScrollBody = function() return false end
	inst.GetLineNumbersPanel = function() return false end
	inst.GetWidth = function(self) return self.width end
	inst.GetHeight = function(self) return self.height end
	return inst
end

-- ----------------------------------------------------------------
-- tiny assertion harness
-- ----------------------------------------------------------------
local failures = 0
local total = 0

local function fail(name, msg)
	failures = failures + 1
	print(string.format("FAIL  %s\n        %s", name, msg))
end

local function linesEqual(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function dump(t)
	local parts = {}
	for i = 1, #t do parts[i] = string.format("%q", t[i]) end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- check the full editor state in one shot
local function check(name, inst, exp)
	total = total + 1
	local ok = true
	local msgs = {}
	if exp.lines and not linesEqual(inst.lines, exp.lines) then
		ok = false
		msgs[#msgs + 1] = "lines: got " .. dump(inst.lines) .. " want " .. dump(exp.lines)
	end
	if exp.line ~= nil and inst.line ~= exp.line then
		ok = false
		msgs[#msgs + 1] = "line: got " .. tostring(inst.line) .. " want " .. tostring(exp.line)
	end
	if exp.indicatornum ~= nil and inst.indicatornum ~= exp.indicatornum then
		ok = false
		msgs[#msgs + 1] = "indicatornum: got " .. tostring(inst.indicatornum) .. " want " .. tostring(exp.indicatornum)
	end
	if exp.offsetx ~= nil and inst.offsetx ~= exp.offsetx then
		ok = false
		msgs[#msgs + 1] = "offsetx: got " .. tostring(inst.offsetx) .. " want " .. tostring(exp.offsetx)
	end
	if exp.offsety ~= nil and inst.offsety ~= exp.offsety then
		ok = false
		msgs[#msgs + 1] = "offsety: got " .. tostring(inst.offsety) .. " want " .. tostring(exp.offsety)
	end
	if exp.alltextselected ~= nil and inst.alltextselected ~= exp.alltextselected then
		ok = false
		msgs[#msgs + 1] = "alltextselected: got " .. tostring(inst.alltextselected) .. " want " .. tostring(exp.alltextselected)
	end
	if exp.text ~= nil and inst:GetText() ~= exp.text then
		ok = false
		msgs[#msgs + 1] = "GetText: got " .. string.format("%q", inst:GetText()) .. " want " .. string.format("%q", exp.text)
	end
	if ok then
		print("ok    " .. name)
	else
		fail(name, table.concat(msgs, "\n        "))
	end
end

-- ----------------------------------------------------------------
-- DELETE: cross-line merge at end of line
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "abc", "def" }, line = 1, indicatornum = 3 }
	t:RunKey("delete", false)
	check("delete merges non-empty next line", t,
		{ lines = { "abcdef" }, line = 1, indicatornum = 3, offsetx = 0, text = "abcdef" })
end

do
	-- a stale horizontal offset from the old line must not survive the merge
	local t = newinput{ lines = { "abc", "def" }, line = 1, indicatornum = 3, offsetx = 40 }
	t:RunKey("delete", false)
	check("delete merge resets stale horizontal offset", t,
		{ lines = { "abcdef" }, line = 1, indicatornum = 3, offsetx = 0 })
end

do
	local t = newinput{ lines = { "", "xyz" }, line = 1, indicatornum = 0 }
	t:RunKey("delete", false)
	check("delete from empty line pulls next line up", t,
		{ lines = { "xyz" }, line = 1, indicatornum = 0, text = "xyz" })
end

do
	local t = newinput{ lines = { "abc", "" }, line = 1, indicatornum = 3 }
	t:RunKey("delete", false)
	check("delete merges empty next line", t,
		{ lines = { "abc" }, line = 1, indicatornum = 3, text = "abc" })
end

do
	local t = newinput{ lines = { "abcd", "z" }, line = 1, indicatornum = 1 }
	t:RunKey("delete", false)
	check("delete mid-line removes single char", t,
		{ lines = { "acd", "z" }, line = 1, indicatornum = 1 })
end

do
	local t = newinput{ lines = { "abc" }, line = 1, indicatornum = 3 }
	t:RunKey("delete", false)
	check("delete at end of last line is a no-op", t,
		{ lines = { "abc" }, line = 1, indicatornum = 3 })
end

-- ----------------------------------------------------------------
-- BACKSPACE: cross-line merge at start of line
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "abc", "def" }, line = 2, indicatornum = 0, offsetx = 40 }
	t:RunKey("backspace", false)
	check("backspace merges into previous line, cursor at join", t,
		{ lines = { "abcdef" }, line = 1, indicatornum = 3, offsetx = 0, text = "abcdef" })
end

do
	local t = newinput{ lines = { "abc", "" }, line = 2, indicatornum = 0 }
	t:RunKey("backspace", false)
	check("backspace from empty line joins onto previous", t,
		{ lines = { "abc" }, line = 1, indicatornum = 3 })
end

do
	local t = newinput{ lines = { "", "def" }, line = 2, indicatornum = 0 }
	t:RunKey("backspace", false)
	check("backspace onto empty previous line keeps cursor at 0", t,
		{ lines = { "def" }, line = 1, indicatornum = 0, text = "def" })
end

do
	local t = newinput{ lines = { "abc", "def" }, line = 2, indicatornum = 2 }
	t:RunKey("backspace", false)
	check("backspace mid-line removes single char (no merge)", t,
		{ lines = { "abc", "df" }, line = 2, indicatornum = 1 })
end

do
	local t = newinput{ lines = { "abc", "d" }, line = 1, indicatornum = 0 }
	t:RunKey("backspace", false)
	check("backspace at start of first line is a no-op", t,
		{ lines = { "abc", "d" }, line = 1, indicatornum = 0 })
end

-- ----------------------------------------------------------------
-- SELECT-ALL then delete / backspace
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "abc", "def" }, line = 2, indicatornum = 3, alltextselected = true }
	t:RunKey("delete", false)
	check("select-all + delete clears everything", t,
		{ lines = { "" }, line = 1, indicatornum = 0, offsetx = 0, offsety = 0, alltextselected = false })
end

do
	local t = newinput{ lines = { "abc", "def" }, line = 2, indicatornum = 3, alltextselected = true }
	t:RunKey("backspace", false)
	check("select-all + backspace clears everything", t,
		{ lines = { "" }, line = 1, indicatornum = 0, offsetx = 0, offsety = 0, alltextselected = false })
end

-- ----------------------------------------------------------------
-- CONTINUOUS editing: chained merges + insert must stay consistent
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "ab", "cd", "ef" }, line = 2, indicatornum = 0 }
	t:RunKey("backspace", false)
	check("chain step 1: backspace merge", t,
		{ lines = { "abcd", "ef" }, line = 1, indicatornum = 2, offsetx = 0 })
	t:RunKey("delete", false)
	check("chain step 2: delete mid-line", t,
		{ lines = { "abd", "ef" }, line = 1, indicatornum = 2 })
	t:RunKey("X", true)
	check("chain step 3: insert char", t,
		{ lines = { "abXd", "ef" }, line = 1, indicatornum = 3, text = "abXd\nef" })
end

-- ----------------------------------------------------------------
-- SINGLE-LINE mode must be unaffected
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "abc" }, line = 1, indicatornum = 2, multiline = false }
	t:RunKey("backspace", false)
	check("single-line backspace removes single char", t,
		{ lines = { "ac" }, line = 1, indicatornum = 1, text = "ac" })
end

do
	local t = newinput{ lines = { "ab" }, line = 1, indicatornum = 2, multiline = false }
	t:RunKey("c", true)
	check("single-line char append", t,
		{ lines = { "abc" }, line = 1, indicatornum = 3, text = "abc" })
end

-- ----------------------------------------------------------------
-- TAB and multibyte input keep working
-- ----------------------------------------------------------------
do
	local t = newinput{ lines = { "ab" }, line = 1, indicatornum = 2 }
	t:RunKey("tab", false)
	check("tab inserts replacement and advances cursor", t,
		{ lines = { "ab        " }, line = 1, indicatornum = 10 })
end

do
	-- "é" (U+00E9) is two bytes but one codepoint
	local t = newinput{ lines = { "é", "x" }, line = 1, indicatornum = 1 }
	t:RunKey("delete", false)
	check("delete merge counts multibyte as one char", t,
		{ lines = { "éx" }, line = 1, indicatornum = 1, text = "éx" })
end

do
	local t = newinput{ lines = { "" }, line = 1, indicatornum = 0, multiline = false }
	t:RunKey("é", true)
	check("multibyte char input advances cursor by one", t,
		{ lines = { "é" }, line = 1, indicatornum = 1, text = "é" })
end

-- ----------------------------------------------------------------
-- summary
-- ----------------------------------------------------------------
print(string.format("\n%d/%d checks passed", total - failures, total))
if failures > 0 then
	os.exit(1)
end
