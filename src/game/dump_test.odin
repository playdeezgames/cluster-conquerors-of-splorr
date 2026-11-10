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
