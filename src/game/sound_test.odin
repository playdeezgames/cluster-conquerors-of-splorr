#+build !js
package game

import "core:testing"

// Runs a command the way the page does and gives the sound it would play.
sound_of :: proc(g: ^Game, c: Command) -> Sfx {
	b := sound_look(g)
	command(g, c)
	return sound_after(b, g, c == .Confirm, c <= .South_East)
}

@(test)
test_sounds :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, sound_of(g, .East), Sfx.Blip)
	g.cursor = g.home
	testing.expect_value(t, sound_of(g, .Confirm), Sfx.Open) // yer home colony
	testing.expect_value(t, sound_of(g, .South), Sfx.Blip)
	testing.expect_value(t, sound_of(g, .Cancel), Sfx.Close)
	s := sound_of(g, .End_Turn)
	testing.expect(t, s == .Turn || s == .Gavel || s == .Hit, "end of turn")
	// A colony settled, then lost; the end of the Metaphor.
	b := sound_look(g)
	for i in 0 ..< g.star_count {
		if any_colony(g, i) == nil && i != g.home {
			found_colony(g, i, 1)
			break
		}
	}
	testing.expect_value(t, sound_after(b, g, false, false), Sfx.Gain)
	b = sound_look(g)
	g.outcome = .Lost
	testing.expect_value(t, sound_after(b, g, false, false), Sfx.Lose)
	// The setup screens make no colony sounds.
	b = sound_look(g)
	b.mode = .New_Game
	b.colonies = 0
	testing.expect(t, sound_after(b, g, true, false) != .Gain)
}
