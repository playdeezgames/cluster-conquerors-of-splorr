package game

// Bylaws (slice 2 step 6). Every meeting of the Homeowners' Association puts two bylaws from the book to
// a vote by households; the one with more votes binds every empire until the next meeting (a tie, or
// nobody voting, leaves none). Some simply happen (quiet hours halve research; a jumble sale costs
// everyone 10 BJ at once); some change what the neighbours complain about (tidy yards, no parking); the
// rest forbid something, and doing it anyway is a complaint and a fine at the next meeting. The rivals
// obey them, and vote for whichever would hurt the empire they hate most.

JUMBLE_SALE_BJ :: 10
TIDY_WASTE :: 2 // waste at a colony before the neighbours complain, under tidy yards

Bylaw :: enum u8 {
	None,
	Small_Trucks, // no warships bigger than a Pickup
	Quiet_Hours, // research halved
	No_Carpools,
	No_Parking, // ships not at their own (or an ally's) colonies are complained about
	Tidy_Yards, // waste over 2 is a complaint
	No_New_Houses, // no Moving Vans
	Fence_Height, // no new bases
	Jumble_Sale, // everyone pays 10 BJ
}

Bylaw_Info :: struct {
	name: string, // for the panel and the ballot: "no new houses"
	says: string, // for the minutes
}

BYLAWS := [Bylaw]Bylaw_Info {
	.None          = {"none", "No bylaw is in force."},
	.Small_Trucks  = {"small trucks", "No Monster Trucks. Pickups are as big as anyone needs."},
	.Quiet_Hours   = {"quiet hours", "Book Clubs keep it down: research is halved."},
	.No_Carpools   = {"no carpools", "No Carpools built and none landed."},
	.No_Parking    = {"no parking", "No ships parked anywhere but at their own colonies."},
	.Tidy_Yards    = {"tidy yards", "Yards with any mess at all are a complaint."},
	.No_New_Houses = {"no new houses", "No Moving Vans built and nobody settles."},
	.Fence_Height  = {"fence height", "No new defence bases. Fences spoil the view."},
	.Jumble_Sale   = {"jumble sale", "A jumble sale: everyone pays 10 BJ. Nobody buys anything."},
}

bylaw_is :: proc(g: ^Game, b: Bylaw) -> bool {
	return g.council.bylaw == b
}

// Whether the bylaw in force forbids building this ship.
bylaw_bans :: proc(g: ^Game, t: Ship_Type) -> bool {
	#partial switch g.council.bylaw {
	case .Small_Trucks:
		return t == .Monster_Truck
	case .No_Carpools:
		return t == .Carpool
	case .No_New_Houses:
		return t == .Moving_Van
	}
	return false
}

// Someone did what the bylaw forbids: a complaint at the next meeting.
break_bylaw :: proc(g: ^Game, owner: int, what: string) {
	c := &g.council
	if !c.broke[owner] && owner == PLAYER {
		b: Text
		add(&b, what)
		add(&b, " That breaks the bylaw (")
		add(&b, BYLAWS[c.bylaw].name)
		add(&b, "). The Association will hear of it.")
		say(g, text(&b))
	}
	c.broke[owner] = true
}

// At a meeting, among the complaints: whoever broke the bylaw in force since the last one.
bylaw_complaints :: proc(g: ^Game) {
	c := &g.council
	for e in 0 ..< g.empire_count {
		if c.broke[e] && alive_empire(g, e) {
			b: Text
			add(&b, "broke the bylaw (")
			add(&b, BYLAWS[c.bylaw].name)
			add(&b, ").")
			complain(g, e, text(&b))
		}
	}
	c.broke = {}
}

// Two bylaws from the book, not the one in force, for the meeting to vote on.
propose_bylaws :: proc(g: ^Game) {
	c := &g.council
	book: [len(Bylaw) - 1]Bylaw
	n := 0
	for b in Bylaw {
		if b != .None && b != c.bylaw {
			book[n] = b
			n += 1
		}
	}
	i := rng_int(&g.rng, n)
	j := rng_int(&g.rng, n - 1)
	if j >= i {
		j += 1
	}
	c.proposals = {book[i], book[j]}
	c.bylaw_voting = true
	t: Text
	add(&t, "Proposed bylaws: ")
	add(&t, BYLAWS[book[i]].name)
	add(&t, ", or ")
	add(&t, BYLAWS[book[j]].name)
	add(&t, ".")
	minute(c, text(&t))
}

