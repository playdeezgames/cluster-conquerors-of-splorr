package game

// Campaigns (slice 3 step 6): the computer gathers its fleets and escorts its Carpools. Each computer
// empire picks one target at a time: the star it most wants to hit (by `target_score`) of those its
// warships, all together, are strong enough for. It goes in from a staging colony, the one of its
// colonies nearest the target that can reach it. Warships at its other colonies fly there; once the
// warships at the staging colony are strong enough by themselves (`attack_percent` of what it saw), and,
// for a colony, the Carpools to take it are there too (the staging colony builds them), they go in
// together: the warships fight whatever is there, and the Carpools land the turn after. A campaign not
// launched within CAMPAIGN_TURNS is given up. Before step 6 each colony's warships went alone at
// whatever they alone could beat, and Carpools went alone, only at colonies seen with no defence.
// While a campaign is on, the warships elsewhere still go after what they alone can beat on the way
// (`ai_attack`), except those at the staging colony. Numbers are Claude's (PLAN.md).
// Step 7 added reach and finishing. Reach: a target no colony can reach in one trip is still a target
// if some star on the way (no colony of anyone's, no moth, no wormhole) is in reach of a colony and
// the target is in reach of it. The staging colony then builds a Gas Can, and the fleet goes with it
// to that star first; it refuels there (a Gas Can tops up a docked fleet) and goes on next turn.
// Finishing: an empire that has lost colonies and is down to FINISH_AT or fewer is worth FINISH_BONUS more as a target
// (`target_score`), and a campaign against it is given up only after twice as long.

CAMPAIGN_TURNS :: 30
FINISH_AT :: 2 // colonies an empire is down to when the others close in
FINISH_BONUS :: 50
CARPOOL_SPARE :: CARPOOL_LOAD * 2 // a colony builds Carpools only with more households than this

Campaign :: struct {
	on:      bool,
	target:  int,
	staging: int,
	since:   int, // the turn it was planned
	via:     int, // the star it stops at to refuel on the way (step 7), or NO_STAR
	hopping: bool, // gone from the staging colony to `via`
}

// What `owner` believes is at a star, with the moth that everyone has heard of.
campaign_intel :: proc(g: ^Game, owner, star: int) -> Intel {
	in_ := g.empires[owner].intel[star]
	if star == g.clubhouse && g.moth_alive && !in_.seen {
		in_ = {seen = true, owner = NO_OWNER, strength = MOTH_COMBAT.hp}
	}
	return in_
}

// Whether a star is still worth a campaign: an enemy colony (not one with a pact, and not while the
// empire keeps out of wars), or something armed it saw there.
campaign_target_ok :: proc(g: ^Game, owner, star: int, at_empires: bool) -> bool {
	in_ := campaign_intel(g, owner, star)
	if !in_.seen || in_.owner == owner {
		return false
	}
	if in_.owner >= 0 {
		return at_empires && !has_pact(g, owner, in_.owner) && !g.empires[in_.owner].out
	}
	return in_.strength > 0
}

// Carpools wanted to take a colony seen with these households: half as many troops again as its militia.
carpools_for :: proc(households: int) -> int {
	return (militia_of(households) * 3 / 2) / CARPOOL_LOAD + 1
}

// The kit a campaign is planned with: the least of any of the empire's warship fleets (a gathered fleet
// goes with its oldest ship's kit, and fleets whose upgrades went unpaid keep the old), or today's.
// Planning with today's kit left most ready campaigns out of range in step 7's first simulator runs.
planning_kit :: proc(g: ^Game, owner: int) -> Kit {
	k := empire_kit(g, owner)
	for &f in g.fleets {
		if f.used && f.owner == owner && warship_hits(&f) > 0 {
			for s in Kit_Stat {
				k[s] = min(k[s], f.kit[s])
			}
		}
	}
	return k
}

// Whether a fleet of warships and Carpools, full of fuel, reaches `to` from `from`, with this kit (by
// default the planning kit).
campaign_reaches :: proc(g: ^Game, owner, from, to: int, kit: Maybe(Kit) = nil) -> bool {
	trial := Fleet {
		ships = ship_one(.Golf_Cart),
		kit   = kit.? or_else planning_kit(g, owner),
	}
	trial.ships[.Carpool] = 1
	return trip_turns(g, from, to, fleet_speed(&trial)) <= fleet_range(&trial)
}

// A stop on the way from `from` to `to` for a fleet with this kit, the shortest trip, or NO_STAR.
stopover_for :: proc(g: ^Game, owner, from, to: int, kit: Kit) -> int {
	best, best_trip := NO_STAR, max(int)
	for w in 0 ..< g.star_count {
		if w == to || w == from || !stopover_ok(g, w) || !campaign_reaches(g, owner, from, w, kit) || !campaign_reaches(g, owner, w, to, kit) {
			continue
		}
		if trip := isqrt(dist2(g, from, w)) + isqrt(dist2(g, w, to)); trip < best_trip {
			best, best_trip = w, trip
		}
	}
	return best
}

