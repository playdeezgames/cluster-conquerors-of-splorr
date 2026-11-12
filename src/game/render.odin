package game

// Draws the play screen: star map, side panel and news ticker.

draw_game :: proc(f: ^Frame, g: ^Game) {
	cls(f, COLOR_BLACK)
	switch g.mode {
	case .Council:
		draw_council(f, g)
	case .Game_Over:
		draw_game_over(f, g)
	case .Battle:
		draw_battle(f, g)
	case .Choose_Race:
		draw_races(f, g)
	case .Colony:
		draw_colony(f, g)
	case .Research:
		draw_research(f, g)
	case .Map, .Fleet, .Destination:
		draw_map(f, g)
	}
	draw_panel(f, g)
	draw_news(f, g)
}

// A cheap fixed hash for the background specks, so the sky does not shimmer between frames.
speck :: proc(x, y: int) -> bool {
	h := u32(x * 73856093) ~ u32(y * 19349663)
	h ~= h >> 13
	h *= 0x5bd1e995
	h ~= h >> 15
	return h % 23 == 0
}

// The screen pixel of the top-left corner of a map cell.
cell_px :: proc(g: ^Game, x, y: int) -> (sx, sy: int) {
	ox, oy := view_origin(g)
	return MAP_X + (x - ox) * TILE, MAP_Y + (y - oy) * TILE
}

on_map :: proc(sx, sy: int) -> bool {
	return sx >= MAP_X && sy >= MAP_Y && sx < MAP_X + VIEW_W * TILE && sy < MAP_Y + VIEW_H * TILE
}

draw_map :: proc(f: ^Frame, g: ^Game) {
	ox, oy := view_origin(g)
	for vy in 0 ..< VIEW_H {
		for vx in 0 ..< VIEW_W {
			if speck(ox + vx, oy + vy) {
				set_px(f, MAP_X + vx * TILE + 6, MAP_Y + vy * TILE + 6, COLOR_DARK)
			}
		}
	}
	// While choosing where, a dotted line from the ships to the cursor: cyan if they can make it.
	if g.mode == .Destination && g.cursor != g.source {
		color: u8 = send_problem(g, PLAYER, g.source, g.cursor, g.send) == "" ? COLOR_CYAN : COLOR_RED
		a, b := g.stars[g.source], g.stars[g.cursor]
		ax, ay := cell_px(g, a.x, a.y)
		bx, by := cell_px(g, b.x, b.y)
		draw_dots(f, ax + 6, ay + 6, bx + 6, by + 6, color)
	}
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		sx, sy := cell_px(g, s.x, s.y)
		if !on_map(sx, sy) {
			continue
		}
		if s.wormhole_known[PLAYER] {
			draw_gfx(f, .Wormhole, sx, sy, COLOR_PURPLE)
		} else if s.reports[PLAYER].filed {
			draw_gfx(f, .Star, sx, sy, COLOR_YELLOW)
		} else {
			draw_gfx(f, .Star_Dim, sx, sy, COLOR_MID)
		}
		if c := any_colony(g, i); c != nil && (c.owner == PLAYER || g.empires[PLAYER].sees[i]) {
			frame_rect(f, sx - 1, sy - 1, TILE + 2, TILE + 2, EMPIRE_COLORS[c.owner])
		}
		// Rivals' ships here, if in sight: a flag at the top left in their colour.
		if g.empires[PLAYER].sees[i] {
			for e in 1 ..< g.empire_count {
				if fleet_of(g, i, e) != nil {
					fill_rect(f, sx, sy - 3, 1, 6, COLOR_LIGHT)
					fill_rect(f, sx - 3, sy - 3, 3, 3, EMPIRE_COLORS[e])
				}
			}
		}
		// Yer ships here: a little flag at the top right, red if they are out of fuel.
		if fl := fleet_at(g, i); fl != nil {
			color: u8 = stranded(g, fl) ? COLOR_RED : COLOR_LIME
			fill_rect(f, sx + TILE - 1, sy - 3, 1, 6, COLOR_LIGHT)
			fill_rect(f, sx + TILE, sy - 3, 3, 3, color)
		}
	}
	// Fleets in transit, part of the way along: yers, and rivals' that are in sight.
	for &fl in g.fleets {
		if !fl.used || fl.star != NO_STAR {
			continue
		}
		if fl.owner != PLAYER && !sees_cell(g, PLAYER, &fl) {
			continue
		}
		a, b := g.stars[fl.from], g.stars[fl.to]
		done := fl.total - fl.left
		x := a.x * TILE + (b.x - a.x) * TILE * done / max(1, fl.total)
		y := a.y * TILE + (b.y - a.y) * TILE * done / max(1, fl.total)
		sx, sy := MAP_X + x - ox * TILE, MAP_Y + y - oy * TILE
		if on_map(sx + 6, sy + 6) {
			draw_gfx(f, .Van, sx, sy, fl.owner == PLAYER ? COLOR_WHITE : EMPIRE_COLORS[fl.owner])
		}
	}
	// The cursor: corner brackets, so the star under it stays visible.
	cur := g.stars[g.cursor]
	cx, cy := cell_px(g, cur.x, cur.y)
	cx, cy = cx - 2, cy - 2
	n := TILE + 4
	for c in ([4][2]int{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
		x0, y0 := cx + c.x * (n - 4), cy + c.y * (n - 1)
		fill_rect(f, x0, y0, 4, 1, COLOR_CYAN)
		x1, y1 := cx + c.x * (n - 1), cy + c.y * (n - 4)
		fill_rect(f, x1, y1, 1, 4, COLOR_CYAN)
	}
}

