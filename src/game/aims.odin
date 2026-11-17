package game

// Aims (slice 3 step 5): every rival is dealt one, different from the others', alongside its temper
// (tempers.odin). The temper steers how it feels; the aim steers what it does: its colonies' sliders,
// what it builds, its Watch, its complaints, its votes, its forms and whom it goes to war with. You
// learn it when you first meet that rival, and the forms desk shows it. Numbers are Claude's (PLAN.md).
//   Builder: factories and settling first (10 more to Home Improvement, two Moving Vans at a time); it
//     starts no war while it still has somewhere to settle.
//   Bully: warships (10 more to Parking, Pickups at home), and war on the weakest empire it has met,
//     attacking at a smaller edge.
//   Busybody: twice the Watch budget, it brings every complaint it can, and each meeting it files one of
//     its own against whoever it hates most.
//   Committee type: households and votes (15 more to Lawn Care, which grows households); a pact with it
//     is worth more to it, and the others back it for President twice as often.
//   Tinkerer: research first (20 more to Book Club), a swap is worth 30 more to it, and now and then it
//     offers you one on yer doormat.

Aim :: enum u8 {
	None, // yers
	Builder,
	Bully,
	Busybody,
	Committee,
	Tinkerer,
}

Aim_Info :: struct {
	name:   string,
	plural: string, // "The Rabbits are <plural>."
	says:   string, // after "Aim: <name>. " (the line fits the desk's 58 columns)
}

AIMS := [Aim]Aim_Info {
	.None      = {"none", "", ""},
	.Builder   = {"Builder", "Builders", "Factories and settling first."},
	.Bully     = {"Bully", "Bullies", "Warships, and war on the weakest."},
	.Busybody  = {"Busybody", "Busybodies", "A big Watch, and complaints."},
	.Committee = {"Committee type", "committee types", "Households, votes, the presidency."},
	.Tinkerer  = {"Tinkerer", "Tinkerers", "Research first; swaps techs freely."},
}

AIM_SHIFT :: 10 // slider points a Builder or a Bully moves to its chore
TINKERER_BOOKS :: 20 // more to Book Club
COMMITTEE_CARE :: 15 // more to Lawn Care
BUILDER_VANS :: 2 // Moving Vans on the way at once
BULLY_ATTACK_PERCENT :: 125 // the share of what it saw there a Bully attacks with (150 for the others)
BULLY_WEAK_BONUS :: 40 // added to its grudge at the weakest empire it has met, for choosing targets
BUSYBODY_WATCH :: 2 // times the usual Watch budget
COMMITTEE_PACT :: 15 // more value in a pact or an alliance
COMMITTEE_BACKED_IN :: 2 // the others vote for a Committee type one time in this many (5 for the others)
TINKERER_SWAP :: 30 // more value in a swap
TINKERER_SWAP_IN :: 2 // a Tinkerer's form at you is a swap offer one time in this many, when it has one

aim_of :: proc(g: ^Game, e: int) -> Aim {
	if e < 0 || e >= g.empire_count {
		return .None
	}
	return g.empires[e].aim
}

// Deals the rivals their aims, each a different one.
deal_aims :: proc(g: ^Game) {
	deck: [len(Aim) - 1]Aim
	for i in 0 ..< len(deck) {
		deck[i] = Aim(i + 1)
	}
	for i := len(deck) - 1; i > 0; i -= 1 {
		j := rng_int(&g.rng, i + 1)
		deck[i], deck[j] = deck[j], deck[i]
	}
	g.empires[PLAYER].aim = .None
	for e in 1 ..< g.empire_count {
		g.empires[e].aim = deck[(e - 1) % len(deck)]
	}
}

// Moves up to `n` slider points from one chore to another; returns how many it moved.
shift_points :: proc(from, to: ^int, n: int) -> int {
	k := clamp(n, 0, from^)
	from^ -= k
	to^ += k
	return k
}

