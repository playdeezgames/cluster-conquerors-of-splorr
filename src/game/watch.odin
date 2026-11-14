package game

// The Neighbourhood Watch (slice 2 step 4): spies. Every empire sends a share of its BJ income (0 to 25 %)
// to its Watch; each WATCHER_COST BJ saved trains a watcher, who stays at home (looking out for the other
// side's watchers) until placed on a rival with a mission: just watch, steal techs, or sabotage
// factories, bases or ships. Each turn every placed watcher risks being caught (caught is gone, and the
// rival's grudge grows); the ones on a mission try their luck, and at most one succeeds per rival a
// turn. Watchers on a rival let you see its colonies and parked ships as if yer own were there. Raccoons
// succeed half as often again and are caught half as often.

WATCH_SHARE_MAX :: 25 // percent of BJ income
WATCHER_COST :: 20 // BJ to train a watcher
WATCHERS_MAX :: 20 // an empire's watchers, at home and placed
WATCH_SUCCESS :: 10 // percent a watcher on a mission succeeds a turn
WATCH_PER_EXTRA :: 5 // added for every watcher placed beyond the rival's watchers at home
WATCH_SUCCESS_MAX :: 60
WATCH_CATCH :: 20 // percent a watcher on a mission is caught a turn
WATCH_CATCH_WATCHING :: 5 // the same for one that only watches
WATCH_CATCH_DEFENDED :: 10 // added to either when the rival has watchers at home
GRUDGE_SPY_CAUGHT :: 10
SABOTAGE_FACTORIES :: 5 // factories wrecked by one sabotage
AI_WATCH_SHARE :: 10
FRAME_WORKS :: 75 // percent a frame-up fools the victim
GRUDGE_FRAMED :: 10 // what a mission done under a frame-up adds, on whoever is blamed
MAX_EXPOSED :: 3 // failed frame-ups read out at a meeting (the minutes hold 14 lines); yers come first

// A frame-up that fooled nobody, waiting to be read out at the next meeting.
Exposed :: struct {
	spy, victim, framed: int,
}

Mission :: enum u8 {
	Watch,
	Steal,
	Factories,
	Bases,
	Ships,
}

MISSION_NAMES := [Mission]string {
	.Watch     = "just watch",
	.Steal     = "steal techs",
	.Factories = "wreck factories",
	.Bases     = "wreck bases",
	.Ships     = "wreck ships",
}

// Watchers an empire has, at home and placed.
watchers_of :: proc(g: ^Game, owner: int) -> int {
	e := &g.empires[owner]
	n := e.watchers
	for p in e.placed {
		n += p
	}
	return n
}

// A watcher's chance on a mission; `defenders` is the rival's watchers at home (the screen, not knowing
// them, passes 0).
watch_success :: proc(g: ^Game, spy, target, defenders: int) -> int {
	extra := max(0, g.empires[spy].placed[target] - defenders)
	p := WATCH_SUCCESS + WATCH_PER_EXTRA * extra
	if g.empires[spy].race == .Raccoons {
		p = p * 3 / 2
	}
	return min(p, WATCH_SUCCESS_MAX)
}

watch_catch :: proc(g: ^Game, spy: int, m: Mission, defended: bool) -> int {
	p := m == .Watch ? WATCH_CATCH_WATCHING : WATCH_CATCH
	if defended {
		p += m == .Watch ? WATCH_CATCH_WATCHING : WATCH_CATCH_DEFENDED
	}
	if g.empires[spy].race == .Raccoons {
		p /= 2
	}
	return p
}

// The Watch's share of this turn's income (what the colonies brought in since `before`), and new watchers.
fund_watch :: proc(g: ^Game, owner, before: int) {
	e := &g.empires[owner]
	gained := e.bj - before
	if gained <= 0 || e.watch_share <= 0 || watchers_of(g, owner) >= WATCHERS_MAX {
		return
	}
	take := gained * e.watch_share / 100
	e.bj -= take
	e.watch_saved += take
	for e.watch_saved >= WATCHER_COST && watchers_of(g, owner) < WATCHERS_MAX {
		e.watch_saved -= WATCHER_COST
		e.watchers += 1
		if owner == PLAYER {
			say(g, "A new watcher joins yer Neighbourhood Watch.")
		}
	}
}