// Every third pixel along a line, clipped to the map.
draw_dots :: proc(f: ^Frame, x0, y0, x1, y1: int, color: u8) {
	dx, dy := x1 - x0, y1 - y0
	steps := max(abs(dx), abs(dy))
	for i := 0; i <= steps; i += 3 {
		x, y := x0 + dx * i / max(1, steps), y0 + dy * i / max(1, steps)
		if on_map(x, y) {
			set_px(f, x, y, color)
		}
	}
}

draw_panel :: proc(f: ^Frame, g: ^Game) {
	fill_rect(f, PANEL_X - 2, 0, 1, VIEW_H * TILE, COLOR_DARK)
	x := PANEL_TEXT_X
	print(f, "Cluster Conquerors", x, 4, COLOR_CYAN)
	print(f, "of SPLORR!!", x, 13, COLOR_CYAN)
	b: Text
	add(&b, "Turn ")
	add_int(&b, g.turn)
	print(f, text(&b), x, 28, COLOR_LIGHT)
	money: Text
	add(&money, "BJ ")
	add_int(&money, g.empires[PLAYER].bj)
	print(f, text(&money), x + 9 * GLYPH_W, 28, COLOR_YELLOW)
	switch g.mode {
	case .Council:
		draw_empire_panel(f, g)
	case .Game_Over:
	case .Battle:
		draw_battle_panel(f, g)
	case .Choose_Race:
	case .Map:
		draw_star_panel(f, g)
	case .Colony, .Research:
		draw_empire_panel(f, g)
	case .Fleet:
		draw_fleet_panel(f, g)
	case .Destination:
		draw_destination_panel(f, g)
	}
	if g.mode == .Map || g.mode == .Colony {
		print(f, "R: research", x, RESEARCH_LINK_Y, COLOR_CYAN)
	} else if g.mode == .Research {
		print(f, "R: back to map", x, RESEARCH_LINK_Y, COLOR_CYAN)
	}
}