// The aim's lean on a colony's sliders (after ai_sliders' rules of thumb). Points come out of Home
// Improvement, or out of Book Club once the factories are full.
aim_sliders :: proc(g: ^Game, c: ^Colony, threat: bool) {
	s := &c.slider
	take :: proc(s: ^[Chore]int, to: Chore, n: int) {
		left := n - shift_points(&s[.Home_Improvement], &s[to], n)
		if to != .Book_Club {
			shift_points(&s[.Book_Club], &s[to], left)
		}
	}
	#partial switch aim_of(g, c.owner) {
	case .Builder:
		if c.factories < factory_cap(c) {
			shift_points(&s[.Book_Club], &s[.Home_Improvement], AIM_SHIFT)
		}
	case .Bully:
		if !threat {
			take(s, .Parking, AIM_SHIFT)
		}
	case .Committee:
		take(s, .Lawn_Care, COMMITTEE_CARE)
	case .Tinkerer:
		take(s, .Book_Club, TINKERER_BOOKS)
	}
}

// Moving Vans the empire wants on the go at once.
vans_wanted :: proc(g: ^Game, e: int) -> int {
	return aim_of(g, e) == .Builder ? BUILDER_VANS : 1
}

// Whether the empire starts fights with other empires this turn: a Builder not while it can still settle.
goes_to_war :: proc(g: ^Game, e: int, can_settle: bool) -> bool {
	return !(aim_of(g, e) == .Builder && can_settle)
}

attack_percent :: proc(g: ^Game, e: int) -> int {
	return aim_of(g, e) == .Bully ? BULLY_ATTACK_PERCENT : ATTACK_PERCENT
}

// The weakest empire `e` has met and that is still standing, or NO_OWNER.
weakest_met :: proc(g: ^Game, e: int) -> int {
	w := NO_OWNER
	for o in 0 ..< g.empire_count {
		if o == e || g.empires[o].out || !g.empires[e].met[o] {
			continue
		}
		if w == NO_OWNER || empire_strength(g, o) < empire_strength(g, w) {
			w = o
		}
	}
	return w
}

// How keen `holder` is to go after what it saw: its grudge, and for a Bully, more for the weakest.
target_score :: proc(g: ^Game, holder: int, in_: Intel, weakest: int) -> int {
	gr := grudge_at(g, holder, in_)
	if aim_of(g, holder) == .Bully && in_.owner >= 0 && in_.owner == weakest {
		gr += BULLY_WEAK_BONUS
	}
	if in_.owner >= 0 && nearly_finished(g, in_.owner) {
		gr += FINISH_BONUS // slice 3 step 7: everyone closes in on an empire down to its last colonies
	}
	return gr
}

// What the aim adds to a pact's value.
aim_pact_value :: proc(g: ^Game, holder: int) -> int {
	return aim_of(g, holder) == .Committee ? COMMITTEE_PACT : 0
}

// A Busybody in the room brings the complaint, if one is not the accused.
busybody_complainer :: proc(g: ^Game, accused: int) -> int {
	for e in 0 ..< g.empire_count {
		if e != accused && alive_empire(g, e) && aim_of(g, e) == .Busybody {
			return e
		}
	}
	return NO_OWNER
}

BUSYBODY_GRIPES := [?]string {
	"the hedges are a disgrace.",
	"someone has been putting the bins out on the wrong day.",
	"a garden gnome was seen making a rude gesture.",
	"the wind chimes go all night.",
}

// At each meeting every Busybody complains about whoever it hates most.
busybody_complaints :: proc(g: ^Game) {
	for e in 1 ..< g.empire_count {
		if !alive_empire(g, e) || aim_of(g, e) != .Busybody {
			continue
		}
		t := NO_OWNER
		for o in 0 ..< g.empire_count {
			if o != e && alive_empire(g, o) && g.empires[e].met[o] && (t == NO_OWNER || g.empires[e].grudge[o] > g.empires[e].grudge[t]) {
				t = o
			}
		}
		if t != NO_OWNER {
			complain(g, t, BUSYBODY_GRIPES[rng_int(&g.rng, len(BUSYBODY_GRIPES))])
		}
	}
}
