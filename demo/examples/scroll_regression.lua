local example = {}
example.title = "Scroll Regression Tests"
example.category = "Example Implementations"

function example.func(loveframes, centerarea)

	-- =========================================================
	-- Regression test: columnlist wheel / MakeTop / direction
	-- =========================================================
	-- This demo creates several overlapping scenarios so you can
	-- verify by hand that:
	--   1. Scrolling inside a columnlist does NOT bring the parent
	--      frame to the top (MakeTop only on click).
	--   2. When two frames overlap, only the front-most one scrolls.
	--   3. Horizontal wheel (x) drives the horizontal scrollbar
	--      when one is present.
	--   4. A regular list behaves the same way (no MakeTop on scroll,
	--      correct direction handling).

	local cx, cy, cw, ch = unpack(centerarea)

	-- ---- helper: fill rows ----
	local function fillrows(list, n)
		for i = 1, n do
			list:AddRow(
				"R" .. i .. " C1",
				"R" .. i .. " C2",
				"R" .. i .. " C3",
				"R" .. i .. " C4"
			)
		end
	end

	-- ==== TEST 1: basic columnlist in a frame ====
	local f1 = loveframes.Create("frame")
	f1:SetName("Test1 - basic columnlist (scroll me)")
	f1:SetSize(320, 260)
	f1:SetPos(cx, cy)

	local cl1 = loveframes.Create("columnlist", f1)
	cl1:SetPos(5, 30)
	cl1:SetSize(310, 225)
	cl1:AddColumn("Col A")
	cl1:AddColumn("Col B")
	cl1:AddColumn("Col C")
	cl1:AddColumn("Col D")
	fillrows(cl1, 30)

	-- ==== TEST 2: second overlapping frame (drawn AFTER f1, so on top) ====
	local f2 = loveframes.Create("frame")
	f2:SetName("Test2 - overlapping frame (on top)")
	f2:SetSize(280, 220)
	f2:SetPos(cx + 180, cy + 40)

	local cl2 = loveframes.Create("columnlist", f2)
	cl2:SetPos(5, 30)
	cl2:SetSize(270, 185)
	cl2:AddColumn("X")
	cl2:AddColumn("Y")
	fillrows(cl2, 25)

	-- ==== TEST 3: columnlist with wide columns (triggers hbar) ====
	local f3 = loveframes.Create("frame")
	f3:SetName("Test3 - hbar + vbar (scroll x and y)")
	f3:SetSize(300, 240)
	f3:SetPos(cx, cy + 280)

	local cl3 = loveframes.Create("columnlist", f3)
	cl3:SetPos(5, 30)
	cl3:SetSize(290, 205)
	cl3:AddColumn("Wide Column 1")
	cl3:AddColumn("Wide Column 2")
	cl3:AddColumn("Wide Column 3")
	cl3:SetColumnWidth(1, 200)
	cl3:SetColumnWidth(2, 200)
	cl3:SetColumnWidth(3, 200)
	cl3:PositionColumns()
	cl3.internals[1]:CalculateSize()
	cl3.internals[1]:RedoLayout()
	fillrows(cl3, 20)

	-- ==== TEST 4: regular list in a frame (no MakeTop on scroll) ====
	local f4 = loveframes.Create("frame")
	f4:SetName("Test4 - regular list")
	f4:SetSize(260, 200)
	f4:SetPos(cx + 320, cy + 280)

	local lst = loveframes.Create("list", f4)
	lst:SetPos(5, 30)
	lst:SetSize(250, 165)
	lst:SetPadding(3)
	lst:SetSpacing(2)
	for i = 1, 30 do
		local btn = loveframes.Create("button")
		btn:SetText("Item " .. i)
		btn:SetWidth(230)
		lst:AddItem(btn)
	end

	-- ==== TEST 5: columnlist with ONLY horizontal bar (few rows, wide cols) ====
	local f5 = loveframes.Create("frame")
	f5:SetName("Test5 - hbar only (try horiz scroll)")
	f5:SetSize(250, 160)
	f5:SetPos(cx + 320, cy)

	local cl5 = loveframes.Create("columnlist", f5)
	cl5:SetPos(5, 30)
	cl5:SetSize(240, 125)
	cl5:AddColumn("AAA")
	cl5:AddColumn("BBB")
	cl5:SetColumnWidth(1, 250)
	cl5:SetColumnWidth(2, 250)
	cl5:PositionColumns()
	cl5.internals[1]:CalculateSize()
	cl5.internals[1]:RedoLayout()
	-- only 2 rows so vbar should NOT appear
	fillrows(cl5, 2)

	-- ==== on-screen instructions ====
	local info = loveframes.Create("text")
	info:SetPos(cx + 600, cy)
	info:SetText({
		{color = {1, 0, 0, 1}}, "Scroll regression tests\n",
		{color = {1, 1, 1, 1}},
		"\nTest 1: scroll basic columnlist",
		"\n  - frame should NOT jump to top",
		"\n\nTest 2: scroll overlapping frame",
		"\n  - only top-most list responds",
		"\n\nTest 3: scroll both x and y",
		"\n  - y wheel -> vertical bar",
		"\n  - x wheel -> horizontal bar",
		"\n\nTest 4: regular list scroll",
		"\n  - frame should NOT jump to top",
		"\n\nTest 5: hbar-only columnlist",
		"\n  - y wheel should NOT move hbar",
		"\n  - x wheel should move hbar",
		"\n\nClick any frame title to bring",
		"\nit to front (expected behavior)."
	})

end

return example