// Places one more watcher on `target` (by > 0) or calls one home (by < 0).
move_watcher :: proc(g: ^Game, owner, target, by: int) -> bool {
	e := &g.empires[owner]
	if by > 0 && e.watchers > 0 {
		e.watchers -= 1
		e.placed[target] += 1
		return true
	}
	if by < 0 && e.placed[target] > 0 {
		e.placed[target] -= 1
		e.watchers += 1
		return true
	}
	return false
}

// Every placed watcher's turn.
watch_turn :: proc(g: ^Game) {
	for a in 0 ..< g.empire_count {
		ea := &g.empires[a]
		if ea.out {
			continue
		}
		for b in 0 ..< g.empire_count {
			if b == a || ea.placed[b] == 0 {
				continue
			}
			if g.empires[b].out {
				ea.watchers += ea.placed[b]
				ea.placed[b] = 0
				continue
			}
			m := ea.mission[b]
			caught := 0
			tries := ea.placed[b]
			done := false
			for _ in 0 ..< tries {
				if rng_int(&g.rng, 100) < watch_catch(g, a, m, g.empires[b].watchers > 0) {
					caught += 1
					continue
				}
				if m != .Watch && !done && rng_int(&g.rng, 100) < watch_success(g, a, b, g.empires[b].watchers) {
					done = sabotage(g, a, b, m)
				}
			}
			if done && framing(g, a, b, m) {
				blamed, exposed := pin_blame(g, a, b, GRUDGE_FRAMED)
				report_frame(g, a, b, blamed, exposed)
			}
			if caught > 0 {
				ea.placed[b] -= caught
				g.spies_caught += caught
				blamed, exposed := a, false
				if framing(g, a, b, m) {
					blamed, exposed = pin_blame(g, a, b, GRUDGE_SPY_CAUGHT * caught)
				} else {
					add_grudge(g, b, a, GRUDGE_SPY_CAUGHT * caught)
				}
				report_caught(g, a, b, caught, blamed, exposed)
			}
		}
	}
}

// The empire a frame-up would name: the third one, if the spy knows of it.
frame_target :: proc(g: ^Game, spy, victim: int) -> int {
	t := third_of(g, spy, victim)
	if t == NO_OWNER || !g.empires[spy].met[t] {
		return NO_OWNER
	}
	return t
}

// Whether the spy's watchers on `victim` are leaving someone else's name about.
framing :: proc(g: ^Game, spy, victim: int, m: Mission) -> bool {
	return m != .Watch && g.empires[spy].frame[victim] && frame_target(g, spy, victim) != NO_OWNER
}

// Whose fault the victim thinks it was: the framed empire takes the grudge if the frame-up works; if
// not, the spy takes it twice over and the Association hears of it at the next meeting.
pin_blame :: proc(g: ^Game, spy, victim, grudge: int) -> (blamed: int, exposed: bool) {
	framed := frame_target(g, spy, victim)
	if rng_int(&g.rng, 100) < FRAME_WORKS {
		add_grudge(g, victim, framed, grudge)
		g.frames_worked += 1
		return framed, false
	}
	add_grudge(g, victim, spy, 2 * grudge)
	g.frames_failed += 1
	c := &g.council
	x := Exposed{spy, victim, framed}
	if c.exposed_n < MAX_EXPOSED {
		c.exposed[c.exposed_n] = x
		c.exposed_n += 1
	} else if spy == PLAYER || victim == PLAYER || framed == PLAYER {
		// A full list makes room for one about you.
		for &old in c.exposed {
			if old.spy != PLAYER && old.victim != PLAYER && old.framed != PLAYER {
				old = x
				break
			}
		}
	}
	return spy, true
}

