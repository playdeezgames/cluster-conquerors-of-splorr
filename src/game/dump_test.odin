#+build !js
package game

// Writes a real frame for screenshots when run with -define:DUMP_PLAY=<path.ppm> (tools/make_shots.sh).
// Without the define it does nothing.

import "core:os"
import "core:testing"

DUMP_PLAY :: #config(DUMP_PLAY, "")
DUMP_SEED :: #config(DUMP_SEED, 8)

@(test)
test_dump_play :: proc(t: ^testing.T) {
	when DUMP_PLAY != "" {
		g := new(Game)
		defer free(g)
		init_game(g, u64(DUMP_SEED))
		command(g, .Confirm)
		fr := new(Frame)
		defer free(fr)
		draw_game(fr, g)
		resolve(fr)
		write_ppm(DUMP_PLAY, fr)
	}
}

// A battle frame for checking the screen by eye (-define:DUMP_BATTLE=<path.ppm>).
DUMP_BATTLE :: #config(DUMP_BATTLE, "")

@(test)
test_dump_battle :: proc(t: ^testing.T) {
	when DUMP_BATTLE != "" {
		g := new(Game)
		defer free(g)
		init_game(g, u64(DUMP_SEED))
		h := g.empires[1].home
		colony_of(g, h, 1).bases = 2
		fleet_of(g, h, 1).ships[.Pickup] = 3
		f := new_fleet(g)
		f.ships[.Golf_Cart], f.ships[.Pickup], f.ships[.Monster_Truck], f.ships[.Inspector] = 4, 2, 1, 1
		dock(g, f, h)
		find_battles(g)
		command(g, .Confirm)
		command(g, .Confirm)
		fr := new(Frame)
		defer free(fr)
		draw_game(fr, g)
		resolve(fr)
		write_ppm(DUMP_BATTLE, fr)
	}
}

write_ppm :: proc(path: string, f: ^Frame) {
	header := "P6\n480 270\n255\n"
	data := make([]u8, len(header) + SCREEN_W * SCREEN_H * 3)
	defer delete(data)
	copy(data, header)
	for c, i in f.rgba {
		data[len(header) + i * 3 + 0] = u8(c)
		data[len(header) + i * 3 + 1] = u8(c >> 8)
		data[len(header) + i * 3 + 2] = u8(c >> 16)
	}
	_ = os.write_entire_file(path, data)
}