// How much a bylaw would cost an empire, roughly, for the rivals' votes.
bylaw_hurt :: proc(g: ^Game, b: Bylaw, e: int) -> int {
	switch b {
	case .None:
		return 0
	case .Small_Trucks:
		return 5 * ships_owned(g, e, .Monster_Truck)
	case .Quiet_Hours:
		rp := 0
		for i in 0 ..< g.star_count {
			if colony_of(g, i, e) != nil {
				rp += research_points(g, i)
			}
		}
		return rp / 5
	case .No_Carpools:
		return 5 * ships_owned(g, e, .Carpool)
	case .No_Parking:
		n := 0
		for &f in g.fleets {
			if f.used && f.owner == e && f.star != NO_STAR && !parked_at_home(g, &f) {
				n += 5
			}
		}
		return n
	case .Tidy_Yards:
		n := 0
		for i in 0 ..< g.star_count {
			if c := colony_of(g, i, e); c != nil && c.waste >= TIDY_WASTE {
				n += 5
			}
		}
		return n
	case .No_New_Houses:
		n := 5 * ships_owned(g, e, .Moving_Van)
		if best_settle_target(g, e, g.empires[e].home, nil) != NO_STAR {
			n += 3
		}
		return n
	case .Fence_Height:
		n := 0
		for i in 0 ..< g.star_count {
			if c := colony_of(g, i, e); c != nil && c.slider[.Fencing] > 0 {
				n += 3
			}
		}
		return n
	case .Jumble_Sale:
		return g.empires[e].bj < 5 * JUMBLE_SALE_BJ ? JUMBLE_SALE_BJ : 2
	}
	return 0
}

// Whether a fleet is parked where the no-parking bylaw allows: at its own colony or an ally's.
parked_at_home :: proc(g: ^Game, f: ^Fleet) -> bool {
	c := any_colony(g, f.star)
	return c != nil && (c.owner == f.owner || allied(g, f.owner, c.owner))
}

// A rival votes for whichever proposal hurts the empire it hates most more; on a tie it abstains.
rival_bylaw_vote :: proc(g: ^Game, e: int) -> Vote {
	c := &g.council
	target := -1
	for o in 0 ..< g.empire_count {
		if o != e && alive_empire(g, o) && (target < 0 || g.empires[e].grudge[o] > g.empires[e].grudge[target]) {
			target = o
		}
	}
	if target < 0 {
		return .Abstain
	}
	a, b := bylaw_hurt(g, c.proposals[0], target), bylaw_hurt(g, c.proposals[1], target)
	switch {
	case a > b:
		return .First
	case b > a:
		return .Second
	}
	return .Abstain
}

// Counts the bylaw votes with yers; the winner is in force until the next meeting.
cast_bylaw_votes :: proc(g: ^Game, mine: Vote) {
	c := &g.council
	if !c.bylaw_voting {
		return
	}
	c.bylaw_voting = false
	tally: [3]int
	for e in 0 ..< g.empire_count {
		if alive_empire(g, e) {
			v := e == PLAYER ? mine : rival_bylaw_vote(g, e)
			tally[int(v)] += households_of(g, e)
		}
	}
	won := Bylaw.None
	switch {
	case tally[1] > tally[2]:
		won = c.proposals[0]
	case tally[2] > tally[1]:
		won = c.proposals[1]
	}
	b: Text
	add(&b, "Bylaw votes: ")
	add_int(&b, tally[1])
	add(&b, " for ")
	add(&b, BYLAWS[c.proposals[0]].name)
	add(&b, ", ")
	add_int(&b, tally[2])
	add(&b, " for ")
	add(&b, BYLAWS[c.proposals[1]].name)
	add(&b, ". ")
	if won == .None {
		add(&b, "No bylaw until the next meeting.")
	} else {
		add(&b, "Passed: ")
		add(&b, BYLAWS[won].says)
	}
	minute(c, text(&b))
	pass_bylaw(g, won)
}

pass_bylaw :: proc(g: ^Game, b: Bylaw) {
	c := &g.council
	c.bylaw = b
	c.broke = {}
	g.bylaws_passed += b != .None ? 1 : 0
	if b == .Jumble_Sale {
		for e in 0 ..< g.empire_count {
			g.empires[e].bj -= min(g.empires[e].bj, JUMBLE_SALE_BJ)
		}
	}
	t: Text
	if b == .None {
		add(&t, "No bylaw is in force until the next meeting.")
	} else {
		add(&t, "New bylaw (")
		add(&t, BYLAWS[b].name)
		add(&t, "): ")
		add(&t, BYLAWS[b].says)
	}
	say(g, text(&t))
}
