package game

// Diplomacy by filed forms (slice 2 step 2). You fill in a form for a rival you have met and it is
// filed; the answer comes back in the news a turn or two later. Forms: a non-aggression pact, tribute
// (the BJ goes in with the form), a threat (pay up, or else) and a declaration of war, which needs no
// answer and tears up the pact. A rival signs only when what it gains outweighs its grudge (grudges.odin).
// The rivals file forms at you too: they land on yer doormat after the turn's battles and meetings, to
// sign or refuse. With a pact, neither side's ships fight the other's and neither lands Carpools.
// Step 3 added an alliance (a pact first; then each refuels at the other's colonies and they share
// sight), a trade agreement (each gets a growing share of the other's BJ income), a research swap (one
// tech for one tech) and tribute in a tech. Numbers are Claude's (PLAN.md).

MAX_FORMS :: 8
PACT_ANSWER_TURNS :: 1 // a pact or tribute is answered next turn
THREAT_ANSWER_TURNS :: 2 // a threat takes longer to read
PACT_VALUE :: 20 // what any pact is worth to a rival, before the grudge
PACT_VALUE_WEAKER :: 30 // more if the other side is the stronger
PACT_VALUE_BUSY :: 20 // more if it hates the third empire at least this much:
PACT_BUSY_GRUDGE :: 60
PACT_BREAK_GRUDGE :: 80 // a rival tears up a pact at this grudge, or when it is twice as strong
TRIBUTE_PER_GRUDGE :: 2 // BJ of tribute per point of grudge paid off
TRIBUTE_BELOW_FLOOR :: 20 // tribute can take a grudge this far below where it started, and no further
THREAT_PERCENT :: 200 // a threat works when the threatener has at least this share of the other's strength
GRUDGE_THREAT :: 15 // a threat, whether it works or not
GRUDGE_BROKEN_PACT :: 30 // a pact torn up, to the other side
GRUDGE_REFUSED_PACT :: 5 // a pact offer refused
RIVAL_FORM_IN :: 10 // each turn, a rival who has met you files a form one time in this many
DEMAND_PERCENT :: 150 // a rival demands tribute when it has this share of yer strength
FORM_AMOUNT_STEP :: 10
ALLIANCE_VALUE_OFF :: 10 // an alliance is worth this much less to a rival than a pact
TRADE_VALUE :: 30 // what a trade agreement is worth to a rival
TREATY_BONUS :: 20 // more for trade or a swap with someone it already has a pact with
SWAP_VALUE :: 30 // what a research swap is worth to a rival
TECH_TRIBUTE_GRUDGE :: 15 // a tech given as tribute pays this much grudge off
TRADE_START :: 5 // percent of the other's BJ income, the first turn of a trade agreement
TRADE_MAX :: 15 // and it grows a point a turn to this
NO_TECH :: -1

Treaty :: enum u8 {
	None, // everybody hates everybody
	Pact, // non-aggression
	Alliance, // a pact, plus refuelling at each other's colonies and shared sight
}

Form_Kind :: enum u8 {
	Pact,
	Tribute,
	Threat,
	War,
	Alliance,
	Trade,
	Gift, // tribute in a tech
	Swap, // one tech for one tech
}

Form :: struct {
	used:   bool,
	kind:   Form_Kind,
	from:   int,
	to:     int,
	amount: int, // BJ, for tribute and threats
	tech:   int, // the tech given, for a gift or a swap (tech_id), else NO_TECH
	filed:  int, // the turn it was filed
	due:    int, // the turn the answer comes
}

// A rival's form on yer doormat.
Doormat_Kind :: enum u8 {
	Demand, // pay up, or else
	Pact_Offer,
	Trade_Offer,
}

Doormat :: struct {
	waiting: bool, // filed, to show once the turn's battles and meetings are done
	open:    bool, // on screen
	kind:    Doormat_Kind,
	from:    int,
	amount:  int,
	choice:  int, // 0 sign, 1 refuse
}

