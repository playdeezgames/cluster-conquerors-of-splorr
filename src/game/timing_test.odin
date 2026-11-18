#+build !js
package game

// How long a turn and a frame take at huge with six empires (slice 3 step 8). Without
// -define:TIME_TURNS it does nothing: tools/time.sh runs it.

@(require) import "core:fmt"
import "core:testing"
@(require) import "core:time"

TIME_TURNS :: #config(TIME_TURNS, 0)

@(test)
test_time_turns :: proc(t: ^testing.T) {
	when TIME_TURNS > 0 {
		g := new(Game)
		defer free(g)
		f := new(Frame)
		defer free(f)
		worst, total, frames: time.Duration
		worst_at, turns := 0, 0
		frame_worst: time.Duration
		for seed in u64(1) ..= 5 {
			init_game(g, seed, {size = .Huge, rivals = 5})
			choose_race(g, .Owls)
			for turn in 1 ..= TIME_TURNS {
				ai_turn(g, PLAYER)
				start := time.tick_now()
				next_turn(g)
				d := time.tick_since(start)
				total += d
				turns += 1
				if d > worst {
					worst, worst_at = d, turn
				}
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
				if g.outcome != .Playing {
					break
				}
				fs := time.tick_now()
				draw_game(f, g)
				fd := time.tick_since(fs)
				frames += fd
				frame_worst = max(frame_worst, fd)
			}
		}
		fmt.printfln("TIME %v turns at huge with 5 rivals: %.2f ms a turn on average, %.2f ms at worst (turn %v); a map frame %.3f ms on average, %.3f ms at worst",
			turns, time.duration_milliseconds(total) / f64(turns), time.duration_milliseconds(worst), worst_at,
			time.duration_milliseconds(frames) / f64(turns), time.duration_milliseconds(frame_worst))
	}
}
