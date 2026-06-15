-- Headless regression test for frame docking (loveframes/objects/frame.lua).
--
-- Verifies, for all four dock directions, that:
--   * docking sets the matching dockedX flag and Xdockobject reference,
--   * the OnDock callback fires once on dock with (frame, object, direction, true),
--   * the docked position matches the original placement formula,
--   * undocking clears both the dockedX flag AND the Xdockobject reference,
--   * the OnDock callback fires on undock with (frame, object, direction, false).
-- Plus: a non-dockable target produces no dock/callback, and a frame can be
-- undocked from one target and re-docked onto a different one.
--
-- Run from the repo root:  lua tests/dock_test.lua

local script = (arg and arg[0]) or "tests/dock_test.lua"
local scriptdir = script:match("^(.*)[/\\][^/\\]*$") or "."
local frame_path = scriptdir .. "/../loveframes/objects/frame.lua"

------------------------------------------------------------------- test runner
local failures = 0
local function check(cond, msg)
	if cond then
		print("  ok   - " .. msg)
	else
		failures = failures + 1
		print("  FAIL - " .. msg)
	end
end

----------------------------------------------------------- fake love + loveframes
local mouse = {x = 0, y = 0}
love = {mouse = {getPosition = function() return mouse.x, mouse.y end}}

local lf = {}
lf.state = "test"
lf.base = {children = {}}

-- collision primitives copied verbatim from loveframes/libraries/utils.lua
function lf.BoundingBox(x1, x2, y1, y2, w1, w2, h1, h2)
	if x1 > x2 + w2 - 1 or y1 > y2 + h2 - 1 or x2 > x1 + w1 - 1 or y2 > y1 + h1 - 1 then
		return false
	else
		return true
	end
end
function lf.RectangleCollisionCheck(rect1, rect2)
	return lf.BoundingBox(rect1.x, rect2.x, rect1.y, rect2.y, rect1.width, rect2.width, rect1.height, rect2.height)
end

-- capture the frame "class" that frame.lua registers via NewObject
local FrameClass
function lf.NewObject(otype, classname, internal)
	local cls = {}
	FrameClass = cls
	return cls
end

-- load the real frame module and attach its methods to FrameClass
local modfn = assert(loadfile(frame_path))()
assert(type(modfn) == "function", "frame.lua should return a module function")
modfn(lf)
assert(FrameClass, "frame.lua did not register an object via NewObject")
-- frame:update() calls self:CheckHover(); stub it (defined on the base object normally)
FrameClass.CheckHover = function() end

------------------------------------------------------------------ frame factory
local function recompute_zones(f)
	local s = f.dockzonesize
	f.dockzones = {
		top    = {x = f.x,            y = f.y - s,        width = f.width, height = s},
		bottom = {x = f.x,            y = f.y + f.height, width = f.width, height = s},
		left   = {x = f.x - s,        y = f.y,            width = s,       height = f.height},
		right  = {x = f.x + f.width,  y = f.y,            width = s,       height = f.height},
	}
end

local function new_frame(x, y, w, h)
	local f = setmetatable({}, {__index = FrameClass})
	f.type = "frame"
	f.state = lf.state
	f.visible = true
	f.dragging = false
	f.screenlocked = false
	f.parentlocked = false
	f.modal = false
	f.alwaysontop = false
	f.dockable = false
	f.dockzonesize = 10
	f.children = {}
	f.internals = {}
	f.parent = lf.base
	f.clickx = 0
	f.clicky = 0
	f.dockx = 0
	f.docky = 0
	f.dockedtop, f.dockedbottom, f.dockedleft, f.dockedright = false, false, false, false
	f.topdockobject, f.bottomdockobject = false, false
	f.leftdockobject, f.rightdockobject = false, false
	f.x, f.y, f.width, f.height = x, y, w, h
	recompute_zones(f)
	return f
end

-- target frame shared by the directional cases
local function make_pair(ax, ay)
	local A = new_frame(ax, ay, 100, 150)
	local B = new_frame(300, 300, 300, 150)
	A.dragging = true
	A.dockable = true
	B.dockable = true
	lf.base.children = {A, B}
	return A, B
end