// The forms desk on screen: the rival it is open at and the amounts in the blanks.
Desk :: struct {
	rival:   int,
	tribute: int,
	threat:  int,
	gift:    int, // the tech on the gift row (tech_id)
	swap:    int, // the tech on the swap row
}

FORM_NAMES := [Form_Kind]string {
	.Pact     = "a non-aggression pact",
	.Tribute  = "tribute",
	.Threat   = "a threat",
	.War      = "a declaration of war",
	.Alliance = "an alliance",
	.Trade    = "a trade agreement",
	.Gift     = "tribute in a tech",
	.Swap     = "a research swap",
}

// The short names the post list uses.
POST_NAMES := [Form_Kind]string {
	.Pact     = "pact",
	.Tribute  = "tribute",
	.Threat   = "threat",
	.War      = "war",
	.Alliance = "alliance",
	.Trade    = "trade",
	.Gift     = "gift",
	.Swap     = "swap",
}

// A tech as one number: its field and its place in the field.
tech_id :: proc(f: Field, i: int) -> int {
	return int(f) * TECHS_PER_FIELD + i
}

tech_of :: proc(id: int) -> (f: Field, i: int) {
	return Field(id / TECHS_PER_FIELD), id % TECHS_PER_FIELD
}

knows :: proc(g: ^Game, owner, id: int) -> bool {
	f, i := tech_of(id)
	return g.empires[owner].tech.known[f][i]
}

// The techs `from` knows and `to` does not, cheapest first in each field.
giveable :: proc(g: ^Game, from, to: int) -> (list: [len(Field) * TECHS_PER_FIELD]int, n: int) {
	for f in Field {
		for i in 0 ..< TECHS_PER_FIELD {
			id := tech_id(f, i)
			if knows(g, from, id) && !knows(g, to, id) {
				list[n] = id
				n += 1
			}
		}
	}
	return
}

tech_name :: proc(id: int) -> string {
	if id < 0 {
		return "nothing"
	}
	f, i := tech_of(id)
	return TECHS[f][i].name
}

treaty_of :: proc(g: ^Game, a, b: int) -> Treaty {
	if a < 0 || b < 0 || a == b {
		return .None
	}
	return g.treaty[a][b]
}

// A pact or an alliance: no fighting, no landing.
has_pact :: proc(g: ^Game, a, b: int) -> bool {
	return treaty_of(g, a, b) >= .Pact
}

allied :: proc(g: ^Game, a, b: int) -> bool {
	return treaty_of(g, a, b) == .Alliance
}

trading :: proc(g: ^Game, a, b: int) -> bool {
	return a >= 0 && b >= 0 && a != b && g.trade[a][b] > 0
}

set_treaty :: proc(g: ^Game, a, b: int, t: Treaty) {
	g.treaty[a][b] = t
	g.treaty[b][a] = t
	g.treaty_since[a][b] = g.turn
	g.treaty_since[b][a] = g.turn
	if t == .Pact {
		g.pacts += 1
	}
	if t == .Alliance {
		g.alliances += 1
	}
}

// What an empire can fight with: its warships' hits and its bases'. The HOA keeps a register, so
// everyone knows everyone's.
empire_strength :: proc(g: ^Game, e: int) -> int {
	n := 0
	for &f in g.fleets {
		if f.used && f.owner == e {
			n += warship_hits(&f)
		}
	}
	for i in 0 ..< g.star_count {
		if c := colony_of(g, i, e); c != nil {
			n += c.bases * BASE_COMBAT.hp
		}
	}
	return n
}

// The third empire, if there is one.
third_of :: proc(g: ^Game, a, b: int) -> int {
	for e in 0 ..< g.empire_count {
		if e != a && e != b && !g.empires[e].out {
			return e
		}
	}
	return NO_OWNER
}

// What a pact with `other` is worth to `holder`; it signs when this beats its grudge.
pact_value :: proc(g: ^Game, holder, other: int) -> int {
	v := PACT_VALUE
	if empire_strength(g, other) > empire_strength(g, holder) {
		v += PACT_VALUE_WEAKER
	}
	if t := third_of(g, holder, other); t != NO_OWNER && g.empires[holder].grudge[t] >= PACT_BUSY_GRUDGE {
		v += PACT_VALUE_BUSY
	}
	return v
}