// The empire's warships docked at its colonies, in hits.
docked_hits :: proc(g: ^Game, owner: int) -> int {
	n := 0
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) == nil {
			continue
		}
		if f := fleet_of(g, i, owner); f != nil {
			n += warship_hits(f)
		}
	}
	return n
}

dist2 :: proc(g: ^Game, a, b: int) -> int {
	sa, sb := g.stars[a], g.stars[b]
	return (sa.x - sb.x) * (sa.x - sb.x) + (sa.y - sb.y) * (sa.y - sb.y)
}

// A star a fleet can stop at on the way: nobody's colony, no moth, no wormhole.
stopover_ok :: proc(g: ^Game, star: int) -> bool {
	return !g.stars[star].wormhole && any_colony(g, star) == nil && !(star == g.clubhouse && g.moth_alive)
}

// The empire's colony nearest `to` that can reach it, or NO_STAR; failing that (step 7), the colony
// and the stop on the way with the shortest trip.
staging_for :: proc(g: ^Game, owner, to: int) -> (staging, via: int) {
	staging, via = NO_STAR, NO_STAR
	best_d := max(int)
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) == nil || i == to || !campaign_reaches(g, owner, i, to) {
			continue
		}
		if d := dist2(g, i, to); d < best_d {
			staging, best_d = i, d
		}
	}
	if staging != NO_STAR {
		return
	}
	best_trip := max(int)
	for w in 0 ..< g.star_count {
		if w == to || !stopover_ok(g, w) || !campaign_reaches(g, owner, w, to) {
			continue
		}
		for i in 0 ..< g.star_count {
			if colony_of(g, i, owner) == nil || !campaign_reaches(g, owner, i, w) {
				continue
			}
			if trip := isqrt(dist2(g, i, w)) + isqrt(dist2(g, w, to)); trip < best_trip {
				staging, via, best_trip = i, w, trip
			}
		}
	}
	return
}

// How long a campaign may take to get going: twice as long against an empire nearly finished.
campaign_turns :: proc(g: ^Game, owner: int) -> int {
	in_ := campaign_intel(g, owner, g.empires[owner].campaign.target)
	return in_.owner >= 0 && nearly_finished(g, in_.owner) ? 2 * CAMPAIGN_TURNS : CAMPAIGN_TURNS
}

// An empire that has lost colonies and is down to its last few.
nearly_finished :: proc(g: ^Game, e: int) -> bool {
	n := colonies_of(g, e)
	return !g.empires[e].out && n <= FINISH_AT && n < g.empires[e].peak
}

// Each turn, before the colonies choose what to build: the campaign is checked, given up or planned.
plan_campaign :: proc(g: ^Game, owner: int, at_empires: bool) {
	c := &g.empires[owner].campaign
	if c.on && (!campaign_target_ok(g, owner, c.target, at_empires) || (!c.hopping && colony_of(g, c.staging, owner) == nil)) {
		c.on = false
		g.dropped += 1
	}
	if c.on && !c.hopping && g.turn - c.since > campaign_turns(g, owner) {
		c.on = false
		g.timed_out += 1
	}
	if c.on && !c.hopping && !finishing(g, owner, c.target) {
		// Step 9: an empire nearly finished is worth dropping a campaign for, before it recovers.
		if t, _, _ := best_campaign_target(g, owner, at_empires); t != NO_STAR && finishing(g, owner, t) {
			c.on = false
			g.retargeted += 1
		}
	}
	if c.on {
		return
	}
	best, best_staging, best_via := best_campaign_target(g, owner, at_empires)
	if best != NO_STAR {
		c^ = {true, best, best_staging, g.turn, best_via, false}
		g.planned += 1
	}
}

// Whether the campaign target is a colony of an empire nearly finished.
finishing :: proc(g: ^Game, owner, star: int) -> bool {
	in_ := campaign_intel(g, owner, star)
	return in_.owner >= 0 && nearly_finished(g, in_.owner)
}

// The star the empire most wants a campaign against, of those its docked warships could beat, with
// the staging colony and any stop on the way; NO_STAR if none.
best_campaign_target :: proc(g: ^Game, owner: int, at_empires: bool) -> (best, best_staging, best_via: int) {
	total := docked_hits(g, owner)
	weakest := weakest_met(g, owner)
	pct := attack_percent(g, owner)
	best, best_staging, best_via = NO_STAR, NO_STAR, NO_STAR
	best_score, best_d := -1, max(int)
	for t in 0 ..< g.star_count {
		if !campaign_target_ok(g, owner, t, at_empires) {
			continue
		}
		in_ := campaign_intel(g, owner, t)
		if total * 100 < pct * in_.strength || (in_.strength > 0 && total == 0) {
			continue
		}
		staging, via := staging_for(g, owner, t)
		if staging == NO_STAR {
			continue
		}
		d := dist2(g, staging, t)
		score := target_score(g, owner, in_, weakest)
		if score > best_score || (score == best_score && d < best_d) {
			best, best_score, best_d, best_staging, best_via = t, score, d, staging, via
		}
	}
	return
}

