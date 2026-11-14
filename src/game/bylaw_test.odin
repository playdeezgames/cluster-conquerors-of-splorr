#+build !js
package game

import "core:testing"

// Sliders with everything on one chore.
all_on :: proc(ch: Chore) -> (s: [Chore]int) {
	s[ch] = 100
	return
}

// A cluster where everyone has met, with a bylaw in force.
bylaw_game :: proc(g: ^Game, b: Bylaw) {
	init_game(g, SEED)
	all_met(g)
	g.council.bylaw = b
}

@(test)
test_bylaws_proposed_and_voted :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for _ in 0 ..< 30 {
		bylaw_game(g, .Quiet_Hours)
		g.council.lines = 0
		propose_bylaws(g)
		p := g.council.proposals
		testing.expect(t, p[0] != p[1])
		testing.expect(t, p[0] != .None && p[1] != .None)
		testing.expect(t, p[0] != .Quiet_Hours && p[1] != .Quiet_Hours)
		testing.expect(t, g.council.bylaw_voting)
		testing.expect(t, minutes_contain(g, "Proposed bylaws"))
		g.seed += 1
		g.rng = Rng{g.seed}
	}
	// Yer households carry it.
	colony_at(g, g.home).households = 1000
	g.council.proposals = {.Tidy_Yards, .Fence_Height}
	cast_bylaw_votes(g, .Second)
	testing.expect_value(t, g.council.bylaw, Bylaw.Fence_Height)
	testing.expect(t, minutes_contain(g, "Passed: No new defence bases"))
	testing.expect(t, news_has(g, "New bylaw (fence height)"))
	testing.expect_value(t, g.bylaws_passed, 1)
	// Nobody voting: no bylaw.
	colony_at(g, g.home).households = 1
	g.council.bylaw_voting = true
	g.council.proposals = {.Jumble_Sale, .Jumble_Sale}
	cast_bylaw_votes(g, .Abstain)
	testing.expect_value(t, g.council.bylaw, Bylaw.None)
}

@(test)
test_a_whole_meeting_with_a_bylaw :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	colony_at(g, g.home).households = 1000
	council_turn(g)
	testing.expect_value(t, g.mode, Mode.Council)
	testing.expect(t, g.council.bylaw_voting)
	first := g.council.proposals[0]
	command(g, .Confirm) // the first proposal
	testing.expect_value(t, g.council.bylaw, first)
	testing.expect(t, g.council.voting) // then the vote for President
	command(g, .Confirm)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_quiet_hours_and_the_jumble_sale :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	bylaw_game(g, .None)
	rp := research_points(g, g.home)
	g.council.bylaw = .Quiet_Hours
	testing.expect_value(t, research_points(g, g.home), rp / 2)
	for e in 0 ..< g.empire_count {
		g.empires[e].bj = 25
	}
	g.empires[2].bj = 4
	pass_bylaw(g, .Jumble_Sale)
	testing.expect_value(t, g.empires[PLAYER].bj, 25 - JUMBLE_SALE_BJ)
	testing.expect_value(t, g.empires[1].bj, 25 - JUMBLE_SALE_BJ)
	testing.expect_value(t, g.empires[2].bj, 0)
}

@(test)
test_breaking_a_bylaw :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	bylaw_game(g, .Small_Trucks)
	c := colony_at(g, g.home)
	c.build = .Monster_Truck
	testing.expect(t, bylaw_bans(g, .Monster_Truck))
	testing.expect(t, !bylaw_bans(g, .Pickup))
	c.slider = all_on(.Parking)
	c.stored[.Parking] = SHIPS[.Monster_Truck].cost
	run_colony(g, g.home)
	testing.expect(t, g.council.broke[PLAYER])
	testing.expect(t, news_has(g, "That breaks the bylaw (small trucks)"))
	// The next meeting hears of it, fines it, and forgets it.
	g.empires[PLAYER].bj = 1000
	hold_meeting(g)
	testing.expect(t, minutes_contain(g, "Complaint, you: broke the bylaw (small trucks)."))
	testing.expect(t, g.empires[PLAYER].bj < 1000)
	testing.expect(t, !g.council.broke[PLAYER])
	// Fence height: a new base.
	g.council.bylaw = .Fence_Height
	c.slider = all_on(.Fencing)
	c.stored[.Fencing] = BASE_COST
	run_colony(g, g.home)
	testing.expect(t, g.council.broke[PLAYER])
	// No carpools: a landing.
	g.council.broke = {}
	g.council.bylaw = .No_Carpools
	h := g.empires[1].home
	colony_of(g, h, 1).bases = 0
	for &f in g.fleets {
		if f.used && f.owner == 1 {
			f = {}
		}
	}
	f := new_fleet(g)
	f.ships[.Carpool] = 1
	dock(g, f, h)
	land_troops(g)
	testing.expect(t, g.council.broke[PLAYER])
	// No new houses: building a Moving Van.
	g.council.broke = {}
	g.council.bylaw = .No_New_Houses
	testing.expect(t, bylaw_bans(g, .Moving_Van))
}

@(test)
test_tidy_yards_and_no_parking :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	bylaw_game(g, .None)
	colony_at(g, g.home).waste = TIDY_WASTE
	hold_meeting(g)
	testing.expect(t, !minutes_contain(g, "are a mess"))
	g.council.bylaw = .Tidy_Yards
	hold_meeting(g)
	testing.expect(t, minutes_contain(g, "are a mess"))
	// No parking: ships at an empty star.
	colony_at(g, g.home).waste = 0
	empty := NO_STAR
	for i in 0 ..< g.star_count {
		if any_colony(g, i) == nil && !g.stars[i].wormhole {
			empty = i
			break
		}
	}
	f := new_fleet(g)
	f.ships[.Golf_Cart] = 1
	dock(g, f, empty)
	g.council.bylaw = .None
	hold_meeting(g)
	testing.expect(t, !minutes_contain(g, "no-parking"))
	g.council.bylaw = .No_Parking
	hold_meeting(g)
	testing.expect(t, minutes_contain(g, "under the no-parking bylaw"))
}

@(test)
test_rivals_keep_and_vote_bylaws :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	bylaw_game(g, .No_Carpools)
	for _ in 0 ..< 30 {
		ai_turn(g, 1)
		for i in 0 ..< g.star_count {
			if c := colony_of(g, i, 1); c != nil {
				testing.expect(t, c.build != .Carpool)
			}
		}
	}
	g.council.bylaw = .Fence_Height
	ai_turn(g, 1)
	testing.expect_value(t, colony_of(g, g.empires[1].home, 1).slider[.Fencing], 0)
	// They vote for what hurts whoever they hate most: you, with yer research.
	g.empires[1].grudge[PLAYER] = 90
	g.empires[1].grudge[2] = 10
	g.council.proposals = {.Jumble_Sale, .Quiet_Hours}
	colony_at(g, g.home).slider = all_on(.Book_Club)
	g.empires[PLAYER].bj = 1000
	testing.expect_value(t, rival_bylaw_vote(g, 1), Vote.Second)
	g.council.proposals = {.Quiet_Hours, .Jumble_Sale}
	testing.expect_value(t, rival_bylaw_vote(g, 1), Vote.First)
}
