--[[------------------------------------------------------------------------
	Headless regression check for columnlistarea:wheelmoved.

	Loads the real loveframes/objects/internal/columnlist/columnlistarea.lua
	module with a stubbed `loveframes` so we can capture the object table and
	drive its wheelmoved directly -- no LOVE runtime required.

	Run from anywhere:  lua tests/columnlist_wheel_spec.lua

	It verifies, across every scroll-direction and layering scenario, that:
	  * the correct scroll bar is driven for the correct wheel axis,
	  * a horizontal-only list still scrolls with the vertical wheel,
	  * nothing scrolls when there is no active bar or the list is not on top,
	  * the owning frame is NEVER raised (MakeTop) as a side effect of a wheel
	    event (GetBaseParent is wired to fail the test if it is ever called).
--]]------------------------------------------------------------------------

-- locate the module relative to this script so cwd does not matter
local scriptpath = arg and arg[0] or "tests/columnlist_wheel_spec.lua"
local scriptdir = scriptpath:match("^(.*)[/\\]") or "."
local modulepath = scriptdir .. "/../loveframes/objects/internal/columnlist/columnlistarea.lua"

-- minimal love stub so the dtscrolling branch is exercisable
love = { timer = { getDelta = function() return 0.5 end } }

-- capture the object table built by the module
local captured
local fakeloveframes = {
	NewObject = function() captured = {}; return captured end,
}

local initfn = assert(loadfile(modulepath))()
initfn(fakeloveframes)
assert(type(captured) == "table" and type(captured.wheelmoved) == "function",
	"failed to load columnlistarea module")

------------------------------------------------------------------- helpers

local function makebar()
	local bar = { scrolled = {} }
	function bar:Scroll(amount) self.scrolled[#self.scrolled + 1] = amount end
	return bar
end

local function makebody(bartype, bar)
	return { bartype = bartype, GetScrollBar = function() return bar end }
end

-- builds a fake columnlistarea `self` that inherits the real methods
-- (GetVerticalScrollBody / GetHorizontalScrollBody / wheelmoved) via __index
local function makearea(opts)
	local vbar = makebar()
	local hbar = makebar()
	local internals = {}
	if opts.hasvbody then internals[#internals + 1] = makebody("vertical", vbar) end
	if opts.hashbody then internals[#internals + 1] = makebody("horizontal", hbar) end
	local self = setmetatable({
		internals = internals,
		vbar = opts.vbar or false,
		hbar = opts.hbar or false,
		mousewheelscrollamount = 100,
		dtscrolling = opts.dtscrolling or false,
		IsTopList = function() return opts.toplist ~= false end,
		-- if wheelmoved ever tries to raise the frame, this fails the run
		GetBaseParent = function()
			error("GetBaseParent/MakeTop must not be triggered by a wheel event")
		end,
	}, { __index = captured })
	return self, vbar, hbar
end

local failures = 0
local function check(name, cond)
	if cond then
		print("  PASS  " .. name)
	else
		failures = failures + 1
		print("  FAIL  " .. name)
	end
end

local function only(list, ...)
	local expected = {...}
	if #list ~= #expected then return false end
	for i = 1, #expected do
		if list[i] ~= expected[i] then return false end
	end
	return true
end

------------------------------------------------------------------- scenarios

-- A: bars exist in internals but the vbar/hbar flags are off -> no scrolling
do
	local self, v, h = makearea{ hasvbody = true, hashbody = true, vbar = false, hbar = false }
	self:wheelmoved(0, 1)
	self:wheelmoved(2, 0)
	check("no active bar -> vertical bar untouched", only(v.scrolled))
	check("no active bar -> horizontal bar untouched", only(h.scrolled))
end

-- B: vertical only -> y drives vertical; horizontal wheel (x) is ignored
do
	local self, v, h = makearea{ hasvbody = true, vbar = true }
	self:wheelmoved(0, 1)
	self:wheelmoved(3, 0) -- pure horizontal wheel must not scroll a v-only list
	check("v-only: y scrolls vertical once (-100)", only(v.scrolled, -100))
	check("v-only: horizontal wheel ignored", only(h.scrolled))
end

-- C: horizontal only -> vertical wheel (y) drives the horizontal bar
do
	local self, v, h = makearea{ hashbody = true, hbar = true }
	self:wheelmoved(0, 1)
	check("h-only: y scrolls horizontal (-100)", only(h.scrolled, -100))
	check("h-only: vertical bar untouched", only(v.scrolled))
end

-- D: both bars, pure vertical wheel -> only vertical scrolls
do
	local self, v, h = makearea{ hasvbody = true, hashbody = true, vbar = true, hbar = true }
	self:wheelmoved(0, 2)
	check("both/y: vertical scrolls (-200)", only(v.scrolled, -200))
	check("both/y: horizontal untouched", only(h.scrolled))
end

-- E: both bars, pure horizontal wheel -> only horizontal scrolls
do
	local self, v, h = makearea{ hasvbody = true, hashbody = true, vbar = true, hbar = true }
	self:wheelmoved(5, 0)
	check("both/x: horizontal scrolls (-500)", only(h.scrolled, -500))
	check("both/x: vertical untouched", only(v.scrolled))
end

-- F: both bars, diagonal wheel -> each axis drives its own bar
do
	local self, v, h = makearea{ hasvbody = true, hashbody = true, vbar = true, hbar = true }
	self:wheelmoved(3, 4)
	check("both/diag: vertical from y (-400)", only(v.scrolled, -400))
	check("both/diag: horizontal from x (-300)", only(h.scrolled, -300))
end

-- G: not the top list -> nothing scrolls even with both bars
do
	local self, v, h = makearea{ hasvbody = true, hashbody = true, vbar = true, hbar = true, toplist = false }
	self:wheelmoved(1, 1)
	check("not top list: vertical untouched", only(v.scrolled))
	check("not top list: horizontal untouched", only(h.scrolled))
end

-- H: dtscrolling applies the frame delta (0.5) to the scroll amount
do
	local self, v = makearea{ hasvbody = true, vbar = true, dtscrolling = true }
	self:wheelmoved(0, 2) -- -2 * 100 * 0.5
	check("dtscrolling: vertical scaled by dt (-100)", only(v.scrolled, -100))
end

------------------------------------------------------------------- result

print("")
if failures == 0 then
	print("All columnlist wheel scenarios passed.")
	os.exit(0)
else
	print(failures .. " columnlist wheel scenario(s) FAILED.")
	os.exit(1)
end
