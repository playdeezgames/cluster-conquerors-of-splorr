package game

// The rules, independent of the platform. Step 0 of slice 1 (PLAN.md): a placeholder cluster to prove
// the layout and every input path. The generator, fleets, colonies and the rest arrive in later steps.

// Commands the page sends for keys, gamepad buttons and the touch pads (keep in step with
// web/index.html). Directions move the cursor across the star map.
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

// The star map, in cells. Bigger than the view, so the view scrolls.
GALAXY_W :: 60
GALAXY_H :: 40

MAX_STARS :: 24

Star :: struct {
	x, y:  int,
	name:  string, // straight star name; the HOA's paperwork uses the lot number (index + 1)
	known: bool, // surveyed (step 0: only the home star)
}

NO_STAR :: -1

Game :: struct {
	stars:      [MAX_STARS]Star,
	star_count: int,
	home:       int,
	cx, cy:     int, // cursor cell
	selected:   int, // a star index or NO_STAR
	turn:       int,
	news:       [NEWS_LINES]Message, // oldest first
}

// Placeholder names for step 0; step 1 draws names for a generated cluster.
STAR_NAMES := [MAX_STARS]string {
	"Vega Minor", "Kepler's Rest", "Altair", "Deneb Gate", "Procyon", "Mira",
	"Castor", "Pollux", "Rigel Far", "Achernar", "Hadar", "Acrux",
	"Spica", "Antares Low", "Fomalhaut", "Mimosa", "Regulus", "Adhara",
	"Shaula", "Bellatrix", "Elnath", "Miaplacidus", "Alnilam", "Alnair",
}

init_game :: proc(g: ^Game) {
	g^ = {}
	// A fixed scatter of 20 stars, one per 12 by 10 block, nudged so they do not line up.
	n := 0
	for by in 0 ..< 4 {
		for bx in 0 ..< 5 {
			s := &g.stars[n]
			s.x = bx * 12 + 2 + (bx * 7 + by * 5) % 8
			s.y = by * 10 + 1 + (bx * 3 + by * 7) % 8
			s.name = STAR_NAMES[n]
			n += 1
		}
	}
	g.star_count = n
	g.home = 7
	g.stars[g.home].known = true
	g.cx, g.cy = g.stars[g.home].x, g.stars[g.home].y
	g.selected = g.home
	g.turn = 1
	say(g, "Welcome to the cluster. The Homeowners' Association has been notified.")
	say(g, "(Slice 1, step 0: a placeholder cluster. Move the cursor; Enter/OK selects.)")
}

// The star at a cell, or NO_STAR.
star_at :: proc(g: ^Game, x, y: int) -> int {
	for i in 0 ..< g.star_count {
		if g.stars[i].x == x && g.stars[i].y == y {
			return i
		}
	}
	return NO_STAR
}

command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North, .South, .West, .East, .North_West, .North_East, .South_West, .South_East:
		d := DIRECTION[c]
		g.cx = clamp(g.cx + d.x, 0, GALAXY_W - 1)
		g.cy = clamp(g.cy + d.y, 0, GALAXY_H - 1)
	case .Confirm:
		select_cell(g, g.cx, g.cy)
	case .Cancel:
		g.selected = NO_STAR
		g.cx, g.cy = g.stars[g.home].x, g.stars[g.home].y
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

// Selects whatever is at a cell and says what it is.
select_cell :: proc(g: ^Game, x, y: int) {
	i := star_at(g, x, y)
	g.selected = i
	if i == NO_STAR {
		say(g, "Empty space. Nobody owns it yet.")
		return
	}
	b: Text
	describe_star(g, i, &b)
	say(g, text(&b))
}

// "Vega Minor (Lot 8), yer home." and the like.
describe_star :: proc(g: ^Game, i: int, b: ^Text) {
	s := &g.stars[i]
	add(b, s.known ? s.name : "An unknown star")
	add(b, " (Lot ")
	add_int(b, i + 1)
	add(b, ")")
	if i == g.home {
		add(b, ", yer home.")
	} else if !s.known {
		add(b, ". Not surveyed.")
	} else {
		add(b, ".")
	}
}

// The map cell under a screen pixel, if the pixel is on the map view.
screen_to_cell :: proc(g: ^Game, sx, sy: int) -> (x, y: int, ok: bool) {
	if sx < MAP_X || sy < MAP_Y || sx >= MAP_X + VIEW_W * TILE || sy >= MAP_Y + VIEW_H * TILE {
		return 0, 0, false
	}
	ox, oy := view_origin(g)
	return ox + (sx - MAP_X) / TILE, oy + (sy - MAP_Y) / TILE, true
}

// Top-left map cell of the view: the cursor in the middle, held inside the galaxy.
view_origin :: proc(g: ^Game) -> (x, y: int) {
	return clamp(g.cx - VIEW_W / 2, 0, GALAXY_W - VIEW_W), clamp(g.cy - VIEW_H / 2, 0, GALAXY_H - VIEW_H)
}

// A click or tap at a screen pixel. Any pointer on the map moves the cursor there and selects
// that cell; a right click (or a tap) on a star also names it in the panel (the same as select for now).
pointer :: proc(g: ^Game, sx, sy: int, p: Pointer) {
	x, y, ok := screen_to_cell(g, sx, sy)
	if !ok {
		return
	}
	g.cx, g.cy = x, y
	select_cell(g, x, y)
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