report_caught :: proc(g: ^Game, spy, target, n, blamed: int, exposed: bool) {
	if spy != PLAYER && target != PLAYER {
		return
	}
	b: Text
	if spy == PLAYER {
		add(&b, "The ")
		add(&b, empire_name(g, target))
		add(&b, " caught ")
		if n == 1 {
			add(&b, "one of yer watchers")
		} else {
			add_int(&b, n)
			add(&b, " of yer watchers")
		}
		switch {
		case exposed:
			add(&b, " framing the ")
			add(&b, empire_name(g, frame_target(g, spy, target)))
			add(&b, ". Nobody was fooled.")
		case blamed != spy:
			add(&b, ", and blame the ")
			add(&b, empire_name(g, blamed))
			add(&b, ".")
		case:
			add(&b, ". They will remember.")
		}
	} else {
		add(&b, g.empires[PLAYER].watchers > 0 ? "Yer Watch caught " : "The neighbours caught ")
		add_int(&b, n)
		add(&b, " ")
		// A frame-up that works fools you too.
		add(&b, blamed == PLAYER ? "of yer own" : empire_name(g, blamed))
		add(&b, n == 1 ? " watcher snooping" : " watchers snooping")
		if exposed {
			add(&b, ", badly dressed as ")
			add(&b, empire_name(g, frame_target(g, spy, target)))
			add(&b, ".")
		} else {
			add(&b, ". Nobody is surprised.")
		}
	}
	say(g, text(&b))
}

// What a mission done under a frame-up left behind.
report_frame :: proc(g: ^Game, spy, victim, blamed: int, exposed: bool) {
	framed := frame_target(g, spy, victim)
	b: Text
	switch {
	case spy == PLAYER && exposed:
		add(&b, "Yer frame-up of the ")
		add(&b, empire_name(g, framed))
		add(&b, " fooled nobody. The ")
		add(&b, empire_name(g, victim))
		add(&b, " blame you, twice over.")
	case spy == PLAYER:
		add(&b, "The ")
		add(&b, empire_name(g, victim))
		add(&b, " blame the ")
		add(&b, empire_name(g, framed))
		add(&b, ". Yer Watch left their name all over it.")
	case victim == PLAYER && exposed:
		add(&b, "The evidence points at the ")
		add(&b, empire_name(g, framed))
		add(&b, ", but it was plainly the ")
		add(&b, empire_name(g, spy))
		add(&b, ".")
	case victim == PLAYER:
		add(&b, "The evidence points at the ")
		add(&b, empire_name(g, blamed))
		add(&b, ".")
	case:
		return
	}
	say(g, text(&b))
}

// At a meeting: every frame-up that fooled nobody is read out, and fined.
read_out_frame_ups :: proc(g: ^Game) {
	c := &g.council
	for k in 0 ..< c.exposed_n {
		x := c.exposed[k]
		if !alive_empire(g, x.spy) {
			continue
		}
		b: Text
		add(&b, "a watcher caught at ")
		if x.victim == PLAYER {
			add(&b, "yer colonies")
		} else {
			add(&b, "the ")
			add(&b, empire_name(g, x.victim))
			add(&b, "' colonies")
		}
		add(&b, ", framing ")
		add(&b, who(g, x.framed))
		add(&b, ".")
		complain(g, x.spy, text(&b))
	}
	c.exposed_n = 0
}

// A mission done: false if there was nothing to do it to.
sabotage :: proc(g: ^Game, spy, target: int, m: Mission) -> bool {
	switch m {
	case .Watch:
		return false
	case .Steal:
		list, n := giveable(g, target, spy)
		if n == 0 {
			return false
		}
		id := list[rng_int(&g.rng, n)]
		f, i := tech_of(id)
		learn(g, spy, f, i, "Yer Watch brings home ")
		g.steals += 1
		if target == PLAYER {
			b: Text
			add(&b, "Somebody copied yer Book Club's notes on ")
			add(&b, tech_name(id))
			add(&b, ". Nobody saw who.")
			say(g, text(&b))
		}
		return true
	case .Factories, .Bases:
		star := pick_colony(g, target, m)
		if star == NO_STAR {
			return false
		}
		c := any_colony(g, star)
		lost := 1
		what := "base"
		if m == .Factories {
			lost = min(SABOTAGE_FACTORIES, c.factories)
			c.factories -= lost
			what = lost == 1 ? "factory" : "factories"
		} else {
			c.bases -= 1
		}
		g.sabotages += 1
		report_sabotage(g, spy, target, star, lost, what)
		return true
	case .Ships:
		pick := -1
		seen := 0
		for &f, k in g.fleets {
			if f.used && f.owner == target && f.star != NO_STAR {
				seen += 1
				if rng_int(&g.rng, seen) == 0 {
					pick = k
				}
			}
		}
		if pick < 0 {
			return false
		}
		f := &g.fleets[pick]
		types: [len(Ship_Type)]Ship_Type
		n := 0
		for c, t in f.ships {
			if c > 0 {
				types[n] = t
				n += 1
			}
		}
		t := types[rng_int(&g.rng, n)]
		f.ships[t] -= 1
		star := f.star
		if fleet_size(f) == 0 {
			f^ = {}
		}
		g.sabotages += 1
		report_sabotage(g, spy, target, star, 1, SHIPS[t].name)
		return true
	}
	return false
}