// What a trade agreement or a swap is worth to `holder`.
deal_value :: proc(g: ^Game, holder, other: int, kind: Form_Kind) -> int {
	v := kind == .Trade ? TRADE_VALUE : SWAP_VALUE
	if has_pact(g, holder, other) {
		v += TREATY_BONUS
	}
	return v
}

// The BJ an empire takes in tax a turn.
income_of :: proc(g: ^Game, e: int) -> int {
	n := 0
	for i in 0 ..< g.star_count {
		if colony_of(g, i, e) != nil {
			n += tax(g, i)
		}
	}
	return n
}

// Each turn: every trade agreement pays both sides a share of the other's income, and the share grows.
trade_turn :: proc(g: ^Game) {
	income: [MAX_EMPIRES]int
	for e in 0 ..< g.empire_count {
		income[e] = income_of(g, e)
	}
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if !trading(g, a, b) {
				continue
			}
			got := income[b] * g.trade[a][b] / 100
			if g.empires[a].race == .Dogs {
				got = got * 3 / 2
			}
			g.empires[a].bj += got
		}
	}
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if trading(g, a, b) {
				g.trade[a][b] = min(TRADE_MAX, g.trade[a][b] + 1)
			}
		}
	}
}

// What `to` gives back in a swap: its cheapest tech `from` lacks.
swap_back :: proc(g: ^Game, from, to: int) -> int {
	list, n := giveable(g, to, from)
	return n > 0 ? list[0] : NO_TECH
}

// Tribute pays a grudge down, but never more than a little below where it started.
pay_off_grudge :: proc(g: ^Game, holder, against, bj: int) {
	lower_grudge(g, holder, against, bj / TRIBUTE_PER_GRUDGE)
}

lower_grudge :: proc(g: ^Game, holder, against, points: int) {
	gr := &g.empires[holder].grudge[against]
	lowest := max(0, grudge_floor(g, against) - TRIBUTE_BELOW_FLOOR)
	if gr^ > lowest {
		gr^ = max(lowest, gr^ - points)
	}
}

pending_form :: proc(g: ^Game, from, to: int, kind: Form_Kind) -> bool {
	for &f in g.forms {
		if f.used && f.from == from && f.to == to && f.kind == kind {
			return true
		}
	}
	return false
}

// Why a form cannot be filed, or "".
form_problem :: proc(g: ^Game, from, to: int, kind: Form_Kind, amount: int, tech := NO_TECH) -> string {
	if to < 0 || to >= g.empire_count || to == from || g.empires[to].out {
		return "Nobody there to write to."
	}
	if !g.empires[from].met[to] {
		return "You have not met them. Nobody knows the address."
	}
	switch kind {
	case .Pact:
		if has_pact(g, from, to) {
			return "There is already a pact. They have it framed."
		}
	case .Alliance:
		if allied(g, from, to) {
			return "You are already allies. Nobody is happy about it."
		}
		if !has_pact(g, from, to) {
			return "An alliance needs a pact first."
		}
	case .Trade:
		if trading(g, from, to) {
			return "There is already a trade agreement."
		}
	case .Gift:
		if tech < 0 || !knows(g, from, tech) || knows(g, to, tech) {
			return "No tech they lack to give."
		}
	case .Swap:
		if tech < 0 || !knows(g, from, tech) || knows(g, to, tech) {
			return "No tech they lack to offer."
		}
		if swap_back(g, from, to) == NO_TECH {
			return "They know nothing you do not. Nothing to swap for."
		}
	case .War:
		if !has_pact(g, from, to) && !trading(g, from, to) {
			return "Nothing to tear up. You are already at odds."
		}
	case .Tribute:
		if amount <= 0 || amount > g.empires[from].bj {
			return "Not enough BJ to enclose."
		}
	case .Threat:
		if amount <= 0 {
			return "A threat needs a figure."
		}
	}
	if kind != .War && pending_form(g, from, to, kind) {
		return "One of those is already in the post."
	}
	return ""
}