// The star under the cursor and yer ships there.
draw_star_panel :: proc(f: ^Frame, g: ^Game) {
	x := PANEL_TEXT_X
	y := 44
	s := &g.stars[g.cursor]
	draw_star_heading(f, g, g.cursor, y)
	y += 24
	if g.cursor == g.clubhouse && g.moth_alive {
		print(f, "Guarded by a", x, y, COLOR_ORANGE)
		print(f, "very large moth.", x, y + 9, COLOR_ORANGE)
		print(f, "Drawn by the", x, y + 18, COLOR_DARK)
		print(f, "porch light.", x, y + 27, COLOR_DARK)
		y += 40
	}
	r := &s.reports[PLAYER]
	if s.wormhole_known[PLAYER] {
		print(f, "A wormhole.", x, y, COLOR_PURPLE)
		y += 12
	} else if !r.filed {
		print(f, "Not surveyed.", x, y, COLOR_MID)
		y += 12
	} else {
		draw_gfx(f, .Planet, x, y - 2, PLANET_COLORS[r.planet])
		kind: Text
		add(&kind, SIZE_NAMES[r.size])
		add(&kind, " ")
		add(&kind, PLANET_NAMES[r.planet])
		print(f, text(&kind), x + 16, y, COLOR_LIGHT)
		y += 12
		if r.special != .None {
			print(f, SPECIAL_NAMES[r.special], x, y, COLOR_YELLOW)
			y += 10
		}
		if col := colony_at(g, g.cursor); col != nil {
			pop: Text
			add(&pop, g.cursor == g.home ? "Home, " : "Colony, ")
			add_int(&pop, col.households)
			add(&pop, "/")
			add_int(&pop, colony_max(g, g.cursor))
			print(f, text(&pop), x, y, COLOR_GREEN)
			y += 10
			if col.captured > 0 {
				who: Text
				add(&who, RACES[col.race].name)
				add(&who, ", for ")
				add_int(&who, ASSIMILATE_TURNS + 1 - col.captured)
				add(&who, " turns")
				print(f, text(&who), x, y, COLOR_ORANGE)
				y += 10
			}
		}
	}
	if g.empires[PLAYER].sees[g.cursor] {
		if c := any_colony(g, g.cursor); c != nil && c.owner != PLAYER {
			who: Text
			add(&who, "The ")
			add(&who, empire_name(g, c.owner))
			add(&who, "' colony")
			print(f, text(&who), x, y, EMPIRE_COLORS[c.owner])
			y += 10
			what: Text
			add_int(&what, c.households)
			add(&what, " households, ")
			add_int(&what, c.bases)
			add(&what, c.bases == 1 ? " base" : " bases")
			print(f, text(&what), x, y, COLOR_LIGHT)
			y += 10
		}
		for e in 1 ..< g.empire_count {
			if o := fleet_of(g, g.cursor, e); o != nil {
				who: Text
				add_int(&who, fleet_size(o))
				add(&who, " ")
				add(&who, RACES[g.empires[e].race].one)
				add(&who, " ships")
				print(f, text(&who), x, y, EMPIRE_COLORS[e])
				y += 10
			}
		}
	}
	y += 4
	fl := fleet_at(g, g.cursor)
	if fl != nil {
		print(f, "Yer ships here:", x, y, COLOR_WHITE)
		y += 10
		for c, t in fl.ships {
			if c == 0 {
				continue
			}
			line: Text
			add_int(&line, c)
			add(&line, " ")
			add(&line, SHIPS[t].name)
			print(f, text(&line), x + 6, y, COLOR_LIGHT)
			y += 9
		}
		y += 2
		fuel: Text
		if refuels_at(g, g.cursor, PLAYER) {
			add(&fuel, "Tanks full.")
		} else if stranded(g, fl) {
			add(&fuel, "Out of fuel.")
		} else {
			add(&fuel, "Fuel: ")
			add_int(&fuel, fleet_range(fl))
			add(&fuel, fleet_range(fl) == 1 ? " turn" : " turns")
		}
		print(f, text(&fuel), x, y, stranded(g, fl) ? COLOR_RED : COLOR_MID)
		y += 10
		if fl.ships[.Gas_Can] > 0 {
			cans: Text
			add(&cans, "Refills: ")
			add_int(&cans, fl.refills)
			draw_gfx(f, .Barrel, x, y - 2, COLOR_ORANGE)
			print(f, text(&cans), x + 14, y, COLOR_MID)
			y += 12
		}
		if due := owed(g, fl); due > 0 {
			u: Text
			add(&u, "Unpaid: ")
			add_int(&u, due)
			add(&u, " BJ")
			print(f, text(&u), x, y, COLOR_ORANGE)
		}
	}
	if colony_at(g, g.cursor) != nil {
		print(f, "Enter/OK: colony", x, ACTION_Y, COLOR_CYAN)
	} else if fl != nil {
		print(f, "Enter/OK: send", x, ACTION_Y, COLOR_CYAN)
	} else if g.cursor != g.home {
		// Straight-line distance from home, in cells.
		h := g.stars[g.home]
		dx, dy := s.x - h.x, s.y - h.y
		far: Text
		add_int(&far, isqrt(dx * dx + dy * dy))
		add(&far, " ly from home")
		print(f, text(&far), x, ACTION_Y, COLOR_MID)
	}
	due := 0
	for &o in g.fleets {
		if o.used && o.star == NO_STAR && o.to == g.cursor {
			due += 1
		}
	}
	if due > 0 {
		d: Text
		add_int(&d, due)
		add(&d, due == 1 ? " fleet on its way" : " fleets on their way")
		print(f, text(&d), x, BACK_Y, COLOR_LIGHT)
	}
}

// Name and lot of a star, with its picture.
draw_star_heading :: proc(f: ^Frame, g: ^Game, i: int, y: int) {
	x := PANEL_TEXT_X
	s := &g.stars[i]
	gfx := Gfx.Star_Dim
	color: u8 = COLOR_MID
	if s.wormhole_known[PLAYER] {
		gfx, color = .Wormhole, COLOR_PURPLE
	} else if s.reports[PLAYER].filed {
		gfx, color = .Star, COLOR_YELLOW
	}
	draw_gfx(f, gfx, x, y - 2, color)
	print(f, s.name, x + 16, y, COLOR_WHITE)
	lot: Text
	add(&lot, "Lot ")
	add_int(&lot, i + 1)
	print(f, text(&lot), x + 16, y + 10, COLOR_MID)
}

