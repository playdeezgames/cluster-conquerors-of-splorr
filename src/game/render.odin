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

draw_map :: proc(f: ^Frame, g: ^Game) {
	ox, oy := view_origin(g)
	for vy in 0 ..< VIEW_H {
		for vx in 0 ..< VIEW_W {
			if speck(ox + vx, oy + vy) {
				set_px(f, MAP_X + vx * TILE + 6, MAP_Y + vy * TILE + 6, COLOR_DARK)
			}
		}
	}
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		vx, vy := s.x - ox, s.y - oy
		if vx < 0 || vy < 0 || vx >= VIEW_W || vy >= VIEW_H {
			continue
		}
		sx, sy := MAP_X + vx * TILE, MAP_Y + vy * TILE
		if s.known {
			draw_gfx(f, .Star, sx, sy, COLOR_YELLOW)
		} else {
			draw_gfx(f, .Star_Dim, sx, sy, COLOR_MID)
		}
		if i == g.home {
			frame_rect(f, sx - 1, sy - 1, TILE + 2, TILE + 2, COLOR_GREEN)
		}
	}
	// The cursor: corner brackets, so the star under it stays visible.
	cur := g.stars[g.cursor]
	cx, cy := MAP_X + (cur.x - ox) * TILE - 2, MAP_Y + (cur.y - oy) * TILE - 2
	n := TILE + 4
	for c in ([4][2]int{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
		x0, y0 := cx + c.x * (n - 4), cy + c.y * (n - 1)
		fill_rect(f, x0, y0, 4, 1, COLOR_CYAN)
		x1, y1 := cx + c.x * (n - 1), cy + c.y * (n - 4)
		fill_rect(f, x1, y1, 1, 4, COLOR_CYAN)
	}
}

draw_panel :: proc(f: ^Frame, g: ^Game) {
	fill_rect(f, PANEL_X - 2, 0, 1, VIEW_H * TILE, COLOR_DARK)
	x := PANEL_X + 2
	print(f, "Cluster Conquerors", x, 4, COLOR_CYAN)
	print(f, "of SPLORR!!", x, 13, COLOR_CYAN)
	b: Text
	add(&b, "Turn ")
	add_int(&b, g.turn)
	print(f, text(&b), x, 28, COLOR_LIGHT)
	print(f, "BJ      --", x, 38, COLOR_MID)

	y := 56
	s := &g.stars[g.cursor]
	draw_gfx(f, s.known ? .Star : .Star_Dim, x, y - 2, s.known ? COLOR_YELLOW : COLOR_MID)
	print(f, s.name, x + 16, y, COLOR_WHITE)
	lot: Text
	add(&lot, "Lot ")
	add_int(&lot, g.cursor + 1)
	print(f, text(&lot), x + 16, y + 10, COLOR_MID)
	y += 26
	if !s.known {
		print(f, "Not surveyed.", x, y, COLOR_MID)
	} else {
		draw_gfx(f, .Planet, x, y - 2, PLANET_COLORS[s.planet])
		kind: Text
		add(&kind, SIZE_NAMES[s.size])
		add(&kind, " ")
		add(&kind, PLANET_NAMES[s.planet])
		print(f, text(&kind), x + 16, y, COLOR_LIGHT)
		y += 12
		if s.special != .None {
			print(f, SPECIAL_NAMES[s.special], x, y, COLOR_YELLOW)
			y += 12
		}
		if g.cursor == g.home {
			print(f, "Yer home world", x + 16, y, COLOR_GREEN)
			y += 14
			draw_gfx(f, .Van, x, y - 2, COLOR_WHITE)
			print(f, "1 Moving Van", x + 16, y, COLOR_LIGHT)
		}
	}
	if g.cursor != g.home {
		// Straight-line distance from home, in cells; fleets and travel time arrive in step 2.
		h := g.stars[g.home]
		dx, dy := s.x - h.x, s.y - h.y
		d := isqrt(dx * dx + dy * dy)
		far: Text
		add_int(&far, d)
		add(&far, " ly from home")
		print(f, text(&far), x, VIEW_H * TILE - 26, COLOR_MID)
	}
	print(f, "Slice 1, step 1", x, VIEW_H * TILE - 12, COLOR_DARK)
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
