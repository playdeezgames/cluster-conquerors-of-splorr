package game

// Giveaways (slice 3 step 10, the user's decision, PLAN.md Decided 9): nobody tells you a rival's
// temper or aim. Each comes out on its own, the first time the rival acts in character where you can
// see it; the news hints at it ("The Rabbits tore up the pact with you. Two-faced, the neighbours
// say.") and the forms desk shows it from then on. A rival that never acts in character stays unknown.
// The giveaways are Claude's draft, accepted by the user as the first draft; the numbers are Claude's.
//   Petty: its grudge at you passes PETTY_GIVEAWAY.      Builder: a second new colony of its seen settled.
//   Pushy: a demand on yer doormat.                      Bully: a battle seen with the weakest it has met.
//   Two-faced: a pact it tears up (with you, or between   Busybody: a gripe of its own at a meeting.
//     two empires you have met).                         Committee type: standing for President.
//   Neighbourly: a pact or trade it signs with you.      Tinkerer: a swap offer on yer doormat.
//   Touchy: a watcher of yers caught on it, or a fine of yers doubled against it.

PETTY_GIVEAWAY :: 90 // the grudge at you that gives a Petty rival away
BUILDER_GIVEAWAY :: 2 // new colonies of a Builder's seen settled

TEMPER_HINTS := [Temper]string {
	.None        = "",
	.Petty       = " are still going on about it",
	.Pushy       = " want paying, and they want it now",
	.Two_Faced   = "", // the pact it tore up says it
	.Neighbourly = " signed it with a smile",
	.Touchy      = " took that very personally",
}

AIM_HINTS := [Aim]string {
	.None      = "",
	.Builder   = " are unpacking another van",
	.Bully     = " picked on the smallest on the street",
	.Busybody  = " have filed a gripe of their own",
	.Committee = " are standing for President",
	.Tinkerer  = " want to swap notes",
}

// Whether a rival's temper or aim is known to you.
temper_known :: proc(g: ^Game, e: int) -> bool {
	return e > 0 && e < g.empire_count && g.empires[e].temper_known
}

aim_known :: proc(g: ^Game, e: int) -> bool {
	return e > 0 && e < g.empire_count && g.empires[e].aim_known
}

// Whether a giveaway from `e` can reach you at all: a rival you have met and that is still about.
can_give_away :: proc(g: ^Game, e: int) -> bool {
	return e > 0 && e < g.empire_count && !g.empires[e].out && g.empires[PLAYER].met[e]
}

// "Petty" or "Committee types", at the start of a sentence.
capital :: proc(b: ^Text, s: string) {
	if len(s) == 0 {
		return
	}
	first := s[0]
	if first >= 'a' && first <= 'z' {
		first -= 'a' - 'A'
	}
	add(b, string([]u8{first}))
	add(b, s[1:])
}

// `e` acted like a rival of temper `t`: if it is one, and you did not know, now you do. `hint`, if
// given, replaces the temper's own.
give_away_temper :: proc(g: ^Game, e: int, t: Temper, hint := "") {
	if !can_give_away(g, e) || temper_of(g, e) != t || g.empires[e].temper_known {
		return
	}
	g.empires[e].temper_known = true
	g.giveaways += 1
	b: Text
	add(&b, "The ")
	add(&b, empire_name(g, e))
	add(&b, hint != "" ? hint : TEMPER_HINTS[t])
	add(&b, ". ")
	capital(&b, TEMPERS[t].name)
	add(&b, ", the neighbours say.")
	say(g, text(&b))
}

// `e` acted like a rival with aim `a`: if it has that aim, and you did not know, now you do.
give_away_aim :: proc(g: ^Game, e: int, a: Aim) {
	if !can_give_away(g, e) || aim_of(g, e) != a || g.empires[e].aim_known {
		return
	}
	g.empires[e].aim_known = true
	g.giveaways += 1
	b: Text
	add(&b, "The ")
	add(&b, empire_name(g, e))
	add(&b, AIM_HINTS[a])
	add(&b, ". ")
	capital(&b, AIMS[a].plural)
	add(&b, ", the neighbours say.")
	say(g, text(&b))
}

// A battle between a Bully and the weakest empire it has met, where you could see it.
bully_battle :: proc(g: ^Game, bt: ^Battle) {
	for side in 0 ..< 2 {
		o, other := bt.owners[side], bt.owners[1 - side]
		if o <= 0 || other < 0 || aim_of(g, o) != .Bully || aim_known(g, o) {
			continue
		}
		if (other == PLAYER || g.empires[PLAYER].sees[bt.star]) && other == weakest_met(g, o) {
			give_away_aim(g, o, .Bully)
		}
	}
}

// A new colony settled by `owner` at `star`: a Builder's second one you see gives it away.
builder_settled :: proc(g: ^Game, owner, star: int) {
	if owner <= 0 || !g.empires[PLAYER].sees[star] || !can_give_away(g, owner) {
		return
	}
	g.empires[owner].settled_seen += 1
	if g.empires[owner].settled_seen >= BUILDER_GIVEAWAY {
		give_away_aim(g, owner, .Builder)
	}
}
