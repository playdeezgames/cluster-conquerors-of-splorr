package game

// The Homeowners' Association (slice 1 step 8): the Galactic Council as an HOA. Once every empire still
// in the game has met every other, it meets, then every 25 turns. Each meeting hears complaints (yards
// in a mess, ships parked at someone else's colony, unpaid upgrade fees, and every captured colony
// whose people have not settled in) and fines each 5 % of the empire's BJ. Every other meeting, from
// the first, it votes for a President: votes follow households, the two biggest empires stand, and a
// winner needs two thirds. Everybody hates you, so the rivals never vote for you, and seldom for each
// other. Being President counts as a win; play goes on, and every later meeting costs the President
// 10 BJ. Numbers are starting values (PLAN.md).

COUNCIL_EVERY :: 25 // turns between meetings
FINE_PERCENT :: 5 // of the empire's BJ, per complaint
MESS_WASTE :: 5 // waste lying about at a colony before the neighbours complain
PRESIDENT_DUTY :: 10 // BJ the President pays for every meeting after being elected
RIVAL_BACKS_RIVAL_IN :: 5 // a rival votes for the other rival one time in this many
MINUTES_LINES :: 14

Vote :: enum u8 {
	Abstain,
	First, // candidate 0
	Second, // candidate 1
}

Council :: struct {
	started:    bool, // everyone has met; meetings are being held
	next:       int, // the turn of the next meeting
	meetings:   int,
	president:  int, // NO_OWNER until someone is elected
	elected_turn: int,
	ever_won:   bool, // you have been President (a win; play goes on)
	minutes:    [MINUTES_LINES]Message,
	lines:      int,
	voting:     bool, // this meeting holds a vote, and is waiting for yers
	candidates: [2]int,
	choice:     int, // the highlighted row while voting
	waiting:    bool, // a meeting is ready to show once yer battles are over
}

MINUTES_COLS :: (VIEW_W * TILE - 12) / GLYPH_W

// Adds an entry to the minutes, wrapped at spaces (later lines indented).
minute :: proc(c: ^Council, s: string) {
	rest := s
	first := true
	for len(rest) > 0 && c.lines < MINUTES_LINES {
		width := first ? MINUTES_COLS : MINUTES_COLS - 2
		cut := min(len(rest), width, LOG_CAP - 2)
		if cut < len(rest) {
			for i := cut; i > 0; i -= 1 {
				if rest[i] == ' ' {
					cut = i
					break
				}
			}
		}
		m := &c.minutes[c.lines]
		m^ = {}
		lead := first ? "" : "  "
		copy(m.text[:len(lead)], lead)
		copy(m.text[len(lead):len(lead) + cut], rest[:cut])
		m.n = len(lead) + cut
		c.lines += 1
		rest = rest[cut:]
		for len(rest) > 0 && rest[0] == ' ' {
			rest = rest[1:]
		}
		first = false
	}
}

// "you" or "the Owls", for the minutes.
who :: proc(g: ^Game, owner: int) -> string {
	@(static) b: Text
	if owner == PLAYER {
		return "you"
	}
	b = {}
	add(&b, "the ")
	add(&b, empire_name(g, owner))
	return text(&b)
}

alive_empire :: proc(g: ^Game, e: int) -> bool {
	return !g.empires[e].out
}

everyone_has_met :: proc(g: ^Game) -> bool {
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if a != b && alive_empire(g, a) && alive_empire(g, b) && !g.empires[a].met[b] {
				return false
			}
		}
	}
	return true
}

households_of :: proc(g: ^Game, owner: int) -> int {
	n := 0
	for i in 0 ..< g.star_count {
		if c := colony_of(g, i, owner); c != nil {
			n += c.households
		}
	}
	return n
}