// The ships at the source star, each with how many are going.
draw_fleet_panel :: proc(f: ^Frame, g: ^Game) {
	x := PANEL_TEXT_X
	head: Text
	add(&head, "Send from Lot ")
	add_int(&head, g.source + 1)
	print(f, text(&head), x, 44, COLOR_WHITE)
	print(f, "Left/Right: count", x, 56, COLOR_DARK)
	rows, n := fleet_rows(g)
	for i in 0 ..< n {
		y := FLEET_TOP + i * ROW_H
		t := rows[i]
		selected := i == g.row
		if selected {
			fill_rect(f, x - 2, y - 1, PANEL_W - 2, ROW_H, COLOR_NAVY)
		}
		print(f, SHIPS[t].name, x, y, selected ? COLOR_WHITE : COLOR_LIGHT)
		count: Text
		add(&count, "<")
		add_int(&count, g.send[t])
		add(&count, ">")
		print(f, text(&count), x + COUNT_COL * GLYPH_W, y, g.send[t] > 0 ? COLOR_CYAN : COLOR_MID)
	}
	if src := fleet_at(g, g.source); src != nil {
		if due := owed(g, src); due > 0 {
			y := FLEET_TOP + n * ROW_H + 4
			if g.row == n {
				fill_rect(f, x - 2, y - 1, PANEL_W - 2, ROW_H, COLOR_NAVY)
			}
			pay: Text
			add(&pay, "Pay upgrades: ")
			add_int(&pay, due)
			print(f, text(&pay), x, y, g.empires[PLAYER].bj >= due ? COLOR_ORANGE : COLOR_RED)
		}
	}
	print(f, "Choose where >", x, ACTION_Y, COLOR_CYAN)
	print(f, "Back", x, BACK_Y, COLOR_MID)
}

// Where the ships would go, how long it takes and whether their fuel lasts.
draw_destination_panel :: proc(f: ^Frame, g: ^Game) {
	x := PANEL_TEXT_X
	print(f, "Send to:", x, 44, COLOR_WHITE)
	draw_star_heading(f, g, g.cursor, 58)
	trial := Fleet {
		ships = g.send,
	}
	if src := fleet_at(g, g.source); src != nil {
		trial.away = src.away
	}
	y := 84
	if g.cursor == g.source {
		print(f, "Pick another star.", x, y, COLOR_MID)
	} else {
		turns := trip_turns(g, g.source, g.cursor, fleet_speed(&trial))
		trip: Text
		add(&trip, "Trip: ")
		add_int(&trip, turns)
		add(&trip, turns == 1 ? " turn" : " turns")
		print(f, text(&trip), x, y, COLOR_LIGHT)
		fuel: Text
		add(&fuel, "Fuel: ")
		add_int(&fuel, fleet_range(&trial))
		add(&fuel, fleet_range(&trial) == 1 ? " turn" : " turns")
		print(f, text(&fuel), x, y + 10, COLOR_LIGHT)
		problem := send_problem(g, PLAYER, g.source, g.cursor, g.send)
		if problem != "" {
			print(f, problem, x, y + 24, COLOR_RED)
		} else if !refuels_at(g, g.cursor, PLAYER) && turns == fleet_range(&trial) {
			print(f, "Arrives empty.", x, y + 24, COLOR_ORANGE)
		}
	}
	print(f, "Enter/OK: send", x, ACTION_Y, COLOR_CYAN)
	print(f, "Back", x, BACK_Y, COLOR_MID)
}

draw_news :: proc(f: ^Frame, g: ^Game) {
	fill_rect(f, 0, VIEW_H * TILE, SCREEN_W, 1, COLOR_DARK)
	for i in 0 ..< NEWS_LINES {
		color: u8 = i == NEWS_LINES - 1 ? COLOR_WHITE : COLOR_MID
		print(f, message(&g.news[i]), NEWS_X, NEWS_Y + i * (GLYPH_H + 1), color)
	}
}

// Whole-number square root, rounded to nearest.
isqrt :: proc(n: int) -> int {
	r := 0
	for (r + 1) * (r + 1) <= n {
		r += 1
	}
	if n - r * r > r {
		r += 1
	}
	return r
}

