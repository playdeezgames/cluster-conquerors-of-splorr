#+build !js
package game

import "core:testing"

// A rival (1) with its home and a second colony, and a colony of yers it has seen, defended, near its
// home: a hand-made layout, whatever the seed. Returns the rival's home, its other colony and yers.
campaign_game :: proc(g: ^Game, defence: int) -> (home, other, yers: int) {
	init_game(g, SEED)
	home = g.empires[1].home
	if f := fleet_of(g, home, 1); f != nil {
		f^ = {}
	}
	free_stars: [2]int
	n := 0
	for i in 0 ..< g.star_count {
		if n < 2 && i != home && i != g.home && i != g.clubhouse && !g.stars[i].wormhole && any_colony(g, i) == nil {
			free_stars[n] = i
			n += 1
		}
	}
	yers, other = free_stars[0], free_stars[1]
	dir := g.stars[home].x < g.galaxy_w / 2 ? 1 : -1 // away from the edge
	g.stars[yers].x = clamp(g.stars[home].x + 6 * dir, 0, g.galaxy_w - 1)
	g.stars[yers].y = g.stars[home].y
	g.stars[other].x = clamp(g.stars[home].x - 6 * dir, 0, g.galaxy_w - 1)
	g.stars[other].y = g.stars[home].y
	found_colony(g, yers, 10)
	found_colony(g, other, 30, 1)
	colony_of(g, home, 1).households = 60
	update_sight(g)
	g.empires[1].intel[yers] = {seen = true, owner = PLAYER, strength = defence, households = 10}
	for i in 0 ..< g.star_count {
		if i != yers {
			g.empires[1].intel[i] = {}
		}
	}
	return
}

// Whether the rival has a fleet on its way to `to` with at least these ships.
on_the_way :: proc(g: ^Game, owner, to: int, t: Ship_Type, n: int) -> bool {
	for &f in g.fleets {
		if f.used && f.owner == owner && f.star == NO_STAR && f.to == to && f.ships[t] >= n {
			return true
		}
	}
	return false
}

@(test)
test_campaign_gathers :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	// Yer colony has 30 hits of defence: the home's 3 Pickups (30 hits) are not enough alone at 150 %,
	// but with the other colony's 2 (50 hits) they are.
	home, other, yers := campaign_game(g, 30)
	rival_fleet(g, home, 1, only(.Pickup, 3))
	rival_fleet(g, other, 1, only(.Pickup, 2))
	plan_campaign(g, 1, true)
	cp := g.empires[1].campaign
	testing.expect(t, cp.on)
	testing.expect_value(t, cp.target, yers)
	testing.expect_value(t, cp.staging, home) // nearer than the other colony
	testing.expect_value(t, g.planned, 1)
	// Not ready at home: the other colony's Pickups come to it, and the home's stay.
	testing.expect_value(t, run_campaign(g, 1), home)
	testing.expect(t, on_the_way(g, 1, home, .Pickup, 2))
	testing.expect_value(t, fleet_of(g, home, 1).ships[.Pickup], 3)
	ai_attack(g, 1, true, home)
	testing.expect_value(t, fleet_of(g, home, 1).ships[.Pickup], 3) // left alone while it waits
	testing.expect_value(t, g.launched, 0)
}

@(test)
test_campaign_escorts_carpools :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	home, _, yers := campaign_game(g, 10)
	rival_fleet(g, home, 1, only(.Pickup, 3))
	plan_campaign(g, 1, true)
	testing.expect_value(t, g.empires[1].campaign.target, yers)
	need := campaign_carpools_wanted(g, 1)
	testing.expect_value(t, need, 1)
	// The Carpools are not built yet: the warships wait for them.
	testing.expect_value(t, run_campaign(g, 1), home)
	testing.expect_value(t, g.launched, 0)
	fleet_of(g, home, 1).ships[.Carpool] = need
	// Now they go in together.
	testing.expect_value(t, run_campaign(g, 1), NO_STAR)
	testing.expect_value(t, g.launched, 1)
	testing.expect(t, !g.empires[1].campaign.on)
	going := false
	for &f in g.fleets {
		if f.used && f.owner == 1 && f.to == yers && f.ships[.Pickup] == 3 && f.ships[.Carpool] == need {
			going = true
		}
	}
	testing.expect(t, going)
	// One of its colonies with households to spare builds the Carpool the campaign needs (since step 7,
	// not only the staging colony), and only the one.
	g2 := new(Game)
	defer free(g2)
	home2, other2, _ := campaign_game(g2, 10)
	rival_fleet(g2, home2, 1, only(.Pickup, 3))
	g2.empires[1].met[PLAYER] = true
	ai_turn(g2, 1)
	building := 0
	for i in ([2]int{home2, other2}) {
		if colony_of(g2, i, 1).build == .Carpool {
			building += 1
		}
	}
	testing.expect_value(t, building, 1)
}

@(test)
test_campaign_reaching :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	home, _, yers := campaign_game(g, 50)
	// Far enough that Monster Trucks (2 fuel, 3 speed) cannot go, but Pickups and Carpools can.
	g.stars[yers].x = clamp(g.stars[home].x + 11 * (g.stars[home].x < g.galaxy_w / 2 ? 1 : -1), 0, g.galaxy_w - 1)
	mix := only(.Pickup, 3)
	mix[.Monster_Truck], mix[.Carpool] = 2, 1
	rival_fleet(g, home, 1, mix)
	ships := reaching(g, 1, home, yers, mix)
	testing.expect_value(t, ships[.Monster_Truck], 0)
	testing.expect_value(t, ships[.Pickup], 3)
	testing.expect_value(t, ships[.Carpool], 1)
}