// The Carpools the campaign wants at the staging colony (0 if none, or for a fleet or the moth). Since
// step 7 any colony with households to spare builds them, and they gather like the warships.
campaign_carpools_wanted :: proc(g: ^Game, owner: int) -> int {
	c := g.empires[owner].campaign
	if !c.on {
		return 0
	}
	in_ := campaign_intel(g, owner, c.target)
	if in_.owner < 0 {
		return 0
	}
	return carpools_for(in_.households)
}

// After the building: warships gather at the staging colony, and go in once ready. Returns the staging
// colony while the campaign waits there (for `ai_attack` to leave alone), else NO_STAR.
run_campaign :: proc(g: ^Game, owner: int) -> int {
	c := &g.empires[owner].campaign
	if !c.on {
		return NO_STAR
	}
	in_ := campaign_intel(g, owner, c.target)
	if c.hopping {
		// At the stop on the way, refuelled: on to the target with everything there.
		if f := fleet_of(g, c.via, owner); f != nil {
			ships := reaching(g, owner, c.via, c.target, f.ships)
			going := Fleet {
				ships = ships,
			}
			if fleet_size(&going) > 0 {
				send_fleet(g, owner, c.via, c.target, ships)
				g.launched += 1
			}
			c.on = false
			return NO_STAR
		}
		for &o in g.fleets {
			if o.used && o.owner == owner && o.star == NO_STAR && o.to == c.via {
				return NO_STAR // still on the way there
			}
		}
		c.on = false // lost on the way
		return NO_STAR
	}
	need := campaign_carpools_wanted(g, owner)
	if in_.owner >= 0 && bylaw_is(g, .No_Carpools) {
		need = 0 // the rivals keep the bylaws: warships only
	}
	cans := c.via != NO_STAR ? 1 : 0
	if f := fleet_of(g, c.staging, owner); f != nil && f.ships[.Carpool] >= need && f.ships[.Gas_Can] >= cans {
		all := warships_of(f)
		all[.Carpool] = need
		all[.Gas_Can] = cans
		to := c.via != NO_STAR ? c.via : c.target
		ready :: proc(g: ^Game, owner: int, ships: [Ship_Type]int, need, cans, strength: int) -> bool {
			going := Fleet {
				ships = ships,
			}
			hits := warship_hits(&going)
			return ships[.Carpool] >= need && ships[.Gas_Can] >= cans && fleet_size(&going) > 0 && hits * 100 >= attack_percent(g, owner) * strength && (hits > 0 || strength == 0)
		}
		ships := reaching(g, owner, c.staging, to, all)
		if !ready(g, owner, ships, need, cans, in_.strength) && ready(g, owner, all, need, cans, in_.strength) && c.via == NO_STAR {
			// Strong enough, but not all of them can make the trip (older ships have less Commuting
			// kit): stop on the way, with a Gas Can, if there is somewhere; else give it up.
			if w := stopover_for(g, owner, c.staging, c.target, f.kit); w != NO_STAR {
				c.via = w
			} else {
				c.on = false
				g.dropped += 1
				return NO_STAR
			}
		}
		if ready(g, owner, ships, need, cans, in_.strength) {
			send_fleet(g, owner, c.staging, to, ships)
			if c.via != NO_STAR {
				c.hopping = true
				g.hops += 1
				return c.via
			}
			g.launched += 1
			c.on = false
			return NO_STAR
		}
	}
	// Not yet: the warships elsewhere come to the staging colony.
	for i in 0 ..< g.star_count {
		if i == c.staging || colony_of(g, i, owner) == nil {
			continue
		}
		o := fleet_of(g, i, owner)
		if o == nil || stranded(g, o) || (warship_hits(o) == 0 && o.ships[.Carpool] == 0) || threatened(g, owner, i) {
			continue
		}
		war := warships_of(o)
		war[.Carpool] = o.ships[.Carpool]
		if send_problem(g, owner, i, c.staging, war) == "" {
			send_fleet(g, owner, i, c.staging, war)
		}
	}
	return c.staging
}


// The ships of these that can make the trip together: the slowest kind is left behind until the rest
// are in range (the Carpools last).
reaching :: proc(g: ^Game, owner, from, to: int, ships: [Ship_Type]int) -> [Ship_Type]int {
	left := ships
	for {
		trial := Fleet {
			ships = left,
		}
		if fleet_size(&trial) == 0 || send_problem(g, owner, from, to, left) == "" {
			return left
		}
		slow := Ship_Type(0)
		found := false
		for c, t in left {
			if c > 0 && t != .Carpool && (!found || SHIPS[t].speed < SHIPS[slow].speed || (SHIPS[t].speed == SHIPS[slow].speed && SHIPS[t].fuel < SHIPS[slow].fuel)) {
				slow, found = t, true
			}
		}
		if !found {
			left[.Carpool] = 0
		} else {
			left[slow] = 0
		}
	}
}
