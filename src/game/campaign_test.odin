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
	// The colony builds the Carpools for a campaign it stages.
	g2 := new(Game)
	defer free(g2)
	home2, _, _ := campaign_game(g2, 10)
	rival_fleet(g2, home2, 1, only(.Pickup, 3))
	g2.empires[1].met[PLAYER] = true
	ai_turn(g2, 1)
	testing.expect_value(t, colony_of(g2, home2, 1).build, Ship_Type.Carpool)
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