------------------------------------------------------------------- the test cases
-- ax/ay: A's placement so the matching dockzone collides with B.
-- exx/exy: expected docked position (proves the placement formula is intact).
-- axis: which mouse axis the undock threshold watches.
local cases = {
	{dir = "top",    field = "dockedtop",    obj = "topdockobject",    ax = 300, ay = 145, exx = 300, exy = 150, axis = "y", undock = 170},
	{dir = "bottom", field = "dockedbottom", obj = "bottomdockobject", ax = 300, ay = 455, exx = 300, exy = 450, axis = "y", undock = 480},
	{dir = "left",   field = "dockedleft",   obj = "leftdockobject",   ax = 195, ay = 300, exx = 200, exy = 300, axis = "x", undock = 220},
	{dir = "right",  field = "dockedright",  obj = "rightdockobject",  ax = 605, ay = 300, exx = 600, exy = 300, axis = "x", undock = 630},
}

for _, c in ipairs(cases) do
	print("direction: " .. c.dir)
	local A, B = make_pair(c.ax, c.ay)
	local calls = {}
	A.OnDock = function(frame, object, direction, docked)
		calls[#calls + 1] = {frame = frame, object = object, direction = direction, docked = docked}
	end

	-- drag A onto B so its dockzone collides (clickx/clicky = 0 keeps it put)
	mouse.x, mouse.y = c.ax, c.ay
	A:update(0)

	check(A[c.field] == true, "dock sets self." .. c.field)
	check(A[c.obj] == B, "dock records self." .. c.obj .. " = target frame")
	check(A.x == c.exx and A.y == c.exy, "docked position matches placement formula")
	check(#calls == 1, "OnDock fires exactly once on dock")
	if #calls >= 1 then
		local cb = calls[1]
		check(cb.frame == A and cb.object == B and cb.direction == c.dir and cb.docked == true,
			"OnDock(dock) payload = (frame, object, \"" .. c.dir .. "\", true)")
	end

	-- move the mouse past the undock threshold on the watched axis
	if c.axis == "y" then
		mouse.x, mouse.y = c.ax, c.undock
	else
		mouse.x, mouse.y = c.undock, c.ay
	end
	A:update(0)

	check(A[c.field] == false, "undock clears self." .. c.field)
	check(A[c.obj] == false, "undock clears self." .. c.obj .. " (no stale reference)")
	check(#calls == 2, "OnDock fires again on undock")
	if #calls >= 2 then
		local cb = calls[2]
		check(cb.frame == A and cb.object == B and cb.direction == c.dir and cb.docked == false,
			"OnDock(undock) payload = (frame, object, \"" .. c.dir .. "\", false)")
	end
end

------------------------------------------------------- non-dockable target case
print("non-dockable target")
do
	local A, B = make_pair(300, 145)
	B.dockable = false
	local fired = false
	A.OnDock = function() fired = true end
	mouse.x, mouse.y = 300, 145
	A:update(0)
	check(A.dockedtop == false, "no dock onto a non-dockable target")
	check(A.topdockobject == false, "no dock object recorded for non-dockable target")
	check(fired == false, "OnDock does not fire for non-dockable target")
end

----------------------------------------------- undock then re-dock onto another
print("re-dock onto a different frame")
do
	local A = new_frame(300, 145, 100, 150)
	local B = new_frame(300, 300, 300, 150)
	local C = new_frame(300, 600, 300, 150)
	A.dragging = true
	A.dockable, B.dockable, C.dockable = true, true, true
	lf.base.children = {A, B, C}
	local calls = {}
	A.OnDock = function(frame, object, direction, docked)
		calls[#calls + 1] = {object = object, direction = direction, docked = docked}
	end

	-- dock onto B (top)
	mouse.x, mouse.y = 300, 145
	A:update(0)
	check(A.dockedtop == true and A.topdockobject == B, "initially docked onto B")

	-- undock
	mouse.x, mouse.y = 300, 170
	A:update(0)
	check(A.dockedtop == false and A.topdockobject == false, "undocked from B (state + reference cleared)")

	-- reposition above C and dock onto it
	A.x, A.y = 300, 445
	recompute_zones(A)
	mouse.x, mouse.y = 300, 445
	A:update(0)
	check(A.dockedtop == true and A.topdockobject == C, "re-docked onto a different frame (C)")
	local last = calls[#calls]
	check(last and last.object == C and last.direction == "top" and last.docked == true,
		"last OnDock payload reflects the new target C")
end

------------------------------------------------------------------------- summary
print("")
if failures == 0 then
	print("ALL TESTS PASSED")
	os.exit(0)
else
	print(failures .. " CHECK(S) FAILED")
	os.exit(1)
end
