#+build !js
package game

import "core:testing"

@(test)
test_the_watch_budget :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	e := &g.empires[PLAYER]
	// Nothing goes to the Watch at 0 %.
	e.bj = 100
	fund_watch(g, PLAYER, 0)
	testing.expect_value(t, e.bj, 100)
	// 20 % of 100 BJ income trains one watcher.
	e.watch_share = 20
	fund_watch(g, PLAYER, 0)
	testing.expect_value(t, e.bj, 80)
	testing.expect_value(t, e.watchers, 1)
	testing.expect_value(t, e.watch_saved, 0)
	testing.expect(t, news_has(g, "A new watcher joins"))
	// Part of a watcher is saved for next time.
	e.bj = 50
	fund_watch(g, PLAYER, 0)
	testing.expect_value(t, e.watch_saved, 10)
	testing.expect_value(t, e.watchers, 1)
	// A full Watch takes nothing more.
	e.watchers = WATCHERS_MAX
	e.bj = 100
	fund_watch(g, PLAYER, 0)
	testing.expect_value(t, e.bj, 100)
	testing.expect_value(t, watchers_of(g, PLAYER), WATCHERS_MAX)
	// A whole turn sends the share.
	g2 := new(Game)
	defer free(g2)
	met_game(g2)
	g2.empires[PLAYER].watch_share = 25
	for _ in 0 ..< 10 {
		next_turn(g2)
	}
	testing.expect(t, watchers_of(g2, PLAYER) > 0 || g2.empires[PLAYER].watch_saved > 0)
}

@(test)
test_the_watch_screen :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	e := &g.empires[PLAYER]
	command(g, .Watch)
	testing.expect_value(t, g.mode, Mode.Watch)
	// The budget in fives, up to 25.
	for _ in 0 ..< 8 {
		command(g, .East)
	}
	testing.expect_value(t, e.watch_share, WATCH_SHARE_MAX)
	command(g, .West)
	testing.expect_value(t, e.watch_share, 20)
	// A rival not met yet: nothing to do.
	e.watchers = 2
	command(g, .South)
	command(g, .East)
	testing.expect_value(t, e.placed[1], 0)
	label, _, _ := watch_row_text(g, 1)
	testing.expect_value(t, label, "Not met yet.")
	// Met: Right sends a watcher, Left calls one home, the mission row changes the mission.
	g.empires[PLAYER].met[1] = true
	command(g, .East)
	command(g, .East)
	testing.expect_value(t, e.placed[1], 2)
	testing.expect_value(t, e.watchers, 0)
	command(g, .East)
	testing.expect(t, news_has(g, "No watchers at home"))
	command(g, .West)
	testing.expect_value(t, e.placed[1], 1)
	command(g, .South)
	command(g, .East)
	testing.expect_value(t, e.mission[1], Mission.Steal)
	command(g, .Confirm)
	testing.expect_value(t, e.mission[1], Mission.Factories)
	command(g, .West)
	command(g, .West)
	command(g, .West)
	testing.expect_value(t, e.mission[1], Mission.Ships)
	// Back, and W toggles.
	g.row = WATCH_BACK_ROW
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
	command(g, .Watch)
	command(g, .Watch)
	testing.expect_value(t, g.mode, Mode.Map)
	// From the forms desk and back.
	command(g, .Forms)
	command(g, .Watch)
	testing.expect_value(t, g.mode, Mode.Watch)
	// Taps: the < and > of the budget row.
	y := watch_row_y(WATCH_BUDGET_ROW)
	pointer(g, COLONY_X + WATCH_VALUE_COL * GLYPH_W + 2, y, .Mouse)
	testing.expect_value(t, e.watch_share, 15)
	_, value, _ := watch_row_text(g, WATCH_BUDGET_ROW)
	pointer(g, COLONY_X + (WATCH_VALUE_COL + 3 + len(value)) * GLYPH_W + 2, y, .Mouse)
	testing.expect_value(t, e.watch_share, 20)
	pointer(g, COLONY_X, watch_row_y(WATCH_BACK_ROW), .Mouse)
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_the_odds :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// One watcher against nobody at home is one more than theirs.
	g.empires[PLAYER].placed[1] = 1
	testing.expect_value(t, watch_success(g, PLAYER, 1, 0), WATCH_SUCCESS + WATCH_PER_EXTRA)
	g.empires[PLAYER].placed[1] = 4
	testing.expect_value(t, watch_success(g, PLAYER, 1, 0), WATCH_SUCCESS + 4 * WATCH_PER_EXTRA)
	testing.expect_value(t, watch_success(g, PLAYER, 1, 4), WATCH_SUCCESS)
	testing.expect_value(t, watch_success(g, PLAYER, 1, 9), WATCH_SUCCESS)
	g.empires[PLAYER].placed[1] = 20
	testing.expect_value(t, watch_success(g, PLAYER, 1, 0), WATCH_SUCCESS_MAX)
	testing.expect_value(t, watch_catch(g, PLAYER, .Steal, false), WATCH_CATCH)
	testing.expect_value(t, watch_catch(g, PLAYER, .Steal, true), WATCH_CATCH + WATCH_CATCH_DEFENDED)
	testing.expect_value(t, watch_catch(g, PLAYER, .Watch, false), WATCH_CATCH_WATCHING)
	// Raccoons: half as well again, caught half as often.
	g.empires[PLAYER].race = .Raccoons
	g.empires[PLAYER].placed[1] = 1
	testing.expect_value(t, watch_success(g, PLAYER, 1, 1), WATCH_SUCCESS * 3 / 2)
	testing.expect_value(t, watch_catch(g, PLAYER, .Steal, false), WATCH_CATCH / 2)
	testing.expect_value(t, RACES[.Raccoons].later, "")
}

