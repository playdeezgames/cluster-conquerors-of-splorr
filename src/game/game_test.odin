#+build !js
package game

import "core:testing"

SEED :: 12345

@(test)
test_cluster_is_well_formed :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 500 {
		init_game(g, seed)
		testing.expect_value(t, g.star_count, STAR_COUNT)
		wormholes := 0
		for i in 0 ..< g.star_count {
			s := g.stars[i]
			testing.expect(t, s.x >= EDGE && s.x < GALAXY_W - EDGE && s.y >= EDGE && s.y < GALAXY_H - EDGE)
			testing.expect(t, i == g.home || !s.known)
			if s.wormhole {
				wormholes += 1
			}
			for j in 0 ..< i {
				o := g.stars[j]
				dx, dy := o.x - s.x, o.y - s.y
				testing.expect(t, dx * dx + dy * dy >= MIN_SPACING * MIN_SPACING)
				testing.expect(t, o.name != s.name)
				// Reading order, so Lot 1 is top left.
				testing.expect(t, o.y < s.y || (o.y == s.y && o.x < s.x))
			}
		}
		testing.expect_value(t, wormholes, WORMHOLES)
		h := g.stars[g.home]
		testing.expect(t, h.known && !h.wormhole)
		testing.expect_value(t, h.planet, Planet_Type.Terran)
		testing.expect_value(t, h.size, Planet_Size.Medium)
		testing.expect_value(t, g.cursor, g.home)
	}
}

@(test)
test_same_seed_same_cluster :: proc(t: ^testing.T) {
	a := new(Game)
	defer free(a)
	b := new(Game)
	defer free(b)
	init_game(a, SEED)
	init_game(b, SEED)
	testing.expect(t, a.stars == b.stars)
	testing.expect_value(t, a.home, b.home)
	init_game(b, SEED + 1)
	testing.expect(t, a.stars != b.stars)
}

// Every star can be reached from home with the eight directions alone (keys, d-pad, stick).
@(test)
test_every_star_reachable_by_direction :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 500 {
		init_game(g, seed)
		seen: [MAX_STARS]bool
		queue: [MAX_STARS]int
		head, tail := 0, 0
		seen[g.home] = true
		queue[tail] = g.home
		tail += 1
		for head < tail {
			from := queue[head]
			head += 1
			for c in Command.North ..= Command.South_East {
				d := DIRECTION[c]
				to := star_toward(g, from, d.x, d.y)
				if to != NO_STAR && !seen[to] {
					seen[to] = true
					queue[tail] = to
					tail += 1
				}
			}
		}
		if !testing.expectf(t, tail == g.star_count, "seed %v: %v of %v stars reachable", seed, tail, g.star_count) {
			return
		}
	}
}

@(test)
test_directions_go_the_right_way :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 100 {
		init_game(g, seed)
		for from in 0 ..< g.star_count {
			for c in Command.North ..= Command.South_East {
				d := DIRECTION[c]
				to := star_toward(g, from, d.x, d.y)
				if to == NO_STAR {
					continue
				}
				vx, vy := g.stars[to].x - g.stars[from].x, g.stars[to].y - g.stars[from].y
				testing.expect(t, vx * d.x + vy * d.y > 0)
			}
		}
	}
}

@(test)
test_cursor_moves_and_returns_home :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	moved := false
	for c in Command.North ..= Command.South_East {
		command(g, c)
		if g.cursor != g.home {
			moved = true
			break
		}
	}
	testing.expect(t, moved)
	command(g, .Cancel)
	testing.expect_value(t, g.cursor, g.home)
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "Back to yer home star.")
}

@(test)
test_confirm_describes :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .Confirm)
	b: Text
	add(&b, g.stars[g.home].name)
	add(&b, " (Lot ")
	add_int(&b, g.home + 1)
	add(&b, "): yer home, a Medium Terran world.")
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), text(&b))
	other := (g.home + 1) % g.star_count
	g.cursor = other
	command(g, .Confirm)
	b = {}
	add(&b, g.stars[other].name)
	add(&b, " (Lot ")
	add_int(&b, other + 1)
	add(&b, "): not surveyed.")
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), text(&b))
}

@(test)
test_end_turn_counts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .End_Turn)
	command(g, .End_Turn)
	testing.expect_value(t, g.turn, 3)
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "Turn 3. The HOA has not met yet.")
}

@(test)
test_pointer_picks_nearby_star :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	ox, oy := view_origin(g)
	// Find a star other than home inside the view, and tap the cell beside it.
	target := NO_STAR
	for i in 0 ..< g.star_count {
		s := g.stars[i]
		if i != g.home && s.x - ox >= 1 && s.y - oy >= 0 && s.x - ox < VIEW_W && s.y - oy < VIEW_H {
			target = i
			break
		}
	}
	testing.expect(t, target != NO_STAR)
	s := g.stars[target]
	pointer(g, MAP_X + (s.x - 1 - ox) * TILE + 5, MAP_Y + (s.y - oy) * TILE + 5, .Touch)
	testing.expect_value(t, g.cursor, target)
	_, _, ok := screen_to_cell(g, PANEL_X + 10, 10)
	testing.expect(t, !ok)
	// Empty space far from any star leaves the cursor alone.
	before := g.cursor
	for y in 0 ..< VIEW_H {
		for x in 0 ..< VIEW_W {
			ox2, oy2 := view_origin(g)
			if star_near(g, ox2 + x, oy2 + y, 1) == NO_STAR {
				pointer(g, MAP_X + x * TILE + 5, MAP_Y + y * TILE + 5, .Mouse)
				testing.expect_value(t, g.cursor, before)
				testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "Empty space. Nobody owns it yet.")
				return
			}
		}
	}
}

@(test)
test_news_keeps_the_newest_and_cuts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	say(g, "last")
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "last")
	long := "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
	say(g, long)
	testing.expect(t, message(&g.news[NEWS_LINES - 1]) == long[:NEWS_COLS])
	b: Text
	add_int(&b, -1205)
	testing.expect_value(t, text(&b), "-1205")
	testing.expect_value(t, isqrt(50), 7)
	testing.expect_value(t, isqrt(56), 7)
	testing.expect_value(t, isqrt(57), 8)
}

@(test)
test_frame_draws_home_star_and_panel :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	f := new(Frame)
	defer free(f)
	init_game(g, SEED)
	draw_game(f, g)
	ox, oy := view_origin(g)
	s := g.stars[g.home]
	lit := 0
	for yy in 0 ..< TILE {
		for xx in 0 ..< TILE {
			if get_px(f, MAP_X + (s.x - ox) * TILE + xx, MAP_Y + (s.y - oy) * TILE + yy) == COLOR_YELLOW {
				lit += 1
			}
		}
	}
	testing.expect(t, lit > 10)
	title := 0
	for yy in 4 ..< 12 {
		for xx in PANEL_X ..< SCREEN_W {
			if get_px(f, xx, yy) == COLOR_CYAN {
				title += 1
			}
		}
	}
	testing.expect(t, title > 50)
	resolve(f)
	testing.expect_value(t, f.rgba[0] >> 24, 0xFF)
}

// Every star name fits beside its icon in the panel.
@(test)
test_names_fit_the_panel :: proc(t: ^testing.T) {
	for name in STAR_NAMES {
		testing.expect(t, text_width(name) <= PANEL_W - 4 - 16)
	}
	for name in SPECIAL_NAMES {
		testing.expect(t, text_width(name) <= PANEL_W - 4)
	}
}