// At the end of a turn: starts the meetings once everyone has met, and holds one when it is due.
council_turn :: proc(g: ^Game) {
	c := &g.council
	if !c.started {
		if !everyone_has_met(g) {
			return
		}
		c.started = true
		c.next = g.turn
		c.president = NO_OWNER
	}
	if g.turn < c.next || g.outcome != .Playing {
		return
	}
	hold_meeting(g)
	c.next = g.turn + COUNCIL_EVERY
}

fine :: proc(g: ^Game, owner: int, why: string) {
	c := &g.council
	e := &g.empires[owner]
	amount := e.bj * FINE_PERCENT / 100
	e.bj -= amount
	for other in 0 ..< g.empire_count {
		add_grudge(g, other, owner, GRUDGE_COMPLAINT)
	}
	b: Text
	add(&b, "Complaint, ")
	add(&b, who(g, owner))
	add(&b, ": ")
	add(&b, why)
	add(&b, " Fined ")
	add_int(&b, amount)
	add(&b, " BJ.")
	minute(c, text(&b))
}

// The complaints against an empire this meeting.
complaints :: proc(g: ^Game, owner: int) {
	// Every captured colony whose people have not settled in.
	for i in 0 ..< g.star_count {
		col := colony_of(g, i, owner)
		if col == nil || col.captured == 0 {
			continue
		}
		b: Text
		add(&b, "the ")
		add(&b, RACES[col.race].name)
		add(&b, " of Lot ")
		add_int(&b, i + 1)
		add(&b, " would like to speak to the manager.")
		fine(g, owner, text(&b))
	}
	// And at most one other.
	for i in 0 ..< g.star_count {
		col := colony_of(g, i, owner)
		if col != nil && col.waste >= MESS_WASTE {
			b: Text
			add(&b, "the yards at Lot ")
			add_int(&b, i + 1)
			add(&b, " are a mess.")
			fine(g, owner, text(&b))
			return
		}
	}
	for &f in g.fleets {
		if !f.used || f.owner != owner || f.star == NO_STAR {
			continue
		}
		col := any_colony(g, f.star)
		if col != nil && col.owner != owner {
			b: Text
			add(&b, "ships parked at Lot ")
			add_int(&b, f.star + 1)
			add(&b, ", which is not theirs.")
			fine(g, owner, text(&b))
			return
		}
	}
	for &f in g.fleets {
		if f.used && f.owner == owner && owed(g, &f) > 0 {
			fine(g, owner, "upgrade fees unpaid.")
			return
		}
	}
}

// A meeting: the President's duty, the complaints, and (every other meeting) the vote.
hold_meeting :: proc(g: ^Game) {
	c := &g.council
	c.meetings += 1
	c.lines = 0
	c.voting = false
	b: Text
	add(&b, "Minutes of the Homeowners' Association, meeting ")
	add_int(&b, c.meetings)
	add(&b, ", turn ")
	add_int(&b, g.turn)
	add(&b, ".")
	minute(c, text(&b))
	if c.president != NO_OWNER && alive_empire(g, c.president) {
		p := &g.empires[c.president]
		paid := min(p.bj, PRESIDENT_DUTY)
		p.bj -= paid
		d: Text
		add(&d, "The President (")
		add(&d, who(g, c.president))
		add(&d, ") pays ")
		add_int(&d, paid)
		add(&d, " BJ for the biscuits.")
		minute(c, text(&d))
	}
	for e in 0 ..< g.empire_count {
		if alive_empire(g, e) {
			complaints(g, e)
		}
	}
	if c.lines == 1 {
		minute(c, "No complaints. Nobody believes it.")
	}
	if c.meetings % 2 == 1 {
		start_vote(g)
	}
	if g.mode == .Map {
		g.mode = .Council
		c.choice = 0
	} else {
		c.waiting = true
	}
	say(g, "The Homeowners' Association has met. The minutes are on yer doormat.")
}

