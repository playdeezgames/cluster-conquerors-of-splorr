#+build !js
package game

import "core:testing"

@(test)
test_save_and_load_carry_on_the_same :: proc(t: ^testing.T) {
	a := new(Game)
	defer free(a)
	b := new(Game)
	defer free(b)
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	init_game(a, SEED)
	for _ in 0 ..< 30 {
		end_turn(a)
		for a.mode == .Battle {
			battle_action(a, 1)
		}
	}
	testing.expect_value(t, write_save(a, buf), SAVE_SIZE)
	init_game(b, SEED + 99)
	testing.expect(t, read_save(b, buf))
	testing.expect_value(t, b.turn, a.turn)
	for i in 0 ..< a.star_count {
		testing.expect_value(t, b.stars[i].name, a.stars[i].name)
	}
	// Both go on exactly alike, the random draws included.
	for _ in 0 ..< 30 {
		end_turn(a)
		end_turn(b)
		for a.mode == .Battle {
			battle_action(a, 1)
		}
		for b.mode == .Battle {
			battle_action(b, 1)
		}
	}
	testing.expect(t, a.stars == b.stars)
	testing.expect(t, a.fleets == b.fleets)
	testing.expect_value(t, a.empires[PLAYER].bj, b.empires[PLAYER].bj)
	testing.expect_value(t, a.rng.state, b.rng.state)
}

@(test)
test_a_bad_save_is_ignored :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	write_save(g, buf)
	turn := g.turn
	testing.expect(t, !read_save(g, buf[:SAVE_SIZE - 1])) // cut short
	buf[0] ~= 0xFF // another magic
	testing.expect(t, !read_save(g, buf))
	testing.expect_value(t, g.turn, turn)
	testing.expect(t, g.stars[0].name != "")
}