// The empire's totals, beside the colony screen.
draw_empire_panel :: proc(f: ^Frame, g: ^Game) {
	x := PANEL_TEXT_X
	print(f, "Species", x, 44, COLOR_MID)
	print(f, RACES[g.empires[PLAYER].race].name, x + 11 * GLYPH_W, 44, COLOR_GREEN)
	colonies, households, made, rp := 0, 0, 0, 0
	for i in 0 ..< g.star_count {
		if c := colony_at(g, i); c != nil {
			colonies += 1
			households += c.households
			made += tax(g, i)
			rp += research_points(g, i)
		}
	}
	rows := [?]struct {
		label: string,
		value: int,
	}{{"Colonies", colonies}, {"Households", households}, {"BJ a turn", made}, {"RP a turn", rp}}
	for r, i in rows {
		print(f, r.label, x, 55 + i * 11, COLOR_MID)
		v: Text
		add_int(&v, r.value)
		print(f, text(&v), x + 11 * GLYPH_W, 55 + i * 11, COLOR_LIGHT)
	}
	// What a ship built today carries.
	print(f, "Ship kit:", x, 104, COLOR_WHITE)
	kit := empire_kit(g, PLAYER)
	for s, i in Kit_Stat {
		print(f, KIT_NAMES[s], x, 116 + int(i) * 10, COLOR_MID)
		v: Text
		add(&v, "+")
		add_int(&v, kit[s])
		print(f, text(&v), x + 11 * GLYPH_W, 116 + int(i) * 10, kit[s] > 0 ? COLOR_LIGHT : COLOR_DARK)
	}
	extra: Text
	add(&extra, "Factories ")
	add_int(&extra, factory_cost(g, PLAYER))
	add(&extra, " each")
	print(f, text(&extra), x, 180, COLOR_MID)
}

// The six fields, each with its slider, its next tech and how far along it is.
draw_research :: proc(f: ^Frame, g: ^Game) {
	res := &g.empires[PLAYER].tech
	x := COLONY_X
	print(f, "Book Club research", x, 6, COLOR_WHITE)
	total := 0
	for i in 0 ..< g.star_count {
		total += research_points(g, i)
	}
	head: Text
	add_int(&head, total)
	add(&head, " research a turn, shared among the hobbies.")
	print(f, text(&head), x, 18, COLOR_LIGHT)
	for fld in Field {
		row := int(fld)
		y := research_row_y(row)
		selected := g.row == row
		if selected {
			fill_rect(f, 0, y - 3, VIEW_W * TILE, RESEARCH_H - 2, COLOR_NAVY)
		}
		print(f, FIELD_NAMES[fld], x, y, selected ? COLOR_WHITE : COLOR_LIGHT)
		bx := x + BAR_COL * GLYPH_W
		bw := BAR_CELLS * GLYPH_W
		frame_rect(f, bx - 1, y - 1, bw + 2, 10, COLOR_DARK)
		fill_rect(f, bx, y, bw * res.slider[fld] / 100, 8, res.locked[fld] ? COLOR_MID : COLOR_CYAN)
		pct: Text
		add_int(&pct, res.slider[fld])
		add(&pct, "%")
		print(f, text(&pct), x + PCT_COL * GLYPH_W, y, COLOR_LIGHT)
		print(f, res.locked[fld] ? "L" : "-", x + LOCK_COL * GLYPH_W, y, res.locked[fld] ? COLOR_ORANGE : COLOR_DARK)
		k: Text
		add_int(&k, known_count(res, fld))
		add(&k, " of ")
		add_int(&k, OFFERED_PER_FIELD)
		print(f, text(&k), x + EFFECT_COL * GLYPH_W, y, COLOR_MID)
		next := next_tech(res, fld)
		line: Text
		if next < 0 {
			add(&line, "Nothing left to learn.")
		} else {
			add(&line, "Next: ")
			add(&line, TECHS[fld][next].name)
			add(&line, "  ")
			add_int(&line, res.stored[fld])
			add(&line, "/")
			add_int(&line, tech_cost(next + 1))
		}
		print(f, text(&line), x + 2 * GLYPH_W, y + 11, COLOR_MID)
	}
	by := research_row_y(RESEARCH_BACK_ROW)
	if g.row == RESEARCH_BACK_ROW {
		fill_rect(f, 0, by - 3, VIEW_W * TILE, 14, COLOR_NAVY)
	}
	print(f, "Back to the map", x, by, COLOR_MID)
	print(f, "Up/Down: pick. Left/Right: change. Enter/OK: lock.", x, VIEW_H * TILE - 12, COLOR_DARK)
}

// Turns until `stored` plus `per_turn` a turn reaches `cost`; 0 if it never will.
turns_to :: proc(stored, per_turn, cost: int) -> int {
	if stored >= cost {
		return 1
	}
	if per_turn <= 0 {
		return 0
	}
	return (cost - stored + per_turn - 1) / per_turn
}