// A random colony of `owner` with something to wreck.
pick_colony :: proc(g: ^Game, owner: int, m: Mission) -> int {
	pick := NO_STAR
	seen := 0
	for i in 0 ..< g.star_count {
		c := colony_of(g, i, owner)
		if c == nil || (m == .Factories && c.factories == 0) || (m == .Bases && c.bases == 0) {
			continue
		}
		seen += 1
		if rng_int(&g.rng, seen) == 0 {
			pick = i
		}
	}
	return pick
}

report_sabotage :: proc(g: ^Game, spy, target, star, n: int, what: string) {
	if spy != PLAYER && target != PLAYER {
		return
	}
	b: Text
	if spy == PLAYER {
		add(&b, "Yer Watch wrecked ")
	} else {
		add(&b, "Somebody wrecked ")
	}
	add_int(&b, n)
	add(&b, " ")
	add(&b, what)
	add(&b, " at ")
	add(&b, g.stars[star].name)
	add(&b, " (Lot ")
	add_int(&b, star + 1)
	add(&b, spy == PLAYER ? ")." : "). Nobody saw who.")
	say(g, text(&b))
}

// Watchers on a rival see its colonies and parked ships.
watch_sight :: proc(g: ^Game) {
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if a == b || g.empires[a].placed[b] == 0 {
				continue
			}
			for i in 0 ..< g.star_count {
				if colony_of(g, i, b) != nil || fleet_of(g, i, b) != nil {
					g.empires[a].sees[i] = true
				}
			}
		}
	}
}

// The rivals' Watch: a tenth of income, one watcher kept home, the rest on the empire they hate most
// (just watching a pact partner), stealing when there is something to steal, otherwise wrecking factories,
// and framing the third empire unless they have a pact with it.
ai_watch :: proc(g: ^Game, owner: int) {
	e := &g.empires[owner]
	e.watch_share = AI_WATCH_SHARE
	target := -1
	for b in 0 ..< g.empire_count {
		if b == owner || !e.met[b] || g.empires[b].out {
			continue
		}
		if target < 0 || e.grudge[b] > e.grudge[target] {
			target = b
		}
	}
	if target < 0 {
		return
	}
	for e.watchers > 1 {
		move_watcher(g, owner, target, 1)
	}
	_, lack := giveable(g, target, owner)
	third := frame_target(g, owner, target)
	e.frame[target] = third != NO_OWNER && !has_pact(g, owner, third)
	switch {
	case has_pact(g, owner, target):
		e.mission[target] = .Watch
	case lack > 0:
		e.mission[target] = .Steal
	case:
		e.mission[target] = .Factories
	}
}

// ---- The Watch screen: the budget, then three rows a rival (watchers, mission, frame-up), then Back ----

Watch_Row :: enum u8 {
	Count,
	Mission,
	Frame,
}

WATCH_BUDGET_ROW :: 0
WATCH_BACK_ROW :: 1 + len(Watch_Row) * (MAX_EMPIRES - 1)
WATCH_ROWS :: WATCH_BACK_ROW + 1

// The rival a row is about, and which of its rows; -1 for the budget and Back.
watch_row_rival :: proc(row: int) -> (rival: int, kind: Watch_Row) {
	if row == WATCH_BUDGET_ROW || row >= WATCH_BACK_ROW {
		return -1, .Count
	}
	return 1 + (row - 1) / len(Watch_Row), Watch_Row((row - 1) % len(Watch_Row))
}

watch_rival_ok :: proc(g: ^Game, r: int) -> bool {
	return r > 0 && r < g.empire_count && g.empires[PLAYER].met[r] && !g.empires[r].out
}

open_watch :: proc(g: ^Game) {
	g.mode = .Watch
	g.row = WATCH_BUDGET_ROW
}

