package game

// Draws the play screen: star map, side panel and news ticker.

draw_game :: proc(f: ^Frame, g: ^Game) {
	cls(f, COLOR_BLACK)
	draw_map(f, g)
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
		color: u8 = send_problem(g, g.source, g.cursor, g.send) == "" ? COLOR_CYAN : COLOR_RED
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
		if s.wormhole_known {
			draw_gfx(f, .Wormhole, sx, sy, COLOR_PURPLE)
		} else if s.report.filed {
			draw_gfx(f, .Star, sx, sy, COLOR_YELLOW)
		} else {
			draw_gfx(f, .Star_Dim, sx, sy, COLOR_MID)
		}
		if i == g.home {
			frame_rect(f, sx - 1, sy - 1, TILE + 2, TILE + 2, COLOR_GREEN)
		}
		// Yer ships here: a little flag at the top right, red if they are out of fuel.
		if fl := fleet_at(g, i); fl != nil {
			color: u8 = stranded(g, fl) ? COLOR_RED : COLOR_LIME
			fill_rect(f, sx + TILE - 1, sy - 3, 1, 6, COLOR_LIGHT)
			fill_rect(f, sx + TILE, sy - 3, 3, 3, color)
		}
	}
	// Fleets in transit, part of the way along.
	for &fl in g.fleets {
		if !fl.used || fl.star != NO_STAR {
			continue
		}
		a, b := g.stars[fl.from], g.stars[fl.to]
		done := fl.total - fl.left
		x := a.x * TILE + (b.x - a.x) * TILE * done / max(1, fl.total)
		y := a.y * TILE + (b.y - a.y) * TILE * done / max(1, fl.total)
		sx, sy := MAP_X + x - ox * TILE, MAP_Y + y - oy * TILE
		if on_map(sx + 6, sy + 6) {
			draw_gfx(f, .Van, sx, sy, COLOR_WHITE)
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
	switch g.mode {
	case .Map:
		draw_star_panel(f, g)
	case .Fleet:
		draw_fleet_panel(f, g)
	case .Destination:
		draw_destination_panel(f, g)
	}
	print(f, "Slice 1, step 2", x, VIEW_H * TILE - 12, COLOR_DARK)
}

// The star under the cursor and yer ships there.
draw_star_panel :: proc(f: ^Frame, g: ^Game) {
	x := PANEL_TEXT_X
	y := 44
	s := &g.stars[g.cursor]
	draw_star_heading(f, g, g.cursor, y)
	y += 24
	r := &s.report
	if s.wormhole_known {
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
		if g.cursor == g.home {
			print(f, "Yer home world", x, y, COLOR_GREEN)
			y += 10
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
		if refuels_at(g, g.cursor) {
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
		}
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
	if s.wormhole_known {
		gfx, color = .Wormhole, COLOR_PURPLE
	} else if s.report.filed {
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
		problem := send_problem(g, g.source, g.cursor, g.send)
		if problem != "" {
			print(f, problem, x, y + 24, COLOR_RED)
		} else if !refuels_at(g, g.cursor) && turns == fleet_range(&trial) {
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
