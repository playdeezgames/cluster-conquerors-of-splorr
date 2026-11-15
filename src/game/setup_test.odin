#+build !js
package game

import "core:testing"

// The new-game screen (slice 3 step 1): after the species, pick the cluster's size, then start.
@(test)
test_new_game_screen :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	start_choosing(g)
	command(g, .South) // Owls
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.New_Game)
	testing.expect_value(t, g.setup.size, Cluster_Size.Small)
	command(g, .East)
	command(g, .East)
	testing.expect_value(t, g.setup.size, Cluster_Size.Large)
	command(g, .West)
	command(g, .West)
	command(g, .West)
	testing.expect_value(t, g.setup.size, Cluster_Size.Huge) // round the end
	// Escape goes back to the species, keeping the choice.
	command(g, .Cancel)
	testing.expect_value(t, g.mode, Mode.Choose_Race)
	testing.expect_value(t, g.row, int(Race.Owls))
	command(g, .Confirm)
	testing.expect_value(t, g.setup.size, Cluster_Size.Huge)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, g.star_count, CLUSTERS[.Huge].stars)
	testing.expect_value(t, g.empires[PLAYER].race, Race.Owls)
	testing.expect_value(t, colony_at(g, g.home).race, Race.Owls)
	testing.expect(t, g.empires[1].race != .Owls && g.empires[2].race != .Owls)
	// The same seed and size give the same cluster.
	h := new(Game)
	defer free(h)
	init_game(h, SEED, {size = .Huge})
	testing.expect(t, h.stars[h.home].x == g.stars[g.home].x && h.stars[h.home].y == g.stars[g.home].y)
	// A new cluster after the game ends keeps the size.
	g.mode = .Game_Over
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Choose_Race)
	testing.expect_value(t, g.setup.size, Cluster_Size.Huge)
	testing.expect_value(t, g.star_count, CLUSTERS[.Huge].stars)
}

@(test)
test_new_game_by_pointer :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	start_choosing(g)
	pick_race(g, .Rabbits)
	size_y := new_game_row_y(int(New_Game_Row.Size)) + 3
	right := COLONY_X + (NEW_GAME_VALUE_COL + 8) * GLYPH_W
	left := COLONY_X + (NEW_GAME_VALUE_COL + 1) * GLYPH_W
	pointer(g, right, size_y, .Touch) // the row is already picked: turns it up
	testing.expect_value(t, g.setup.size, Cluster_Size.Medium)
	pointer(g, left, size_y, .Touch)
	pointer(g, left, size_y, .Touch)
	testing.expect_value(t, g.setup.size, Cluster_Size.Huge)
	start_y := new_game_row_y(int(New_Game_Row.Start)) + 3
	pointer(g, left, start_y, .Touch) // picks Start
	testing.expect_value(t, g.mode, Mode.New_Game)
	pointer(g, left, start_y, .Touch) // starts
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, g.star_count, CLUSTERS[.Huge].stars)
	testing.expect_value(t, g.empires[PLAYER].race, Race.Rabbits)
}

// Every size plays: 60 turns of the computer playing every side, nothing out of the map.
@(test)
test_every_size_plays :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for size in Cluster_Size {
		init_game(g, SEED, {size = size})
		for _ in 0 ..< 60 {
			if g.outcome != .Playing {
				break
			}
			ai_turn(g, PLAYER)
			next_turn(g)
			for g.mode == .Battle {
				battle_action(g, 1)
			}
			for g.council.ruling {
				c := &g.council
				give_ruling(g, ai_ruling(g, PLAYER, &c.docket[c.docket_i]))
			}
			if g.council.bylaw_voting {
				cast_bylaw_votes(g, .Abstain)
			}
			if g.council.voting {
				cast_votes(g, .Abstain)
			}
			for g.mode == .Doormat {
				answer_doormat(g, ai_doormat_sign(g))
			}
			g.mode = g.outcome == .Playing ? .Map : g.mode
		}
		testing.expectf(t, g.turn > 40, "%v: stopped at turn %v", size, g.turn)
		for i in 0 ..< g.star_count {
			s := g.stars[i]
			testing.expect(t, s.x >= 0 && s.x < g.galaxy_w && s.y >= 0 && s.y < g.galaxy_h)
		}
		g.cursor = g.star_count - 1
		ox, oy := view_origin(g)
		testing.expect(t, ox >= 0 && oy >= 0 && ox + VIEW_W <= g.galaxy_w && oy + VIEW_H <= g.galaxy_h)
	}
}