// One colony, drawn where the map goes: its numbers, the five sliders, the ship order and the way out.
draw_colony :: proc(f: ^Frame, g: ^Game) {
	col := colony_at(g, g.source)
	if col == nil {
		return
	}
	s := &g.stars[g.source]
	x := COLONY_X
	head: Text
	add(&head, s.name)
	add(&head, " (Lot ")
	add_int(&head, g.source + 1)
	add(&head, ")")
	print(f, text(&head), x, 6, COLOR_WHITE)
	kind: Text
	add(&kind, SIZE_NAMES[s.size])
	add(&kind, " ")
	add(&kind, PLANET_NAMES[s.planet])
	if s.reports[PLAYER].special != .None {
		add(&kind, ", ")
		add(&kind, SPECIAL_NAMES[s.reports[PLAYER].special])
	}
	add(&kind, ". ")
	add(&kind, RACES[col.race].name)
	if col.captured > 0 {
		add(&kind, ", captured: ")
		add_int(&kind, ASSIMILATE_TURNS + 1 - col.captured)
		add(&kind, " turns to settle in")
	}
	draw_gfx(f, .Planet, x + 300, 4, PLANET_COLORS[s.planet])
	print(f, text(&kind), x, 16, COLOR_LIGHT)

	line1: Text
	add(&line1, "Households ")
	add_int(&line1, col.households)
	add(&line1, "/")
	add_int(&line1, colony_max(g, g.source))
	add(&line1, "   Factories ")
	add_int(&line1, col.factories)
	add(&line1, "/")
	add_int(&line1, col.households * FACTORIES_PER_HOUSEHOLD)
	add(&line1, "   Bases ")
	add_int(&line1, col.bases)
	print(f, text(&line1), x, 30, COLOR_LIGHT)
	line2: Text
	add(&line2, "Makes ")
	add_int(&line2, production(g, g.source))
	add(&line2, " a turn; ")
	add_int(&line2, tax(g, g.source))
	add(&line2, " to BJ. Waste ")
	add_int(&line2, col.waste)
	add(&line2, " (+")
	add_int(&line2, waste_made(g, col))
	add(&line2, " a turn)")
	print(f, text(&line2), x, 40, COLOR_LIGHT)

	for ch in Chore {
		row := int(ch)
		y := colony_row_y(row)
		selected := g.row == row
		if selected {
			fill_rect(f, 0, y - 3, VIEW_W * TILE, SLIDER_H, COLOR_NAVY)
		}
		print(f, CHORE_NAMES[ch], x, y, selected ? COLOR_WHITE : COLOR_LIGHT)
		bx := x + BAR_COL * GLYPH_W
		bw := BAR_CELLS * GLYPH_W
		frame_rect(f, bx - 1, y - 1, bw + 2, 10, COLOR_DARK)
		fill_rect(f, bx, y, bw * col.slider[ch] / 100, 8, col.locked[ch] ? COLOR_MID : COLOR_CYAN)
		pct: Text
		add_int(&pct, col.slider[ch])
		add(&pct, "%")
		print(f, text(&pct), x + PCT_COL * GLYPH_W, y, COLOR_LIGHT)
		print(f, col.locked[ch] ? "L" : "-", x + LOCK_COL * GLYPH_W, y, col.locked[ch] ? COLOR_ORANGE : COLOR_DARK)
		print(f, chore_effect(g, g.source, ch), x + EFFECT_COL * GLYPH_W, y, COLOR_MID)
	}

	rows_y := colony_row_y(BUILD_ROW)
	if g.row == BUILD_ROW {
		fill_rect(f, 0, rows_y - 3, VIEW_W * TILE, SLIDER_H, COLOR_NAVY)
	}
	print(f, "Parking builds", x, rows_y, g.row == BUILD_ROW ? COLOR_WHITE : COLOR_LIGHT)
	print(f, "<", x + BUILD_LEFT_COL * GLYPH_W, rows_y, COLOR_CYAN)
	print(f, SHIPS[col.build].name, x + (BUILD_LEFT_COL + 2) * GLYPH_W, rows_y, COLOR_WHITE)
	print(f, ">", x + BUILD_RIGHT_COL * GLYPH_W, rows_y, COLOR_CYAN)
	cost: Text
	add_int(&cost, SHIPS[col.build].cost)
	add(&cost, " each")
	print(f, text(&cost), x + EFFECT_COL * GLYPH_W, rows_y, COLOR_MID)

	ships_y := colony_row_y(SHIPS_ROW)
	if g.row == SHIPS_ROW {
		fill_rect(f, 0, ships_y - 3, VIEW_W * TILE, SLIDER_H, COLOR_NAVY)
	}
	print(f, fleet_at(g, g.source) != nil ? "Ships parked here >" : "No ships parked here", x, ships_y, COLOR_CYAN)
	back_y := colony_row_y(COLONY_BACK_ROW)
	if g.row == COLONY_BACK_ROW {
		fill_rect(f, 0, back_y - 3, VIEW_W * TILE, SLIDER_H, COLOR_NAVY)
	}
	print(f, "Back to the map", x, back_y, COLOR_MID)
	print(f, "Up/Down: pick. Left/Right: change. Enter/OK: lock.", x, VIEW_H * TILE - 12, COLOR_DARK)
}