// Files a form; war takes effect at once, the rest are answered later. Returns why not, or "".
file_form :: proc(g: ^Game, from, to: int, kind: Form_Kind, amount: int, tech := NO_TECH) -> string {
	if p := form_problem(g, from, to, kind, amount, tech); p != "" {
		return p
	}
	if kind == .War {
		declare_war(g, from, to)
		return ""
	}
	for &f in g.forms {
		if f.used {
			continue
		}
		due := g.turn + (kind == .Threat || kind == .Swap ? THREAT_ANSWER_TURNS : PACT_ANSWER_TURNS)
		f = {true, kind, from, to, amount, tech, g.turn, due}
		if kind == .Tribute {
			g.empires[from].bj -= amount // enclosed
		}
		if from == PLAYER {
			b: Text
			add(&b, "Filed: ")
			add(&b, FORM_NAMES[kind])
			add(&b, ", to the ")
			add(&b, empire_name(g, to))
			add(&b, ". Answer due turn ")
			add_int(&b, due)
			add(&b, ".")
			say(g, text(&b))
		}
		return ""
	}
	return "The out tray is full. Wait for some answers."
}

declare_war :: proc(g: ^Game, from, to: int) {
	had := has_pact(g, from, to) || trading(g, from, to)
	set_treaty(g, from, to, .None)
	g.trade[from][to] = 0
	g.trade[to][from] = 0
	if had {
		add_grudge(g, to, from, GRUDGE_BROKEN_PACT)
	}
	if from != PLAYER && to != PLAYER {
		return
	}
	b: Text
	if from == PLAYER {
		add(&b, "You tear up everything with the ")
		add(&b, empire_name(g, to))
		add(&b, ". They saw that coming.")
	} else {
		add(&b, "The ")
		add(&b, empire_name(g, from))
		add(&b, " have torn up everything with you, in triplicate.")
	}
	say(g, text(&b))
}

// At the end of a turn: answers come back, and the rivals break pacts and file forms of their own.
forms_turn :: proc(g: ^Game) {
	trade_turn(g)
	for &f in g.forms {
		if f.used && f.due <= g.turn {
			answer_form(g, f)
			f = {}
		}
	}
	for e in 1 ..< g.empire_count {
		if g.empires[e].out {
			continue
		}
		for other in 0 ..< g.empire_count {
			if !has_pact(g, e, other) {
				continue
			}
			if g.empires[e].grudge[other] >= PACT_BREAK_GRUDGE || (g.empires[e].grudge[other] >= grudge_floor(g, other) && empire_strength(g, e) >= 2 * max(1, empire_strength(g, other))) {
				declare_war(g, e, other)
			}
		}
		rival_files(g, e)
	}
}