@(test)
test_stealing_and_getting_caught :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	_, theirs := give_techs(g)
	e := &g.empires[PLAYER]
	e.placed[1] = 10
	e.mission[1] = .Steal
	before := g.empires[1].grudge[PLAYER]
	for _ in 0 ..< 30 {
		watch_turn(g)
		if knows(g, PLAYER, theirs) {
			break
		}
	}
	testing.expect(t, knows(g, PLAYER, theirs))
	testing.expect(t, news_has(g, "Yer Watch brings home"))
	testing.expect_value(t, g.steals, 1)
	// Nothing left to steal: the watchers just risk it.
	caught := g.spies_caught
	for _ in 0 ..< 40 {
		watch_turn(g)
	}
	testing.expect_value(t, g.steals, 1)
	testing.expect(t, g.spies_caught > caught)
	testing.expect_value(t, e.placed[1] + g.spies_caught, 10)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], min(100, before + GRUDGE_SPY_CAUGHT * g.spies_caught))
	testing.expect(t, news_has(g, "caught"))
}

@(test)
test_their_watchers_steal_from_you :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	mine, _ := give_techs(g)
	g.empires[1].placed[PLAYER] = 10
	g.empires[1].mission[PLAYER] = .Steal
	for _ in 0 ..< 30 {
		watch_turn(g)
		if knows(g, 1, mine) {
			break
		}
	}
	testing.expect(t, knows(g, 1, mine))
	testing.expect(t, news_has(g, "copied yer Book Club's notes"))
}

@(test)
test_sabotage :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	home := g.empires[1].home
	c := any_colony(g, home)
	factories := c.factories
	testing.expect(t, sabotage(g, PLAYER, 1, .Factories))
	testing.expect_value(t, c.factories, factories - SABOTAGE_FACTORIES)
	testing.expect(t, news_has(g, "Yer Watch wrecked 5 factories"))
	// No bases: nothing to wreck.
	c.bases = 0
	testing.expect(t, !sabotage(g, PLAYER, 1, .Bases))
	c.bases = 2
	testing.expect(t, sabotage(g, PLAYER, 1, .Bases))
	testing.expect_value(t, c.bases, 1)
	// Ships: one fewer.
	ships := 0
	for &f in g.fleets {
		if f.used && f.owner == 1 {
			ships += fleet_size(&f)
		}
	}
	testing.expect(t, sabotage(g, PLAYER, 1, .Ships))
	after := 0
	for &f in g.fleets {
		if f.used && f.owner == 1 {
			after += fleet_size(&f)
		}
	}
	testing.expect_value(t, after, ships - 1)
	testing.expect_value(t, g.sabotages, 3)
	// Done to you: nobody saw who.
	testing.expect(t, sabotage(g, 1, PLAYER, .Factories))
	testing.expect(t, news_has(g, "Nobody saw who"))
	// Watching does nothing but watch.
	testing.expect(t, !sabotage(g, PLAYER, 1, .Watch))
}