// What a chore is doing this turn, in a few words.
chore_effect :: proc(g: ^Game, star: int, ch: Chore) -> string {
	@(static) b: Text
	b = {}
	col := colony_at(g, star)
	pts := chore_points(g, star, ch)
	switch ch {
	case .Parking:
		t := turns_to(col.stored[.Parking], pts, SHIPS[col.build].cost)
		if t == 0 {
			add(&b, "nothing")
		} else {
			add(&b, "ship in ")
			add_int(&b, t)
		}
	case .Fencing:
		t := turns_to(col.stored[.Fencing], pts, BASE_COST)
		if t == 0 {
			add(&b, "none")
		} else {
			add(&b, "base in ")
			add_int(&b, t)
		}
	case .Home_Improvement:
		if col.factories >= col.households * FACTORIES_PER_HOUSEHOLD {
			add(&b, "full; to BJ")
		} else {
			add(&b, "+")
			add_int(&b, (col.stored[.Home_Improvement] + pts) / FACTORY_COST)
			add(&b, " factories")
		}
	case .Lawn_Care:
		need := (col.waste + waste_made(g, col) + WASTE_CLEANED_PER_POINT - 1) / WASTE_CLEANED_PER_POINT
		if pts >= need {
			add(&b, "tidy")
		} else {
			add(&b, "messy")
		}
	case .Book_Club:
		add_int(&b, research_points(g, star))
		add(&b, " research")
	}
	return text(&b)
}

// The four species to choose from, each with its line and its trait.
draw_races :: proc(f: ^Frame, g: ^Game) {
	x := COLONY_X
	print(f, "Choose yer species", x, 6, COLOR_WHITE)
	print(f, "Two of the others will be yer neighbours. They will hate you.", x, 18, COLOR_LIGHT)
	for r in Race {
		row := int(r)
		y := race_row_y(row)
		if g.row == row {
			fill_rect(f, 0, y - 3, VIEW_W * TILE, RACE_H - 4, COLOR_NAVY)
		}
		info := RACES[r]
		print(f, info.name, x, y, g.row == row ? COLOR_WHITE : COLOR_LIGHT)
		print(f, info.blurb, x + 2 * GLYPH_W, y + 11, COLOR_MID)
		print(f, info.trait, x + 2 * GLYPH_W, y + 22, COLOR_CYAN)
	}
	print(f, "Slice 1 of 3. Still to come: diplomacy and spies, bylaws,", x, VIEW_H * TILE - 34, COLOR_MID)
	print(f, "the other six species, bigger clusters and more rivals.", x, VIEW_H * TILE - 24, COLOR_MID)
	print(f, "Up/Down: pick. Enter/OK or a second tap: choose.", x, VIEW_H * TILE - 12, COLOR_DARK)
}

SHIP_GFX := [Ship_Type]Gfx {
	.Inspector     = .Scooter,
	.Moving_Van    = .Van,
	.Carpool       = .Bus,
	.Gas_Can       = .Barrel,
	.Golf_Cart     = .Car,
	.Pickup        = .Truck,
	.Monster_Truck = .Tank,
}

stack_name :: proc(s: ^Stack) -> string {
	return s.moth ? "Space moth" : s.base ? "Defence base" : SHIPS[s.kind].name
}

// The battle grid: each stack as its picture in its empire's colour, with its count beneath; the
// target in red brackets.
draw_battle :: proc(f: ^Frame, g: ^Game) {
	bt := &g.battle
	s := &g.stars[bt.star]
	head: Text
	add(&head, "Battle at ")
	add(&head, s.name)
	add(&head, " (Lot ")
	add_int(&head, bt.star + 1)
	add(&head, "), round ")
	add_int(&head, bt.round + 1)
	print(f, text(&head), BATTLE_X, 6, COLOR_WHITE)
	vs: Text
	add(&vs, "Yer ")
	add(&vs, RACES[g.empires[PLAYER].race].name)
	add(&vs, bt.owners[1] == MOTH ? " against a very large space moth" : " against the ")
	if bt.owners[1] != MOTH {
		add(&vs, empire_name(g, bt.owners[1]))
	}
	print(f, text(&vs), BATTLE_X, 15, COLOR_LIGHT)
	for gy in 0 ..< GRID_H {
		for gx in 0 ..< GRID_W {
			frame_rect(f, BATTLE_X + gx * BATTLE_CELL, BATTLE_Y + gy * BATTLE_CELL, BATTLE_CELL + 1, BATTLE_CELL + 1, COLOR_DARK)
		}
	}
	for i in 0 ..< bt.n {
		st := &bt.stacks[i]
		if !alive(st) {
			continue
		}
		cx, cy := BATTLE_X + st.x * BATTLE_CELL, BATTLE_Y + st.y * BATTLE_CELL
		color := owner_color(bt.owners[st.side])
		if st.moth {
			draw_gfx(f, .Moth_TL, cx, cy, color)
			draw_gfx(f, .Moth_TR, cx + TILE, cy, color)
			draw_gfx(f, .Moth_BL, cx, cy + TILE, color)
			draw_gfx(f, .Moth_BR, cx + TILE, cy + TILE, color)
			if i == bt.target {
				frame_rect(f, cx + 1, cy + 1, BATTLE_CELL - 1, BATTLE_CELL - 1, COLOR_RED)
			}
			continue
		}
		draw_gfx(f, st.base ? .Wall : SHIP_GFX[st.kind], cx + 6, cy + 2, color)
		n: Text
		add_int(&n, st.count)
		print(f, text(&n), cx + (BATTLE_CELL - text_width(text(&n))) / 2, cy + 15, COLOR_WHITE)
		if i == bt.target {
			frame_rect(f, cx + 1, cy + 1, BATTLE_CELL - 1, BATTLE_CELL - 1, COLOR_RED)
		}
	}
	print(f, "Left/Right: target. Up/Down: pick. Enter/OK: do it.", BATTLE_X, VIEW_H * TILE - 12, COLOR_DARK)
}

