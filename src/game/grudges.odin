package game

// Grudges (slice 2 step 1): every empire keeps a hidden ledger of how much it hates every other one,
// 0 to 100. Against you it starts high and never cools below that; against each other the rivals
// start lower. Dogs are hated a little less to begin with. Battles, landings, captures and complaints
// add to a grudge; each turn it cools by a point, down to where it started. The rivals pick whom to
// attack and invade by it, and you hear about it only as gossip. Numbers are Claude's (PLAN.md).

GRUDGE_MAX :: 100
GRUDGE_AT_YOU :: 60 // where the rivals start against you
GRUDGE_AT_RIVAL :: 30 // where empires start against each other
DOG_GRUDGE_OFF :: 20 // Dogs start this much lower on both
GRUDGE_COOL :: 1 // a turn, down to the start
GRUDGE_BATTLE :: 10 // each side, for every battle
GRUDGE_LANDING :: 10 // the defender, for a landing seen off
GRUDGE_CAPTURE :: 25 // the defender, for a colony taken
GRUDGE_COMPLAINT :: 5 // everyone else, against an empire fined at a meeting
GRUDGE_AT_MOTH :: 45 // how much the rivals mind the moth, for choosing targets

// Where an empire's grudge against another starts, and the floor it cools to.
grudge_floor :: proc(g: ^Game, against: int) -> int {
	base := against == PLAYER ? GRUDGE_AT_YOU : GRUDGE_AT_RIVAL
	if g.empires[against].race == .Dogs {
		base -= DOG_GRUDGE_OFF
	}
	return base
}

// Everyone's grudges back to where they start (after the species are known).
reset_grudges :: proc(g: ^Game) {
	for a in 0 ..< MAX_EMPIRES {
		for b in 0 ..< MAX_EMPIRES {
			g.empires[a].grudge[b] = a == b ? 0 : grudge_floor(g, b)
		}
		g.empires[a].mood = mood_of(g.empires[a].grudge[PLAYER])
	}
}

// Adds to `holder`'s grudge against `against`.
add_grudge :: proc(g: ^Game, holder, against, amount: int) {
	if holder < 0 || against < 0 || holder == against || holder >= g.empire_count || against >= g.empire_count {
		return
	}
	gr := &g.empires[holder].grudge[against]
	gr^ = clamp(gr^ + amount, 0, GRUDGE_MAX)
}

// How much `holder` minds whatever it saw at a star: the owner's grudge, or the moth's.
grudge_at :: proc(g: ^Game, holder: int, in_: Intel) -> int {
	if in_.owner >= 0 {
		return g.empires[holder].grudge[in_.owner]
	}
	return GRUDGE_AT_MOTH
}

// The gossip that tells you how a rival feels, in bands.
Mood :: enum u8 {
	Nodding, // under 40
	Not_Waving, // 40 to 59
	Petition, // 60 to 79
	Bins, // 80 and over
}

mood_of :: proc(grudge: int) -> Mood {
	switch {
	case grudge >= 80:
		return .Bins
	case grudge >= 60:
		return .Petition
	case grudge >= 40:
		return .Not_Waving
	}
	return .Nodding
}

MOOD_NEWS := [Mood]string {
	.Nodding    = "nod at you over the fence. It does not mean anything.",
	.Not_Waving = "have stopped waving.",
	.Petition   = "have started a petition about you.",
	.Bins       = "have written yer name on their bins.",
}

// At the end of a turn: grudges cool, and you hear when a rival you have met feels differently.
grudge_turn :: proc(g: ^Game) {
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if a == b {
				continue
			}
			gr := &g.empires[a].grudge[b]
			floor := grudge_floor(g, b)
			if gr^ > floor {
				gr^ = max(floor, gr^ - GRUDGE_COOL)
			}
		}
	}
	for e in 1 ..< g.empire_count {
		emp := &g.empires[e]
		m := mood_of(emp.grudge[PLAYER])
		if m == emp.mood {
			continue
		}
		emp.mood = m
		if emp.out || !g.empires[PLAYER].met[e] {
			continue
		}
		b: Text
		add(&b, "The ")
		add(&b, empire_name(g, e))
		add(&b, " ")
		add(&b, MOOD_NEWS[m])
		say(g, text(&b))
	}
}
