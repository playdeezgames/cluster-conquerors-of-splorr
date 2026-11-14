package game

// The President's rulings (slice 2 step 7). A meeting's complaints go on a docket, each brought by the
// empire that hates the accused most. With nobody President the fines simply stand. A President rules
// on each one: uphold it (the fine stands), dismiss it (no fine; the complainer holds it against the
// President) or double it (twice the fine; the accused holds it against the President). Yers come to you
// one at a time on the meeting screen before the bylaw vote; a computer President rules by its grudges.

MAX_COMPLAINTS :: 8 // complaints heard at one meeting
GRUDGE_DISMISSED :: 10 // the complainer's, against the President
GRUDGE_DOUBLED :: 10 // the accused's, against the President
AI_DOUBLES_AT :: 75 // a computer President doubles fines on anyone it hates this much

Ruling :: enum u8 {
	Uphold,
	Dismiss,
	Double,
}

RULING_ROWS := [Ruling]string {
	.Uphold  = "Uphold: the fine stands",
	.Dismiss = "Dismiss: no fine, and the complainer minds",
	.Double  = "Double: twice the fine, and the accused minds",
}

Complaint :: struct {
	accused:    int,
	complainer: int,
	why:        Text, // "the yards at Lot 11 are a mess."
}

// Puts a complaint on the docket, brought by whoever hates the accused most.
complain :: proc(g: ^Game, accused: int, why: string) {
	c := &g.council
	if c.docket_n >= MAX_COMPLAINTS {
		return
	}
	by := NO_OWNER
	for e in 0 ..< g.empire_count {
		if e != accused && alive_empire(g, e) && (by == NO_OWNER || g.empires[e].grudge[accused] > g.empires[by].grudge[accused]) {
			by = e
		}
	}
	k := &c.docket[c.docket_n]
	k^ = {accused = accused, complainer = by}
	add(&k.why, why)
	c.docket_n += 1
}

president_sits :: proc(g: ^Game) -> bool {
	p := g.council.president
	return p != NO_OWNER && alive_empire(g, p)
}

// Works down the docket: stops for yer ruling while yer President, otherwise rules and goes on to the
// rest of the meeting.
hear_complaints :: proc(g: ^Game) {
	c := &g.council
	for c.docket_i < c.docket_n {
		if !president_sits(g) {
			rule(g, .Uphold)
			continue
		}
		if c.president == PLAYER {
			c.ruling = true
			return
		}
		rule(g, ai_ruling(g, c.president, &c.docket[c.docket_i]))
	}
	c.ruling = false
	finish_meeting(g)
}

// A computer President: dismisses complaints against itself and its pact partners, doubles them on
// anyone it hates enough, and upholds the rest.
ai_ruling :: proc(g: ^Game, president: int, k: ^Complaint) -> Ruling {
	switch {
	case k.accused == president || has_pact(g, president, k.accused):
		return .Dismiss
	case g.empires[president].grudge[k.accused] >= AI_DOUBLES_AT:
		return .Double
	}
	return .Uphold
}

// Rules on the complaint at the top of the docket and writes it into the minutes.
rule :: proc(g: ^Game, r: Ruling) {
	c := &g.council
	k := &c.docket[c.docket_i]
	c.docket_i += 1
	g.rulings[r] += 1
	if !president_sits(g) {
		fine(g, k.accused, text(&k.why))
		return
	}
	p := c.president
	switch r {
	case .Uphold:
		fine(g, k.accused, text(&k.why), 1, "Upheld, fined")
	case .Double:
		fine(g, k.accused, text(&k.why), 2, "Doubled, fined")
		if k.accused != p {
			add_grudge(g, k.accused, p, GRUDGE_DOUBLED)
		}
	case .Dismiss:
		b: Text
		add(&b, "Complaint, ")
		add(&b, who(g, k.accused))
		add(&b, ": ")
		add(&b, text(&k.why))
		add(&b, " Dismissed.")
		minute(c, text(&b))
		if k.complainer != NO_OWNER && k.complainer != p {
			add_grudge(g, k.complainer, p, GRUDGE_DISMISSED)
		}
	}
}

// After the complaints: the bylaw vote and, every other meeting, the vote for President.
finish_meeting :: proc(g: ^Game) {
	c := &g.council
	if c.docket_n == 0 {
		minute(c, "No complaints. Nobody believes it.")
	}
	propose_bylaws(g)
	if c.meetings % 2 == 1 {
		start_vote(g)
	}
}

// Up/Down pick a ruling, Enter/OK (or a tap) gives it.
give_ruling :: proc(g: ^Game, r: Ruling) {
	rule(g, r)
	g.council.choice = 0
	hear_complaints(g)
}
