#+build !js
package game

// The balance simulator (tools/sim.sh): the computer plays every side, yers included, for many games,
// and reports when things first happen. Without -define:SIM_GAMES it does nothing.

import "core:fmt"
import "core:testing"

SIM_GAMES :: #config(SIM_GAMES, 0)
SIM_TURNS :: #config(SIM_TURNS, 200)

Sim_Stats :: struct {
	contact, battle, meeting, capture, moth, president, out, pact, trade: [dynamic]int, // turns things first happened
	colonies: int,
	presidents_you: int,
	won, lost: int,
	doormats: int, // rivals' forms at side 0
}

sim_first :: proc(list: ^[dynamic]int, seen: ^bool, turn: int, now: bool) {
	if now && !seen^ {
		seen^ = true
		append(list, turn)
	}
}

sim_summary :: proc(name: string, list: [dynamic]int, games: int) {
	if len(list) == 0 {
		fmt.printfln("  %-14s never", name)
		return
	}
	sum, lo, hi := 0, max(int), 0
	for v in list {
		sum += v
		lo = min(lo, v)
		hi = max(hi, v)
	}
	fmt.printfln("  %-14s in %2v of %v games, turn %v on average (%v to %v)", name, len(list), games, sum / len(list), lo, hi)
}

@(test)
test_simulate :: proc(t: ^testing.T) {
	when SIM_GAMES > 0 {
		g := new(Game)
		defer free(g)
		st: Sim_Stats
		defer {
			delete(st.contact)
			delete(st.battle)
			delete(st.meeting)
			delete(st.capture)
			delete(st.moth)
			delete(st.president)
			delete(st.out)
			delete(st.pact)
			delete(st.trade)
		}
		for seed in u64(1) ..= SIM_GAMES {
			init_game(g, seed)
			seen: [9]bool
			for turn in 1 ..= SIM_TURNS {
				ai_turn(g, PLAYER)
				next_turn(g)
				for g.mode == .Battle {
					battle_action(g, 1)
				}
				if g.council.voting {
					cast_votes(g, .Abstain)
				}
				if g.outcome == .Playing && g.mode != .Doormat {
					back_to_map(g)
				}
				for g.mode == .Doormat {
					st.doormats += 1
					answer_doormat(g, ai_doormat_sign(g))
				}
				g.mode = g.outcome == .Playing ? .Map : g.mode
				met := false
				for a in 0 ..< g.empire_count {
					for b in 0 ..< g.empire_count {
						met = met || g.empires[a].met[b]
					}
				}
				anyone_out := false
				for e in 0 ..< g.empire_count {
					anyone_out = anyone_out || g.empires[e].out
				}
				sim_first(&st.contact, &seen[0], turn, met)
				sim_first(&st.battle, &seen[1], turn, g.battles > 0)
				sim_first(&st.meeting, &seen[2], turn, g.council.meetings > 0)
				sim_first(&st.capture, &seen[3], turn, g.captures > 0)
				sim_first(&st.moth, &seen[4], turn, !g.moth_alive)
				sim_first(&st.president, &seen[5], turn, g.council.president != NO_OWNER)
				sim_first(&st.out, &seen[6], turn, anyone_out)
				sim_first(&st.pact, &seen[7], turn, g.pacts > 0)
				sim_first(&st.trade, &seen[8], turn, g.trades > 0)
				if g.outcome != .Playing {
					break
				}
			}
			for e in 0 ..< g.empire_count {
				st.colonies += colonies_of(g, e)
			}
			if g.council.ever_won {
				st.presidents_you += 1
			}
			if g.outcome == .Won {
				st.won += 1
			}
			if g.outcome == .Lost {
				st.lost += 1
			}
		}
		fmt.printfln("SIM %v games of up to %v turns, the computer playing every side:", SIM_GAMES, SIM_TURNS)
		sim_summary("first contact", st.contact, SIM_GAMES)
		sim_summary("first battle", st.battle, SIM_GAMES)
		sim_summary("first meeting", st.meeting, SIM_GAMES)
		sim_summary("first capture", st.capture, SIM_GAMES)
		sim_summary("moth gone", st.moth, SIM_GAMES)
		sim_summary("a President", st.president, SIM_GAMES)
		sim_summary("someone out", st.out, SIM_GAMES)
		sim_summary("first pact", st.pact, SIM_GAMES)
		sim_summary("first trade", st.trade, SIM_GAMES)
		fmt.printfln("  rivals' forms on side 0's doormat: %.1f a game (pacts signed, demands paid only to the twice as strong)", f64(st.doormats) / f64(SIM_GAMES))
		fmt.printfln("  colonies at the end: %.1f per empire; side 0 won %v, lost %v, was President in %v", f64(st.colonies) / f64(SIM_GAMES * MAX_EMPIRES), st.won, st.lost, st.presidents_you)
	}
}