@(test)
test_watchers_see :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	home := g.empires[1].home
	update_sight(g)
	saw := g.empires[PLAYER].sees[home]
	g.empires[PLAYER].placed[1] = 1
	update_sight(g)
	testing.expect(t, g.empires[PLAYER].sees[home])
	testing.expect_value(t, g.empires[PLAYER].intel[home].owner, 1)
	_ = saw
	// A rival gone: the watchers come home.
	g.empires[1].out = true
	watch_turn(g)
	testing.expect_value(t, g.empires[PLAYER].placed[1], 0)
	testing.expect_value(t, g.empires[PLAYER].watchers, 1)
}

@(test)
test_rivals_run_a_watch :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	e := &g.empires[1]
	e.watchers = 4
	e.grudge[PLAYER] = 90
	e.grudge[2] = 10
	e.met[2] = true
	ai_watch(g, 1)
	testing.expect_value(t, e.watch_share, AI_WATCH_SHARE)
	testing.expect_value(t, e.watchers, 1)
	testing.expect_value(t, e.placed[PLAYER], 3)
	// A pact partner is only watched.
	g.treaty[1][PLAYER] = .Pact
	g.treaty[PLAYER][1] = .Pact
	ai_watch(g, 1)
	testing.expect_value(t, e.mission[PLAYER], Mission.Watch)
}

@(test)
test_the_watch_link :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	pointer(g, PANEL_TEXT_X + 2, WATCH_LINK_Y + 3, .Mouse)
	testing.expect_value(t, g.mode, Mode.Watch)
	pointer(g, PANEL_TEXT_X + 2, WATCH_LINK_Y + 3, .Mouse)
	testing.expect_value(t, g.mode, Mode.Map)
}

// Whether the minutes of the last meeting say something (lines joined where they wrapped).
minutes_have :: proc(g: ^Game, s: string) -> bool {
	all: [MINUTES_LINES * LOG_CAP]u8
	n := 0
	for i in 0 ..< g.council.lines {
		m := message(&g.council.minutes[i])
		for len(m) > 0 && m[0] == ' ' {
			m = m[1:]
		}
		if n > 0 {
			all[n] = ' '
			n += 1
		}
		copy(all[n:], m)
		n += len(m)
	}
	j := string(all[:n])
	for k := 0; k + len(s) <= len(j); k += 1 {
		if j[k:k + len(s)] == s {
			return true
		}
	}
	return false
}

@(test)
test_the_frame_up_row :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	e := &g.empires[PLAYER]
	e.met[1] = true
	open_watch(g)
	g.row = 3 // the first rival's frame-up
	r, kind := watch_row_rival(g.row)
	testing.expect_value(t, r, 1)
	testing.expect_value(t, kind, Watch_Row.Frame)
	// Nobody else met: nobody to name.
	command(g, .East)
	testing.expect(t, !e.frame[1])
	testing.expect(t, news_has(g, "nobody else to frame"))
	label, _, _ := watch_row_text(g, 3)
	testing.expect_value(t, label, "  frame-up: nobody else to name")
	// The other rival met: Left/Right names them or nobody.
	e.met[2] = true
	command(g, .East)
	testing.expect(t, e.frame[1])
	_, value, tail := watch_row_text(g, 3)
	testing.expect_value(t, value[4:], empire_name(g, 2))
	testing.expect_value(t, tail, "(on missions only)") // just watching, so far
	testing.expect(t, !framing(g, PLAYER, 1, e.mission[1]))
	e.mission[1] = .Steal
	testing.expect(t, framing(g, PLAYER, 1, e.mission[1]))
	command(g, .West)
	testing.expect(t, !e.frame[1])
	// Back is now below three rows for each rival.
	testing.expect_value(t, WATCH_BACK_ROW, 7)
}

