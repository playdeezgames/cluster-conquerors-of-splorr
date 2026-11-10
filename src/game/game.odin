package game

// The rules, independent of the platform. Slice 1 step 1 (PLAN.md): a generated cluster to look at,
// with a cursor that goes from star to star. Fleets, colonies and the rest arrive in later steps.

// Commands the page sends for keys, gamepad buttons and the touch pads (keep in step with
// web/index.html). Directions move the cursor to the next star that way.
Command :: enum i32 {
	North,
	South,
	West,
	East,
	North_West,
	North_East,
	South_West,
	South_East,
	Confirm,
	Cancel,
	End_Turn,
}

DIRECTION := [Command][2]int {
	.North      = {0, -1},
	.South      = {0, 1},
	.West       = {-1, 0},
	.East       = {1, 0},
	.North_West = {-1, -1},
	.North_East = {1, -1},
	.South_West = {-1, 1},
	.South_East = {1, 1},
	.Confirm    = {0, 0},
	.Cancel     = {0, 0},
	.End_Turn   = {0, 0},
}

// How a click or tap reached the game (the page sends these numbers).
Pointer :: enum i32 {
	Mouse,
	Right_Mouse,
	Touch,
}

Game :: struct {
	seed:       u64,
	stars:      [MAX_STARS]Star,
	star_count: int,
	home:       int,
	cursor:     int, // the star under the cursor; the panel shows it
	turn:       int,
	news:       [NEWS_LINES]Message, // oldest first
}

init_game :: proc(g: ^Game, seed: u64) {
	g^ = {}
	g.seed = seed
	make_cluster(g, seed)
	g.cursor = g.home
	g.turn = 1
	b: Text
	add(&b, "Welcome to ")
	add(&b, g.stars[g.home].name)
	add(&b, ". The Homeowners' Association has been notified.")
	say(g, text(&b))
	say(g, "(Slice 1, step 1: arrows or d-pad go star to star; a click or tap picks one.)")
}

command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North, .South, .West, .East, .North_West, .North_East, .South_West, .South_East:
		d := DIRECTION[c]
		next := star_toward(g, g.cursor, d.x, d.y)
		if next != NO_STAR {
			g.cursor = next
		}
	case .Confirm:
		b: Text
		describe_star(g, g.cursor, &b)
		say(g, text(&b))
	case .Cancel:
		g.cursor = g.home
		say(g, "Back to yer home star.")
	case .End_Turn:
		g.turn += 1
		b: Text
		add(&b, "Turn ")
		add_int(&b, g.turn)
		add(&b, ". The HOA has not met yet.")
		say(g, text(&b))
	}
}

// "Pollux (Lot 8): yer home, a Medium Terran world." and the like.
describe_star :: proc(g: ^Game, i: int, b: ^Text) {
	s := &g.stars[i]
	add(b, s.name)
	add(b, " (Lot ")
	add_int(b, i + 1)
	add(b, ")")
	if !s.known {
		add(b, ": not surveyed.")
		return
	}
	add(b, i == g.home ? ": yer home, a " : ": a ")
	if s.special != .None {
		add(b, SPECIAL_NAMES[s.special])
		add(b, ", ")
	}
	add(b, SIZE_NAMES[s.size])
	add(b, " ")
	add(b, PLANET_NAMES[s.planet])
	add(b, " world.")
}

// The map cell under a screen pixel, if the pixel is on the map view.
screen_to_cell :: proc(g: ^Game, sx, sy: int) -> (x, y: int, ok: bool) {
	if sx < MAP_X || sy < MAP_Y || sx >= MAP_X + VIEW_W * TILE || sy >= MAP_Y + VIEW_H * TILE {
		return 0, 0, false
	}
	ox, oy := view_origin(g)
	return ox + (sx - MAP_X) / TILE, oy + (sy - MAP_Y) / TILE, true
}

// Top-left map cell of the view: the cursor's star in the middle, held inside the galaxy.
view_origin :: proc(g: ^Game) -> (x, y: int) {
	s := g.stars[g.cursor]
	return clamp(s.x - VIEW_W / 2, 0, GALAXY_W - VIEW_W), clamp(s.y - VIEW_H / 2, 0, GALAXY_H - VIEW_H)
}

// A click or tap at a screen pixel. On or next to a star (one cell's slack, for fingers), it moves
// the cursor there and names the star; on empty space it says so.
pointer :: proc(g: ^Game, sx, sy: int, p: Pointer) {
	x, y, ok := screen_to_cell(g, sx, sy)
	if !ok {
		return
	}
	i := star_near(g, x, y, 1)
	if i == NO_STAR {
		say(g, "Empty space. Nobody owns it yet.")
		return
	}
	g.cursor = i
	b: Text
	describe_star(g, i, &b)
	say(g, text(&b))
}

// ---- Messages and text without core:fmt ----

LOG_CAP :: 96 // characters per remembered message

Message :: struct {
	text: [LOG_CAP]u8,
	n:    int,
}

// Adds a line to the news ticker, cut to its width.
say :: proc(g: ^Game, s: string) {
	for i in 0 ..< NEWS_LINES - 1 {
		g.news[i] = g.news[i + 1]
	}
	m := &g.news[NEWS_LINES - 1]
	m^ = {}
	m.n = min(len(s), LOG_CAP, NEWS_COLS)
	copy(m.text[:m.n], s[:m.n])
}

message :: proc(m: ^Message) -> string {
	return string(m.text[:m.n])
}

Text :: struct {
	buf: [LOG_CAP]u8,
	n:   int,
}

add :: proc(b: ^Text, s: string) {
	for i in 0 ..< len(s) {
		if b.n < LOG_CAP {
			b.buf[b.n] = s[i]
			b.n += 1
		}
	}
}

add_int :: proc(b: ^Text, v: int) {
	digits: [24]u8
	n := 0
	x := v < 0 ? -v : v
	for {
		digits[n] = u8('0' + x % 10)
		n += 1
		x /= 10
		if x == 0 {
			break
		}
	}
	if v < 0 {
		add(b, "-")
	}
	for i := n - 1; i >= 0; i -= 1 {
		add(b, string(digits[i:i + 1]))
	}
}

text :: proc(b: ^Text) -> string {
	return string(b.buf[:b.n])
}
