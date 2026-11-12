package game

// Diplomacy by filed forms (slice 2 step 2). You fill in a form for a rival you have met and it is
// filed; the answer comes back in the news a turn or two later. Forms: a non-aggression pact, tribute
// (the BJ goes in with the form), a threat (pay up, or else) and a declaration of war, which needs no
// answer and tears up the pact. A rival signs only when what it gains outweighs its grudge (grudges.odin).
// The rivals file forms at you too: they land on yer doormat after the turn's battles and meetings, to
// sign or refuse. With a pact, neither side's ships fight the other's and neither lands Carpools.
// Alliances, trade and research swaps are step 3. Numbers are Claude's (PLAN.md).

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

Treaty :: enum u8 {
	None, // everybody hates everybody
	Pact, // non-aggression
}

Form_Kind :: enum u8 {
	Pact,
	Tribute,
	Threat,
	War,
}

Form :: struct {
	used:   bool,
	kind:   Form_Kind,
	from:   int,
	to:     int,
	amount: int, // BJ, for tribute and threats
	filed:  int, // the turn it was filed
	due:    int, // the turn the answer comes
}

// A rival's form on yer doormat.
Doormat_Kind :: enum u8 {
	Demand, // pay up, or else
	Pact_Offer,
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
}

FORM_NAMES := [Form_Kind]string {
	.Pact    = "a non-aggression pact",
	.Tribute = "tribute",
	.Threat  = "a threat",
	.War     = "a declaration of war",
}

treaty_of :: proc(g: ^Game, a, b: int) -> Treaty {
	if a < 0 || b < 0 || a == b {
		return .None
	}
	return g.treaty[a][b]
}

has_pact :: proc(g: ^Game, a, b: int) -> bool {
	return treaty_of(g, a, b) == .Pact
}

set_treaty :: proc(g: ^Game, a, b: int, t: Treaty) {
	g.treaty[a][b] = t
	g.treaty[b][a] = t
	g.treaty_since[a][b] = g.turn
	g.treaty_since[b][a] = g.turn
	if t == .Pact {
		g.pacts += 1
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

// Tribute pays a grudge down, but never more than a little below where it started.
pay_off_grudge :: proc(g: ^Game, holder, against, bj: int) {
	gr := &g.empires[holder].grudge[against]
	lowest := max(0, grudge_floor(g, against) - TRIBUTE_BELOW_FLOOR)
	if gr^ > lowest {
		gr^ = max(lowest, gr^ - bj / TRIBUTE_PER_GRUDGE)
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
form_problem :: proc(g: ^Game, from, to: int, kind: Form_Kind, amount: int) -> string {
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
	case .War:
		if !has_pact(g, from, to) {
			return "No pact to tear up. You are already at odds."
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
file_form :: proc(g: ^Game, from, to: int, kind: Form_Kind, amount: int) -> string {
	if p := form_problem(g, from, to, kind, amount); p != "" {
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
		due := g.turn + (kind == .Threat ? THREAT_ANSWER_TURNS : PACT_ANSWER_TURNS)
		f = {true, kind, from, to, amount, g.turn, due}
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
	had := has_pact(g, from, to)
	set_treaty(g, from, to, .None)
	if had {
		add_grudge(g, to, from, GRUDGE_BROKEN_PACT)
	}
	if from != PLAYER && to != PLAYER {
		return
	}
	b: Text
	if from == PLAYER {
		add(&b, "You tear up the pact with the ")
		add(&b, empire_name(g, to))
		add(&b, ". They saw that coming. They are still cross.")
	} else {
		add(&b, "The ")
		add(&b, empire_name(g, from))
		add(&b, " have torn up their pact with you, in writing, in triplicate.")
	}
	say(g, text(&b))
}

// At the end of a turn: answers come back, and the rivals break pacts and file forms of their own.
forms_turn :: proc(g: ^Game) {
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
	}
	say(g, text(&b))
}

// How a computer would answer yer doormat (for the simulator): sign pacts; pay demands only to someone
// twice as strong.
ai_doormat_sign :: proc(g: ^Game) -> bool {
	d := &g.doormat
	if d.kind == .Pact_Offer {
		return true
	}
	return empire_strength(g, d.from) >= 2 * max(1, empire_strength(g, PLAYER))
}

// ---- The forms desk: To, the pact or war, tribute, a threat, Back ----

DESK_TO_ROW :: 0
DESK_PACT_ROW :: 1
DESK_TRIBUTE_ROW :: 2
DESK_THREAT_ROW :: 3
DESK_BACK_ROW :: 4
DESK_ROWS :: 5

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
	g.row = DESK_PACT_ROW
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
}

desk_change :: proc(g: ^Game, dir: int) {
	switch g.row {
	case DESK_TO_ROW:
		cycle_rival(g, dir)
	case DESK_TRIBUTE_ROW:
		g.desk.tribute = max(FORM_AMOUNT_STEP, g.desk.tribute + dir * FORM_AMOUNT_STEP)
	case DESK_THREAT_ROW:
		g.desk.threat = max(FORM_AMOUNT_STEP, g.desk.threat + dir * FORM_AMOUNT_STEP)
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
	case DESK_PACT_ROW:
		problem = file_form(g, PLAYER, r, has_pact(g, PLAYER, r) ? .War : .Pact, 0)
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