// A rival answers a form from someone else.
answer_form :: proc(g: ^Game, f: Form) {
	to, from := f.to, f.from
	if g.empires[to].out || g.empires[from].out {
		return
	}
	b: Text
	add(&b, "The ")
	add(&b, empire_name(g, to))
	switch f.kind {
	case .Pact:
		if !has_pact(g, from, to) && pact_value(g, to, from) > g.empires[to].grudge[from] {
			set_treaty(g, from, to, .Pact)
			add(&b, " have signed the non-aggression pact. Their fleets will look the other way.")
		} else {
			add_grudge(g, to, from, GRUDGE_REFUSED_PACT)
			add(&b, " sent the pact back unsigned. There is a coffee ring on it.")
		}
	case .Tribute:
		g.empires[to].bj += f.amount
		pay_off_grudge(g, to, from, f.amount)
		add(&b, " have cashed yer cheque for ")
		add_int(&b, f.amount)
		add(&b, " BJ. They seem marginally less cross.")
	case .Threat:
		add_grudge(g, to, from, GRUDGE_THREAT)
		if empire_strength(g, from) * 100 >= THREAT_PERCENT * max(1, empire_strength(g, to)) {
			paid := min(f.amount, max(0, g.empires[to].bj))
			g.empires[to].bj -= paid
			g.empires[from].bj += paid
			add(&b, " paid ")
			add_int(&b, paid)
			add(&b, " BJ. They will remember this.")
		} else {
			add(&b, " have filed yer threat under Ha.")
		}
	case .Alliance:
		if has_pact(g, from, to) && !allied(g, from, to) && pact_value(g, to, from) - ALLIANCE_VALUE_OFF > g.empires[to].grudge[from] {
			set_treaty(g, from, to, .Alliance)
			add(&b, " are now yer allies. Their pumps and their eyes are yers.")
		} else {
			add_grudge(g, to, from, GRUDGE_REFUSED_PACT)
			add(&b, " declined the alliance. They underlined declined.")
		}
	case .Trade:
		if !trading(g, from, to) && deal_value(g, to, from, .Trade) > g.empires[to].grudge[from] {
			g.trade[from][to] = TRADE_START
			g.trade[to][from] = TRADE_START
			g.trades += 1
			add(&b, " signed the trade agreement. Money will change hands.")
		} else {
			add_grudge(g, to, from, GRUDGE_REFUSED_PACT)
			add(&b, " would rather not trade with you. Or anyone.")
		}
	case .Gift:
		f_, i := tech_of(f.tech)
		if !knows(g, to, f.tech) {
			learn(g, to, f_, i, "A gift: ")
		}
		lower_grudge(g, to, from, TECH_TRIBUTE_GRUDGE)
		add(&b, " accepted ")
		add(&b, tech_name(f.tech))
		add(&b, ". They seem marginally less cross.")
	case .Swap:
		back := swap_back(g, from, to)
		if knows(g, to, f.tech) {
			add(&b, " already had ")
			add(&b, tech_name(f.tech))
			add(&b, ". They sent the swap back.")
		} else if back != NO_TECH && !knows(g, to, f.tech) && deal_value(g, to, from, .Swap) > g.empires[to].grudge[from] {
			fa, ia := tech_of(f.tech)
			learn(g, to, fa, ia, "A swap: ")
			fb, ib := tech_of(back)
			learn(g, from, fb, ib, "A swap brings ")
			add(&b, " swapped. You gave ")
			add(&b, tech_name(f.tech))
			add(&b, ".")
		} else {
			add_grudge(g, to, from, GRUDGE_REFUSED_PACT)
			add(&b, " will not swap. They kept the form.")
		}
	case .War:
	}
	if from == PLAYER {
		say(g, text(&b))
	}
}

// Now and then a rival who has met you puts a form through yer door: a demand when it is the stronger,
// a pact when it would rather be left alone.
rival_files :: proc(g: ^Game, e: int) {
	if !g.empires[e].met[PLAYER] || g.empires[PLAYER].out || g.doormat.waiting || g.doormat.open {
		return
	}
	if rng_int(&g.rng, RIVAL_FORM_IN) != 0 {
		return
	}
	mine, yers := empire_strength(g, e), empire_strength(g, PLAYER)
	d := &g.doormat
	switch {
	case !has_pact(g, e, PLAYER) && mine * 100 >= DEMAND_PERCENT * max(1, yers):
		amount := clamp(g.empires[PLAYER].bj / 5 / FORM_AMOUNT_STEP * FORM_AMOUNT_STEP, FORM_AMOUNT_STEP, 200)
		d^ = {waiting = true, kind = .Demand, from = e, amount = amount}
	case !has_pact(g, e, PLAYER) && pact_value(g, e, PLAYER) + GRUDGE_REFUSED_PACT > g.empires[e].grudge[PLAYER]:
		d^ = {waiting = true, kind = .Pact_Offer, from = e}
	case has_pact(g, e, PLAYER) && !trading(g, e, PLAYER) && deal_value(g, e, PLAYER, .Trade) + GRUDGE_REFUSED_PACT > g.empires[e].grudge[PLAYER]:
		d^ = {waiting = true, kind = .Trade_Offer, from = e}
	}
}

// Shows a waiting form once nothing else is on screen.
show_doormat :: proc(g: ^Game) -> bool {
	if !g.doormat.waiting || g.mode != .Map {
		return false
	}
	g.doormat.waiting = false
	g.doormat.open = true
	g.doormat.choice = 0
	g.mode = .Doormat
	return true
}