watch_change :: proc(g: ^Game, by: int) {
	e := &g.empires[PLAYER]
	if g.row == WATCH_BUDGET_ROW {
		e.watch_share = clamp(e.watch_share + by * SLIDER_STEP, 0, WATCH_SHARE_MAX)
		return
	}
	r, kind := watch_row_rival(g.row)
	if !watch_rival_ok(g, r) {
		return
	}
	switch kind {
	case .Mission:
		n := len(Mission)
		e.mission[r] = Mission((int(e.mission[r]) + by + n) % n)
		return
	case .Frame:
		if frame_target(g, PLAYER, r) == NO_OWNER {
			say(g, "You have met nobody else to frame.")
		} else {
			e.frame[r] = !e.frame[r]
		}
		return
	case .Count:
	}
	if !move_watcher(g, PLAYER, r, by) {
		say(g, by > 0 ? "No watchers at home to send." : "Nobody of yers is there.")
	}
}

// Up and Down pick a row, Left and Right change it, Enter/OK changes it onwards (or goes back);
// Escape/Back goes back to the map.
watch_command :: proc(g: ^Game, c: Command) {
	#partial switch c {
	case .North:
		g.row = (g.row + WATCH_ROWS - 1) % WATCH_ROWS
	case .South:
		g.row = (g.row + 1) % WATCH_ROWS
	case .West, .East:
		watch_change(g, c == .West ? -1 : 1)
	case .Confirm:
		if g.row == WATCH_BACK_ROW {
			g.mode = .Map
		} else {
			watch_change(g, 1)
		}
	case .Cancel:
		g.mode = .Map
	case .End_Turn:
		g.mode = .Map
		next_turn(g)
	}
}

// A row of the Watch screen as a label, the value between < and > (if it has one) and what follows it.
watch_row_text :: proc(g: ^Game, row: int) -> (label, value, tail: string) {
	@(static) v: Text
	v = {}
	e := &g.empires[PLAYER]
	if row == WATCH_BUDGET_ROW {
		add_int(&v, e.watch_share)
		add(&v, " %")
		return "Budget:", text(&v), "of BJ income"
	}
	if row == WATCH_BACK_ROW {
		return "Back to the map", "", ""
	}
	r, kind := watch_row_rival(row)
	if r >= g.empire_count {
		return "", "", ""
	}
	if !watch_rival_ok(g, r) {
		if kind != .Count {
			return "", "", ""
		}
		return g.empires[r].out ? "Gone." : "Not met yet.", "", ""
	}
	switch kind {
	case .Mission:
		return "  mission:", MISSION_NAMES[e.mission[r]], ""
	case .Frame:
		t := frame_target(g, PLAYER, r)
		if t == NO_OWNER {
			return "  frame-up: nobody else to name", "", ""
		}
		if !e.frame[r] {
			return "  frame-up:", "nobody", ""
		}
		add(&v, "the ")
		add(&v, empire_name(g, t))
		return "  frame-up:", text(&v), e.mission[r] == .Watch ? "(on missions only)" : ""
	case .Count:
	}
	add_int(&v, e.placed[r])
	@(static) l: Text
	l = {}
	add(&l, "On the ")
	add(&l, empire_name(g, r))
	add(&l, ":")
	return text(&l), text(&v), e.placed[r] == 1 ? "watcher" : "watchers"
}

WATCH_VALUE_COL :: 21 // past "On the Tardigrades:"

watch_row_y :: proc(row: int) -> int {
	return DESK_TOP + row * DESK_H
}

// A tap on the Watch screen: on < or > changes the row; on a row picks it, and a second tap changes it.
watch_pointer :: proc(g: ^Game, sx, sy: int) {
	for row in 0 ..< WATCH_ROWS {
		y := watch_row_y(row)
		if sy < y - 3 || sy >= y - 3 + DESK_H {
			continue
		}
		_, value, _ := watch_row_text(g, row)
		col := (sx - COLONY_X) / GLYPH_W
		g.row = row
		switch {
		case row == WATCH_BACK_ROW:
			g.mode = .Map
		case value != "" && col >= WATCH_VALUE_COL - 1 && col <= WATCH_VALUE_COL + 1:
			watch_change(g, -1)
		case value != "" && col >= WATCH_VALUE_COL + 2 + len(value) && col <= WATCH_VALUE_COL + 4 + len(value):
			watch_change(g, 1)
		}
		return
	}
}
