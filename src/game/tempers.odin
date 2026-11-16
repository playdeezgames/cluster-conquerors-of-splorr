package game

// Tempers (slice 3 step 4): every rival is dealt one, different from the others', when the cluster is
// laid out. It steers its grudges and its forms. You learn it when you first meet that rival, and the
// forms desk shows it. Yer own empire has none. Numbers are Claude's (PLAN.md).
//   Petty: grudges grow half as much again, and cool half as fast (a point every other turn).
//   Pushy: files a form at you twice as often, and demands tribute whenever it is at least as strong.
//   Two-faced: values any pact more, and tears one up sooner (a lower grudge, or half as strong again).
//   Neighbourly: grudges cool twice as fast, and it values pacts and trade more.
//   Touchy: a complaint upheld against it, or a watcher of the others' caught, counts double.

Temper :: enum u8 {
	None, // yers
	Petty,
	Pushy,
	Two_Faced,
	Neighbourly,
	Touchy,
}

Temper_Info :: struct {
	name: string,
	says: string, // what it means, after "Temper: <name>. " (the line fits the desk's 58 columns)
}

TEMPERS := [Temper]Temper_Info {
	.None        = {"none", ""},
	.Petty       = {"Petty", "Their grudges grow faster and last longer."},
	.Pushy       = {"Pushy", "They demand tribute of anyone not stronger."},
	.Two_Faced   = {"Two-faced", "Signs pacts gladly, and breaks them."},
	.Neighbourly = {"Neighbourly", "Forgiving; keen on pacts and trade."},
	.Touchy      = {"Touchy", "Twice as cross at complaints and watchers."},
}

PETTY_GROWS :: 150 // percent of every grudge added
NEIGHBOURLY_COOL :: 2 // a turn
TWO_FACED_PACT :: 20 // more value in any pact
NEIGHBOURLY_DEAL :: 15 // more value in a pact, an alliance, trade or a swap
TWO_FACED_BREAK :: 65 // the grudge it tears a pact up at (80 for the others)
TWO_FACED_STRONGER :: 150 // or this share of the other's strength (200 for the others)
PUSHY_FORM_IN :: 5 // files a form at you one turn in this many (10 for the others)
PUSHY_DEMANDS :: 100 // demands with this share of yer strength (150 for the others)
TOUCHY_COMPLAINT :: 10 // its grudge against whoever complained, for a complaint upheld against it

temper_of :: proc(g: ^Game, e: int) -> Temper {
	if e < 0 || e >= g.empire_count {
		return .None
	}
	return g.empires[e].temper
}

// Deals the rivals their tempers, each a different one (five tempers, five rivals at most).
deal_tempers :: proc(g: ^Game) {
	deck: [len(Temper) - 1]Temper
	for i in 0 ..< len(deck) {
		deck[i] = Temper(i + 1)
	}
	for i := len(deck) - 1; i > 0; i -= 1 {
		j := rng_int(&g.rng, i + 1)
		deck[i], deck[j] = deck[j], deck[i]
	}
	g.empires[PLAYER].temper = .None
	for e in 1 ..< g.empire_count {
		g.empires[e].temper = deck[(e - 1) % len(deck)]
	}
}

// A grudge about to be added, as `holder`'s temper takes it.
tempered_grudge :: proc(g: ^Game, holder, amount: int) -> int {
	if amount > 0 && temper_of(g, holder) == .Petty {
		return amount * PETTY_GROWS / 100
	}
	return amount
}

// Twice the grudge for a Touchy empire (complaints, caught watchers), else as it is.
touchy :: proc(g: ^Game, holder, amount: int) -> int {
	return temper_of(g, holder) == .Touchy ? 2 * amount : amount
}

// How far `holder`'s grudges cool this turn.
grudge_cooling :: proc(g: ^Game, holder: int) -> int {
	#partial switch temper_of(g, holder) {
	case .Petty:
		return g.turn % 2 == 0 ? GRUDGE_COOL : 0
	case .Neighbourly:
		return NEIGHBOURLY_COOL
	}
	return GRUDGE_COOL
}

// What the temper adds to a pact's (or an alliance's) value.
temper_pact_value :: proc(g: ^Game, holder: int) -> int {
	#partial switch temper_of(g, holder) {
	case .Two_Faced:
		return TWO_FACED_PACT
	case .Neighbourly:
		return NEIGHBOURLY_DEAL
	}
	return 0
}

// Whether `e` tears up its pact with `other` this turn.
breaks_pact :: proc(g: ^Game, e, other: int) -> bool {
	at, stronger := PACT_BREAK_GRUDGE, 200
	if temper_of(g, e) == .Two_Faced {
		at, stronger = TWO_FACED_BREAK, TWO_FACED_STRONGER
	}
	gr := g.empires[e].grudge[other]
	return gr >= at || (gr >= grudge_floor(g, other) && empire_strength(g, e) * 100 >= stronger * max(1, empire_strength(g, other)))
}

// The news when you first meet a rival: its temper.
temper_news :: proc(g: ^Game, e: int) {
	t := temper_of(g, e)
	if t == .None {
		return
	}
	b: Text
	add(&b, "The ")
	add(&b, empire_name(g, e))
	add(&b, " are ")
	add(&b, TEMPERS[t].name)
	add(&b, ". ")
	add(&b, TEMPERS[t].says)
	say(g, text(&b))
}
