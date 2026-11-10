#+build !js
package game

import "core:testing"

@(test)
test_cluster_starts_at_home :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	testing.expect_value(t, g.star_count, 20)
	testing.expect_value(t, g.selected, g.home)
	testing.expect_value(t, star_at(g, g.cx, g.cy), g.home)
	testing.expect(t, g.stars[g.home].known)
	for i in 0 ..< g.star_count {
		s := g.stars[i]
		testing.expect(t, s.x >= 0 && s.x < GALAXY_W && s.y >= 0 && s.y < GALAXY_H)
		testing.expect(t, i == g.home || !s.known)
		for j in 0 ..< i {
			testing.expect(t, g.stars[j].x != s.x || g.stars[j].y != s.y)
		}
	}
}

@(test)
test_cursor_moves_and_stays_inside :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	x, y := g.cx, g.cy
	command(g, .North_East)
	testing.expect_value(t, g.cx, x + 1)
	testing.expect_value(t, g.cy, y - 1)
	for _ in 0 ..< 100 {
		command(g, .North_West)
	}
	testing.expect_value(t, g.cx, 0)
	testing.expect_value(t, g.cy, 0)
	ox, oy := view_origin(g)
	testing.expect_value(t, ox, 0)
	testing.expect_value(t, oy, 0)
	for _ in 0 ..< 100 {
		command(g, .South_East)
	}
	testing.expect_value(t, g.cx, GALAXY_W - 1)
	testing.expect_value(t, g.cy, GALAXY_H - 1)
	ox, oy = view_origin(g)
	testing.expect_value(t, ox, GALAXY_W - VIEW_W)
	testing.expect_value(t, oy, GALAXY_H - VIEW_H)
	command(g, .Cancel)
	testing.expect_value(t, star_at(g, g.cx, g.cy), g.home)
}

@(test)
test_confirm_selects_and_names :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	command(g, .Confirm)
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "Pollux (Lot 8), yer home.")
	other := g.stars[0]
	g.cx, g.cy = other.x, other.y
	command(g, .Confirm)
	testing.expect_value(t, g.selected, 0)
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "An unknown star (Lot 1). Not surveyed.")
	g.cx, g.cy = other.x, other.y + 1
	command(g, .Confirm)
	testing.expect_value(t, g.selected, NO_STAR)
}

@(test)
test_end_turn_counts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	command(g, .End_Turn)
	command(g, .End_Turn)
	testing.expect_value(t, g.turn, 3)
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "Turn 3. The HOA has not met yet.")
}

@(test)
test_pointer_moves_the_cursor :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	ox, oy := view_origin(g)
	s := g.stars[g.home]
	x, y, ok := screen_to_cell(g, MAP_X + (s.x - ox) * TILE + 5, MAP_Y + (s.y - oy) * TILE + 5)
	testing.expect(t, ok)
	testing.expect_value(t, x, s.x)
	testing.expect_value(t, y, s.y)
	_, _, ok = screen_to_cell(g, PANEL_X + 10, 10)
	testing.expect(t, !ok)
	pointer(g, MAP_X + 5, MAP_Y + 5, .Touch)
	testing.expect_value(t, g.cx, ox)
	testing.expect_value(t, g.cy, oy)
}

@(test)
test_news_keeps_the_newest_and_cuts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g)
	say(g, "last")
	testing.expect_value(t, message(&g.news[NEWS_LINES - 1]), "last")
	long := "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
	say(g, long)
	testing.expect(t, message(&g.news[NEWS_LINES - 1]) == long[:NEWS_COLS])
	b: Text
	add_int(&b, -1205)
	testing.expect_value(t, text(&b), "-1205")
}

@(test)
test_frame_draws_home_star_and_panel :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	f := new(Frame)
	defer free(f)
	init_game(g)
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
