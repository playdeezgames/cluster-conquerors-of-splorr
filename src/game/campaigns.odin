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

CAMPAIGN_TURNS :: 30
CARPOOL_SPARE :: CARPOOL_LOAD * 2 // a colony builds Carpools only with more households than this

Campaign :: struct {
	on:      bool,
	target:  int,
	staging: int,
	since:   int, // the turn it was planned
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

// Whether a fleet of warships and Carpools with the empire's kit, full of fuel, reaches `to` from `from`.
campaign_reaches :: proc(g: ^Game, owner, from, to: int) -> bool {
	trial := Fleet {
		ships = ship_one(.Golf_Cart),
		kit   = empire_kit(g, owner),
	}
	trial.ships[.Carpool] = 1
	return trip_turns(g, from, to, fleet_speed(&trial)) <= fleet_range(&trial)
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

// The empire's colony nearest `to` that can reach it, or NO_STAR.
staging_for :: proc(g: ^Game, owner, to: int) -> int {
	best, best_d := NO_STAR, max(int)
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) == nil || i == to || !campaign_reaches(g, owner, i, to) {
			continue
		}
		a, b := g.stars[i], g.stars[to]
		d := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// Each turn, before the colonies choose what to build: the campaign is checked, given up or planned.
plan_campaign :: proc(g: ^Game, owner: int, at_empires: bool) {
	c := &g.empires[owner].campaign
	if c.on && (!campaign_target_ok(g, owner, c.target, at_empires) || colony_of(g, c.staging, owner) == nil) {
		c.on = false
		g.dropped += 1
	}
	if c.on && g.turn - c.since > CAMPAIGN_TURNS {
		c.on = false
		g.timed_out += 1
	}
	if c.on {
		return
	}
	total := docked_hits(g, owner)
	weakest := weakest_met(g, owner)
	pct := attack_percent(g, owner)
	best, best_score, best_d, best_staging := NO_STAR, -1, max(int), NO_STAR
	for t in 0 ..< g.star_count {
		if !campaign_target_ok(g, owner, t, at_empires) {
			continue
		}
		in_ := campaign_intel(g, owner, t)
		if total * 100 < pct * in_.strength || (in_.strength > 0 && total == 0) {
			continue
		}
		staging := staging_for(g, owner, t)
		if staging == NO_STAR {
			continue
		}
		a, b := g.stars[staging], g.stars[t]
		d := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
		score := target_score(g, owner, in_, weakest)
		if score > best_score || (score == best_score && d < best_d) {
			best, best_score, best_d, best_staging = t, score, d, staging
		}
	}
	if best != NO_STAR {
		c^ = {true, best, best_staging, g.turn}
		g.planned += 1
	}
}

// The Carpools the campaign still needs built at the staging colony (0 if none, or for a fleet or the
// moth, or when the staging colony is too small to spare them).
campaign_carpools_wanted :: proc(g: ^Game, owner: int) -> int {
	c := g.empires[owner].campaign
	if !c.on {
		return 0
	}
	in_ := campaign_intel(g, owner, c.target)
	col := colony_of(g, c.staging, owner)
	if in_.owner < 0 || col == nil || col.households <= CARPOOL_SPARE {
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
	need := campaign_carpools_wanted(g, owner)
	if in_.owner >= 0 && bylaw_is(g, .No_Carpools) {
		need = 0 // the rivals keep the bylaws: warships only
	}
	if f := fleet_of(g, c.staging, owner); f != nil && f.ships[.Carpool] >= need {
		ships := warships_of(f)
		ships[.Carpool] = need
		ships = reaching(g, owner, c.staging, c.target, ships)
		going := Fleet {
			ships = ships,
		}
		hits := warship_hits(&going)
		if ships[.Carpool] >= need && fleet_size(&going) > 0 && hits * 100 >= attack_percent(g, owner) * in_.strength && (hits > 0 || in_.strength == 0) {
			send_fleet(g, owner, c.staging, c.target, ships)
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
		if o == nil || stranded(g, o) || warship_hits(o) == 0 {
			continue
		}
		war := warships_of(o)
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