// Back to the map after a battle or a meeting, showing whatever was waiting.
back_to_map :: proc(g: ^Game) {
	g.mode = .Map
	if show_waiting_meeting(g) {
		return
	}
	show_doormat(g)
}

// Yer answer: sign (0) or refuse (1).
answer_doormat :: proc(g: ^Game, sign: bool) {
	d := &g.doormat
	if !d.open {
		return
	}
	d.open = false
	g.mode = .Map
	e := d.from
	b: Text
	add(&b, "The ")
	add(&b, empire_name(g, e))
	switch d.kind {
	case .Demand:
		if sign {
			paid := min(d.amount, max(0, g.empires[PLAYER].bj))
			g.empires[PLAYER].bj -= paid
			g.empires[e].bj += paid
			pay_off_grudge(g, e, PLAYER, paid)
			add(&b, " got their ")
			add_int(&b, paid)
			add(&b, " BJ. They do not say thank you.")
		} else {
			add_grudge(g, e, PLAYER, GRUDGE_THREAT)
			add(&b, " got their form back with REFUSED stamped on it. They took it personally.")
		}
	case .Pact_Offer:
		if sign && !has_pact(g, e, PLAYER) {
			set_treaty(g, e, PLAYER, .Pact)
			add(&b, " and you now have a non-aggression pact. Neither side believes it.")
		} else {
			add_grudge(g, e, PLAYER, GRUDGE_REFUSED_PACT)
			add(&b, " got their pact back unsigned.")
		}
	case .Trade_Offer:
		if sign && !trading(g, e, PLAYER) {
			g.trade[e][PLAYER] = TRADE_START
			g.trade[PLAYER][e] = TRADE_START
			g.trades += 1
			add(&b, " and you now trade. Money will change hands.")
		} else {
			add_grudge(g, e, PLAYER, GRUDGE_REFUSED_PACT)
			add(&b, " got their trade agreement back unsigned.")
		}
	}
	say(g, text(&b))
}

// How a computer would answer yer doormat (for the simulator): sign pacts; pay demands only to someone
// twice as strong.
ai_doormat_sign :: proc(g: ^Game) -> bool {
	d := &g.doormat
	if d.kind != .Demand {
		return true
	}
	return empire_strength(g, d.from) >= 2 * max(1, empire_strength(g, PLAYER))
}

// ---- The forms desk: To, the pact or war, tribute, a threat, Back ----

DESK_TO_ROW :: 0
DESK_TREATY_ROW :: 1 // a pact, then an alliance
DESK_TRADE_ROW :: 2
DESK_TRIBUTE_ROW :: 3
DESK_GIFT_ROW :: 4
DESK_SWAP_ROW :: 5
DESK_THREAT_ROW :: 6
DESK_WAR_ROW :: 7
DESK_BACK_ROW :: 8
DESK_ROWS :: 9

met_rivals :: proc(g: ^Game) -> (list: [MAX_EMPIRES]int, n: int) {
	for e in 1 ..< g.empire_count {
		if g.empires[PLAYER].met[e] && !g.empires[e].out {
			list[n] = e
			n += 1
		}
	}
	return
}

open_desk :: proc(g: ^Game) {
	g.mode = .Forms
	g.row = DESK_TREATY_ROW
	list, n := met_rivals(g)
	if n == 0 {
		g.row = DESK_BACK_ROW
	} else {
		found := false
		for i in 0 ..< n {
			found = found || list[i] == g.desk.rival
		}
		if !found {
			g.desk.rival = list[0]
		}
	}
	if g.desk.tribute <= 0 {
		g.desk.tribute = 50
	}
	if g.desk.threat <= 0 {
		g.desk.threat = 50
	}
	fix_desk_techs(g)
}