// The two empires with the most households stand.
start_vote :: proc(g: ^Game) {
	c := &g.council
	first, second := NO_OWNER, NO_OWNER
	for e in 0 ..< g.empire_count {
		if !alive_empire(g, e) {
			continue
		}
		if first == NO_OWNER || households_of(g, e) > households_of(g, first) {
			first, second = e, first
		} else if second == NO_OWNER || households_of(g, e) > households_of(g, second) {
			second = e
		}
	}
	if first == NO_OWNER || second == NO_OWNER {
		return
	}
	c.candidates = {first, second}
	c.voting = true
	b: Text
	add(&b, "Standing for President: ")
	add(&b, who(g, first))
	add(&b, " and ")
	add(&b, who(g, second))
	add(&b, ".")
	minute(c, text(&b))
}

// How a rival votes: for itself if it stands; never for you; for the other rival now and then.
rival_vote :: proc(g: ^Game, e: int) -> Vote {
	c := &g.council
	for k in 0 ..< 2 {
		if c.candidates[k] == e {
			return Vote(k + 1)
		}
	}
	for k in 0 ..< 2 {
		other := c.candidates[k]
		if other != PLAYER && rng_int(&g.rng, RIVAL_BACKS_RIVAL_IN) == 0 {
			return Vote(k + 1)
		}
	}
	return .Abstain
}

// Counts the votes with yers, and elects whoever has two thirds of all households.
cast_votes :: proc(g: ^Game, mine: Vote) {
	c := &g.council
	if !c.voting {
		return
	}
	c.voting = false
	tally: [3]int
	total := 0
	for e in 0 ..< g.empire_count {
		if !alive_empire(g, e) {
			continue
		}
		weight := households_of(g, e)
		total += weight
		v := e == PLAYER ? mine : rival_vote(g, e)
		tally[int(v)] += weight
	}
	b: Text
	add(&b, "Votes: ")
	add_int(&b, tally[1])
	add(&b, " for ")
	add(&b, who(g, c.candidates[0]))
	add(&b, ", ")
	add_int(&b, tally[2])
	add(&b, " for ")
	add(&b, who(g, c.candidates[1]))
	add(&b, ", ")
	add_int(&b, tally[0])
	add(&b, " abstaining.")
	minute(c, text(&b))
	winner := NO_OWNER
	for k in 0 ..< 2 {
		if tally[k + 1] * 3 >= total * 2 {
			winner = c.candidates[k]
		}
	}
	if winner == NO_OWNER {
		minute(c, "Nobody has two thirds. The meeting is adjourned until the next one.")
		return
	}
	c.president = winner
	c.elected_turn = g.turn
	if winner == PLAYER {
		c.ever_won = true
		minute(c, "Yer the President of the Homeowners' Association. Congratulations. Meetings are now yer job.")
	} else {
		r: Text
		add(&r, "The ")
		add(&r, empire_name(g, winner))
		add(&r, " are President. They look as pleased as you would.")
		minute(c, text(&r))
	}
}

// Opens a meeting that was held while yer battles were on, once they are over.
show_waiting_meeting :: proc(g: ^Game) -> bool {
	if !g.council.waiting {
		return false
	}
	g.council.waiting = false
	g.mode = .Council
	g.council.choice = 0
	return true
}

COUNCIL_CHOICES :: 3 // while voting: the first candidate, the second, abstain

// While voting: Up/Down pick, Enter/OK votes. Otherwise Enter/OK (or Escape/Back) closes the minutes.
council_command :: proc(g: ^Game, cmd: Command) {
	c := &g.council
	if c.voting {
		#partial switch cmd {
		case .North:
			c.choice = (c.choice + COUNCIL_CHOICES - 1) % COUNCIL_CHOICES
		case .South:
			c.choice = (c.choice + 1) % COUNCIL_CHOICES
		case .Confirm:
			cast_votes(g, council_vote_of(c.choice))
		}
		return
	}
	#partial switch cmd {
	case .Confirm, .Cancel:
		g.mode = .Map
	}
}

council_vote_of :: proc(choice: int) -> Vote {
	switch choice {
	case 0:
		return .First
	case 1:
		return .Second
	}
	return .Abstain
}