@(test)
test_campaign_given_up :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	home, _, yers := campaign_game(g, 30)
	rival_fleet(g, home, 1, only(.Pickup, 5))
	plan_campaign(g, 1, true)
	testing.expect(t, g.empires[1].campaign.on)
	// Too slow: given up (and planned again at once, if still worth it).
	g.turn += CAMPAIGN_TURNS + 1
	plan_campaign(g, 1, true)
	testing.expect_value(t, g.timed_out, 1)
	testing.expect_value(t, g.empires[1].campaign.since, g.turn)
	// A pact: not a target any more.
	set_treaty(g, 1, PLAYER, .Pact)
	plan_campaign(g, 1, true)
	testing.expect_value(t, g.dropped, 1)
	testing.expect(t, !g.empires[1].campaign.on)
	// A Builder that can still settle goes after no empire.
	set_treaty(g, 1, PLAYER, .None)
	plan_campaign(g, 1, false)
	testing.expect(t, !g.empires[1].campaign.on || g.empires[1].campaign.target != yers)
	// Saves keep a campaign.
	plan_campaign(g, 1, true)
	testing.expect(t, g.empires[1].campaign.on)
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	write_save(g, buf)
	h := new(Game)
	defer free(h)
	init_game(h, SEED)
	testing.expect(t, read_save(h, buf))
	testing.expect_value(t, h.empires[1].campaign.target, yers)
}

@(test)
test_campaign_stops_to_refuel :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	home, other, yers := campaign_game(g, 10)
	// Too far for one trip (a Golf Cart with a Carpool: 3 turns of fuel at 4 cells), with an empty star
	// half way to stop at.
	dir := g.stars[home].x < g.galaxy_w / 2 ? 1 : -1
	g.stars[yers].x = g.stars[home].x + 20 * dir
	g.stars[other].x = g.stars[home].x + 10 * dir // the other colony becomes the stop: make it nobody's
	g.stars[other].colony = {}
	for i in 0 ..< g.star_count {
		if i != home && i != yers && i != other && any_colony(g, i) == nil {
			g.stars[i].x = clamp(g.stars[home].x - 30 * dir, 0, g.galaxy_w - 1) // out of the way
		}
	}
	testing.expect(t, !campaign_reaches(g, 1, home, yers))
	rival_fleet(g, home, 1, only(.Pickup, 3))
	plan_campaign(g, 1, true)
	cp := g.empires[1].campaign
	testing.expect(t, cp.on)
	testing.expect_value(t, cp.staging, home)
	testing.expect_value(t, cp.via, other)
	// The staging colony builds the Gas Can first.
	g.empires[1].met[PLAYER] = true
	ai_turn(g, 1)
	testing.expect_value(t, colony_of(g, home, 1).build, Ship_Type.Gas_Can)
	// With the Gas Can and the Carpool, they go to the stop...
	f := fleet_of(g, home, 1)
	f.ships[.Gas_Can], f.ships[.Carpool] = 1, 1
	f.refills = GAS_CAN_REFILLS
	g.empires[1].campaign = cp
	testing.expect_value(t, run_campaign(g, 1), other)
	testing.expect(t, g.empires[1].campaign.hopping)
	testing.expect(t, on_the_way(g, 1, other, .Carpool, 1))
	testing.expect(t, on_the_way(g, 1, other, .Gas_Can, 1))
	// ...and from there, refuelled, on to the target.
	for &o in g.fleets {
		if o.used && o.owner == 1 && o.to == other {
			dock(g, &o, other)
			o.away = 0
		}
	}
	testing.expect_value(t, run_campaign(g, 1), NO_STAR)
	testing.expect(t, on_the_way(g, 1, yers, .Pickup, 3))
	testing.expect(t, on_the_way(g, 1, yers, .Carpool, 1))
	testing.expect_value(t, g.hops, 1)
	testing.expect_value(t, g.launched, 1)
}

@(test)
test_campaign_finishing :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// One colony from the start is not "nearly finished"; down from three to two is.
	testing.expect(t, !nearly_finished(g, PLAYER))
	g.empires[PLAYER].peak = 3
	testing.expect(t, nearly_finished(g, PLAYER))
	in_ := Intel{seen = true, owner = PLAYER, strength = 1}
	g.empires[1].aim = .Tinkerer
	testing.expect_value(t, target_score(g, 1, in_, NO_OWNER), g.empires[1].grudge[PLAYER] + FINISH_BONUS)
	// A campaign against it may take twice as long.
	g.empires[1].campaign = {on = true, target = g.home, staging = g.empires[1].home, via = NO_STAR}
	g.empires[1].intel[g.home] = in_
	testing.expect_value(t, campaign_turns(g, 1), 2 * CAMPAIGN_TURNS)
	g.empires[PLAYER].peak = 1
	testing.expect_value(t, campaign_turns(g, 1), CAMPAIGN_TURNS)
	// The planning kit is the least of the empire's warship fleets.
	f := fleet_of(g, g.empires[1].home, 1)
	f.ships[.Golf_Cart] = 1
	f.kit = {}
	testing.expect_value(t, planning_kit(g, 1), Kit{})
}