// Keeps the gift and swap rows on techs the rival lacks.
fix_desk_techs :: proc(g: ^Game) {
	list, n := giveable(g, PLAYER, g.desk.rival)
	ok_gift, ok_swap := false, false
	for k in 0 ..< n {
		ok_gift = ok_gift || list[k] == g.desk.gift
		ok_swap = ok_swap || list[k] == g.desk.swap
	}
	if !ok_gift {
		g.desk.gift = n > 0 ? list[0] : NO_TECH
	}
	if !ok_swap {
		g.desk.swap = n > 0 ? list[0] : NO_TECH
	}
}

// The next tech the rival lacks after `id`, one way or the other.
cycle_tech :: proc(g: ^Game, id, dir: int) -> int {
	list, n := giveable(g, PLAYER, g.desk.rival)
	if n == 0 {
		return NO_TECH
	}
	at := 0
	for k in 0 ..< n {
		if list[k] == id {
			at = k
		}
	}
	return list[(at + dir + n) % n]
}

// The next rival you have met, one way or the other.
cycle_rival :: proc(g: ^Game, dir: int) {
	list, n := met_rivals(g)
	if n == 0 {
		return
	}
	at := 0
	for i in 0 ..< n {
		if list[i] == g.desk.rival {
			at = i
		}
	}
	g.desk.rival = list[(at + dir + n) % n]
	fix_desk_techs(g)
}

desk_change :: proc(g: ^Game, dir: int) {
	switch g.row {
	case DESK_TO_ROW:
		cycle_rival(g, dir)
	case DESK_TRIBUTE_ROW:
		g.desk.tribute = max(FORM_AMOUNT_STEP, g.desk.tribute + dir * FORM_AMOUNT_STEP)
	case DESK_THREAT_ROW:
		g.desk.threat = max(FORM_AMOUNT_STEP, g.desk.threat + dir * FORM_AMOUNT_STEP)
	case DESK_GIFT_ROW:
		g.desk.gift = cycle_tech(g, g.desk.gift, dir)
	case DESK_SWAP_ROW:
		g.desk.swap = cycle_tech(g, g.desk.swap, dir)
	}
}

desk_file :: proc(g: ^Game) {
	if g.row == DESK_BACK_ROW {
		g.mode = .Map
		return
	}
	_, n := met_rivals(g)
	if n == 0 {
		return
	}
	r := g.desk.rival
	problem := ""
	switch g.row {
	case DESK_TREATY_ROW:
		problem = file_form(g, PLAYER, r, has_pact(g, PLAYER, r) ? .Alliance : .Pact, 0)
	case DESK_TRADE_ROW:
		problem = file_form(g, PLAYER, r, .Trade, 0)
	case DESK_GIFT_ROW:
		problem = file_form(g, PLAYER, r, .Gift, 0, g.desk.gift)
	case DESK_SWAP_ROW:
		problem = file_form(g, PLAYER, r, .Swap, 0, g.desk.swap)
	case DESK_WAR_ROW:
		problem = file_form(g, PLAYER, r, .War, 0)
	case DESK_TRIBUTE_ROW:
		problem = file_form(g, PLAYER, r, .Tribute, g.desk.tribute)
	case DESK_THREAT_ROW:
		problem = file_form(g, PLAYER, r, .Threat, g.desk.threat)
	case:
		return
	}
	if problem != "" {
		say(g, problem)
	}
	fix_desk_techs(g)
}

// Up and Down pick a row, Left and Right change it, Enter/OK files; Escape/Back (or P) closes.
desk_command :: proc(g: ^Game, c: Command) {
	#partial switch c {
	case .North:
		g.row = (g.row + DESK_ROWS - 1) % DESK_ROWS
	case .South:
		g.row = (g.row + 1) % DESK_ROWS
	case .West, .East:
		desk_change(g, c == .West ? -1 : 1)
	case .Confirm:
		desk_file(g)
	case .Cancel:
		g.mode = .Map
	}
}

// Up and Down pick Sign or Refuse, Enter/OK answers.
doormat_command :: proc(g: ^Game, c: Command) {
	#partial switch c {
	case .North, .South:
		g.doormat.choice = 1 - g.doormat.choice
	case .Confirm:
		answer_doormat(g, g.doormat.choice == 0)
	}
}