@(test)
test_frame_ups_work_or_backfire :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	g.empires[1].met[2] = true
	g.empires[1].frame[2] = true
	// The Owls (you) are framed by rival 1 at rival 2's.
	worked, failed := 0, 0
	for _ in 0 ..< 200 {
		g.empires[2].grudge[PLAYER] = 50
		g.empires[2].grudge[1] = 50
		g.council.exposed_n = 0
		blamed, exposed := pin_blame(g, 1, 2, 10)
		if exposed {
			failed += 1
			testing.expect_value(t, blamed, 1)
			testing.expect_value(t, g.empires[2].grudge[1], 70)
			testing.expect_value(t, g.empires[2].grudge[PLAYER], 50)
			testing.expect_value(t, g.council.exposed_n, 1)
			testing.expect_value(t, g.council.exposed[0], Exposed{1, 2, PLAYER})
		} else {
			worked += 1
			testing.expect_value(t, blamed, PLAYER)
			testing.expect_value(t, g.empires[2].grudge[PLAYER], 60)
			testing.expect_value(t, g.empires[2].grudge[1], 50)
		}
	}
	// About three in four.
	testing.expect(t, worked > 120 && worked < 180)
	testing.expect_value(t, worked + failed, 200)
	testing.expect_value(t, g.frames_worked, worked)
	testing.expect_value(t, g.frames_failed, failed)
}

@(test)
test_framing_on_a_mission :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	_, theirs := give_techs(g)
	e := &g.empires[PLAYER]
	e.placed[1] = 10
	e.mission[1] = .Steal
	e.frame[1] = true
	for _ in 0 ..< 30 {
		watch_turn(g)
		if knows(g, PLAYER, theirs) {
			break
		}
	}
	testing.expect(t, knows(g, PLAYER, theirs))
	testing.expect_value(t, g.frames_worked + g.frames_failed > 0, true)
	testing.expect(t, news_has(g, "left their name all over it") || news_has(g, "fooled nobody"))
	// Caught while framing: blamed on them, or exposed.
	for _ in 0 ..< 40 {
		watch_turn(g)
	}
	testing.expect(t, news_has(g, ", and blame the") || news_has(g, "Nobody was fooled"))
}

@(test)
test_the_association_hears_of_it :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	g.empires[PLAYER].bj = 1000
	g.council.exposed[0] = {PLAYER, 1, 2}
	g.council.exposed[1] = {2, PLAYER, 1}
	g.council.exposed_n = 2
	hold_meeting(g)
	testing.expect(t, minutes_have(g, "framing the"))
	testing.expect(t, minutes_have(g, "caught at yer colonies"))
	testing.expect(t, minutes_have(g, "Complaint, you: a watcher caught at the"))
	testing.expect_value(t, g.empires[PLAYER].bj, 1000 - 1000 * FINE_PERCENT / 100)
	testing.expect_value(t, g.council.exposed_n, 0)
}

@(test)
test_rivals_frame :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	e := &g.empires[1]
	e.watchers = 3
	e.grudge[2] = 90 // they spy on the other rival, and frame you
	e.grudge[PLAYER] = 60
	e.met[2] = true
	ai_watch(g, 1)
	testing.expect_value(t, e.placed[2], 2)
	testing.expect(t, e.frame[2])
	testing.expect_value(t, frame_target(g, 1, 2), PLAYER)
	// Not someone they have a pact with.
	g.treaty[1][PLAYER] = .Pact
	g.treaty[PLAYER][1] = .Pact
	ai_watch(g, 1)
	testing.expect(t, !e.frame[2])
}

@(test)
test_read_outs_make_room_for_you :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	for e in 0 ..< g.empire_count {
		for o in 0 ..< g.empire_count {
			g.empires[e].met[o] = true
		}
	}
	for g.council.exposed_n < MAX_EXPOSED || g.frames_failed < 20 {
		pin_blame(g, 1, 2, 1) // rival on rival, framing you
		if g.frames_failed > 200 {
			break
		}
	}
	testing.expect_value(t, g.council.exposed_n, MAX_EXPOSED)
	// Rival 1 at rival 2's, framing you, does involve you; rival 2 framing rival 1 at yers too.
	g.council.exposed = {}
	g.council.exposed[0] = {1, 2, 2}
	g.council.exposed[1] = {1, 2, 2}
	g.council.exposed[2] = {1, 2, 2}
	before := g.frames_failed
	for g.frames_failed == before {
		pin_blame(g, PLAYER, 1, 1)
	}
	testing.expect_value(t, g.council.exposed[0], Exposed{PLAYER, 1, 2})
}