// Both sides' stacks, the target, and what to do.
draw_battle_panel :: proc(f: ^Frame, g: ^Game) {
	bt := &g.battle
	x := PANEL_TEXT_X
	y := 44
	for side in 0 ..< 2 {
		print(f, side == 0 ? "Yers:" : "Theirs:", x, y, owner_color(bt.owners[side]))
		y += 10
		for i in 0 ..< bt.n {
			st := &bt.stacks[i]
			if st.side != side || !alive(st) {
				continue
			}
			if y > BATTLE_ACTION_Y - 22 {
				break // a long list is cut short rather than run into the actions
			}
			line: Text
			add_int(&line, st.count)
			add(&line, " ")
			add(&line, stack_name(st))
			print(f, text(&line), x + 6, y, i == bt.target ? COLOR_RED : COLOR_LIGHT)
			y += 9
		}
		y += 4
	}
	for row in 0 ..< BATTLE_ROWS {
		ry := battle_action_y(row)
		if bt.row == row {
			fill_rect(f, x - 2, ry - 1, PANEL_W - 2, ROW_H, COLOR_NAVY)
		}
		print(f, BATTLE_ROW_NAMES[row], x, ry, COLOR_CYAN)
	}
}

// The end: conquered, or out.
draw_game_over :: proc(f: ^Frame, g: ^Game) {
	x := COLONY_X
	won := g.outcome == .Won
	print(f, won ? "The cluster is yers." : "Yer empire is no more.", x, 40, won ? COLOR_YELLOW : COLOR_RED)
	lines: [3]string
	if won {
		lines = {"Every other species has been moved out.", "The Homeowners' Association has been notified.", "Nobody is left to read the notice."}
	} else {
		lines = {"Yer last colony has changed hands.", "The Homeowners' Association has been notified.", "Yer dues are paid up to the end of the month."}
	}
	for l, i in lines {
		print(f, l, x, 62 + i * 12, COLOR_LIGHT)
	}
	t: Text
	add(&t, "Turn ")
	add_int(&t, g.turn)
	add(&t, ". Colonies: ")
	add_int(&t, colonies_of(g, PLAYER))
	add(&t, ".")
	print(f, text(&t), x, 110, COLOR_MID)
	print(f, "Enter/OK or a tap: a new cluster.", x, 140, COLOR_CYAN)
}

// The minutes of a meeting, and the vote if there is one.
draw_council :: proc(f: ^Frame, g: ^Game) {
	c := &g.council
	x := COLONY_X
	for i in 0 ..< c.lines {
		color: u8 = i == 0 ? COLOR_WHITE : COLOR_LIGHT
		print(f, message(&c.minutes[i]), x, MINUTES_Y + i * 10, color)
	}
	if c.voting {
		print(f, "Yer vote:", x, VOTE_Y - 14, COLOR_WHITE)
		for row in 0 ..< COUNCIL_CHOICES {
			y := vote_row_y(row)
			if c.choice == row {
				fill_rect(f, 0, y - 2, VIEW_W * TILE, 11, COLOR_NAVY)
			}
			b: Text
			if row < 2 {
				cand := c.candidates[row]
				add(&b, "Vote for ")
				add(&b, cand == PLAYER ? "yerselves" : who(g, cand))
			} else {
				add(&b, "Abstain")
			}
			print(f, text(&b), x, y, COLOR_CYAN)
		}
		print(f, "Up/Down: pick. Enter/OK or a tap: vote.", x, VIEW_H * TILE - 12, COLOR_DARK)
	} else {
		print(f, "Enter/OK or a tap: close the minutes.", x, VIEW_H * TILE - 12, COLOR_CYAN)
	}
	if c.ever_won {
		print(f, "You have been President. That counts as winning.", x, VIEW_H * TILE - 24, COLOR_YELLOW)
	}
}
