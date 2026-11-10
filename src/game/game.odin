package game

// The rules, independent of the platform. Slice 1 step 2 (PLAN.md): turns, fleets, fuel and surveying
// over a generated cluster. Colonies, technology, rivals and the rest arrive in later steps.

// Commands the page sends for keys, gamepad buttons and the touch pads (keep in step with
// web/index.html). Directions move the cursor to the next star that way, or work a list.
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

// What the controls are doing: looking at the map, picking ships to send, or picking where.
Mode :: enum u8 {
	Map,
	Fleet,
	Destination,
}

Game :: struct {
	seed:       u64,
	rng:        Rng, // everything random after the cluster is made
	stars:      [MAX_STARS]Star,
	star_count: int,
	home:       int,
	cursor:     int, // the star under the cursor; the panel shows it
	turn:       int,
	fleets:     [MAX_FLEETS]Fleet,
	mode:       Mode,
	source:     int, // the star ships are being sent from
	send:       [Ship_Type]int, // how many of each are going
	row:        int, // the highlighted row of the ship list
	news:       [NEWS_LINES]Message, // oldest first
}

init_game :: proc(g: ^Game, seed: u64) {
	g^ = {}
	g.seed = seed
	g.rng = Rng{seed ~ 0x5A17_C0DE_0000_0001}
	make_cluster(g, seed)
	g.cursor = g.home
	g.turn = 1
	f := new_fleet(g)
	f.ships = START_SHIPS
	f.star = g.home
	f.refills = f.ships[.Gas_Can] * GAS_CAN_REFILLS
	b: Text
	add(&b, "Welcome to ")
	add(&b, g.stars[g.home].name)
	add(&b, ". The Homeowners' Association has been notified.")
	say(g, text(&b))
	say(g, "(Slice 1, step 2: Enter/OK at home to send ships; T or Turn ends the turn.)")
}

command :: proc(g: ^Game, c: Command) {
	switch g.mode {
	case .Map:
		map_command(g, c)
	case .Fleet:
		fleet_command(g, c)
	case .Destination:
		destination_command(g, c)
	}
}

map_command :: proc(g: ^Game, c: Command) {
	switch c {
	case .North, .South, .West, .East, .North_West, .North_East, .South_West, .South_East:
		move_cursor(g, c)
	case .Confirm:
		if fleet_at(g, g.cursor) != nil {
			open_fleet(g, g.cursor)
			return
		}
		b: Text
		describe_star(g, g.cursor, &b)
		say(g, text(&b))
	case .Cancel:
		g.cursor = g.home
		say(g, "Back to yer home star.")
	case .End_Turn:
		next_turn(g)
	}
}

move_cursor :: proc(g: ^Game, c: Command) {
	d := DIRECTION[c]
	next := star_toward(g, g.cursor, d.x, d.y)
	if next != NO_STAR {
		g.cursor = next
	}
}

next_turn :: proc(g: ^Game) {
	g.turn += 1
	b: Text
	add(&b, "Turn ")
	add_int(&b, g.turn)
	add(&b, ".")
	say(g, text(&b))
	end_turn(g)
}

// The ship types present in the fleet being sent from, in order; the rows of the list.
fleet_rows :: proc(g: ^Game) -> (rows: [len(Ship_Type)]Ship_Type, n: int) {
	f := fleet_at(g, g.source)
	if f == nil {
		return
	}
	for c, t in f.ships {
		if c > 0 {
			rows[n] = t
			n += 1
		}
	}
	return
}

open_fleet :: proc(g: ^Game, star: int) {
	f := fleet_at(g, star)
	if f == nil {
		return
	}
	g.mode = .Fleet
	g.source = star
	g.send = f.ships
	g.row = 0
}

// Up and Down pick a row, Left and Right change how many of that kind go, Enter/OK goes on to
// choosing where, Escape/Back closes the list.
fleet_command :: proc(g: ^Game, c: Command) {
	rows, n := fleet_rows(g)
	if n == 0 {
		g.mode = .Map
		return
	}
	#partial switch c {
	case .North:
		g.row = (g.row + n - 1) % n
	case .South:
		g.row = (g.row + 1) % n
	case .West:
		change_send(g, rows[g.row], -1)
	case .East:
		change_send(g, rows[g.row], 1)
	case .Confirm:
		choose_destination(g)
	case .Cancel:
		g.mode = .Map
	case .End_Turn:
		say(g, "Finish the orders first (Escape/Back closes them).")
	}
}

change_send :: proc(g: ^Game, t: Ship_Type, by: int) {
	f := fleet_at(g, g.source)
	if f == nil {
		return
	}
	g.send[t] = clamp(g.send[t] + by, 0, f.ships[t])
}

choose_destination :: proc(g: ^Game) {
	trial := Fleet {
		ships = g.send,
	}
	if fleet_size(&trial) == 0 {
		say(g, "Nobody is going.")
		return
	}
	g.mode = .Destination
}

// The eight directions move the cursor among stars; Enter/OK sends the ships to the star under it;
// Escape/Back goes back to the list.
destination_command :: proc(g: ^Game, c: Command) {
	#partial switch c {
	case .North, .South, .West, .East, .North_West, .North_East, .South_West, .South_East:
		move_cursor(g, c)
	case .Confirm:
		try_send(g, g.cursor)
	case .Cancel:
		g.cursor = g.source
		g.mode = .Fleet
	case .End_Turn:
		say(g, "Finish the orders first (Escape/Back goes back).")
	}
}

try_send :: proc(g: ^Game, to: int) {
	problem := send_problem(g, g.source, to, g.send)
	if problem != "" {
		say(g, problem)
		return
	}
	trial := Fleet {
		ships = g.send,
	}
	turns := trip_turns(g, g.source, to, fleet_speed(&trial))
	send_fleet(g, g.source, to, g.send)
	b: Text
	add_int(&b, fleet_size(&trial))
	add(&b, fleet_size(&trial) == 1 ? " ship leaves for Lot " : " ships leave for Lot ")
	add_int(&b, to + 1)
	add(&b, ". Due in ")
	add_int(&b, turns)
	add(&b, turns == 1 ? " turn." : " turns.")
	say(g, text(&b))
	g.cursor = g.source
	g.mode = .Map
}

// "Pollux (Lot 8): yer home, a Medium Terran world." and the like, from what has been filed.
describe_star :: proc(g: ^Game, i: int, b: ^Text) {
	s := &g.stars[i]
	add(b, s.name)
	add(b, " (Lot ")
	add_int(b, i + 1)
	add(b, ")")
	if s.wormhole_known {
		add(b, ": a wormhole.")
		return
	}
	if !s.report.filed {
		add(b, ": not surveyed.")
		return
	}
	add(b, i == g.home ? ": yer home, " : ": ")
	describe_report(b, &s.report)
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

// Panel rows that can be clicked or tapped (render.odin draws them at these places).
PANEL_TEXT_X :: PANEL_X + 2
ACTION_Y :: VIEW_H * TILE - 40 // "Send ships" on the map; "Send here" while choosing where
BACK_Y :: ACTION_Y + 12
FLEET_TOP :: 72 // the first row of the ship list
ROW_H :: 10
COUNT_COL :: 13 // the column where "<n>" starts in a ship row

// A click or tap at a screen pixel. On the map: on or next to a star (one cell's slack, for fingers)
// moves the cursor there; on the star already under the cursor with yer ships, opens them. While
// choosing where: a star moves the cursor, the same star again sends. The panel's rows act too.
pointer :: proc(g: ^Game, sx, sy: int, p: Pointer) {
	if sx >= PANEL_X {
		panel_pointer(g, sx, sy)
		return
	}
	x, y, ok := screen_to_cell(g, sx, sy)
	if !ok {
		return
	}
	i := star_near(g, x, y, 1)
	switch g.mode {
	case .Map:
		if i == NO_STAR {
			say(g, "Empty space. Nobody owns it yet.")
			return
		}
		if i == g.cursor && fleet_at(g, i) != nil {
			open_fleet(g, i)
			return
		}
		g.cursor = i
		b: Text
		describe_star(g, i, &b)
		say(g, text(&b))
	case .Fleet:
	case .Destination:
		if i == NO_STAR {
			return
		}
		if i == g.cursor {
			try_send(g, i)
			return
		}
		g.cursor = i
	}
}

on_row :: proc(sy, y: int) -> bool {
	return sy >= y - 1 && sy < y + ROW_H - 1
}

panel_pointer :: proc(g: ^Game, sx, sy: int) {
	switch g.mode {
	case .Map:
		if on_row(sy, ACTION_Y) && fleet_at(g, g.cursor) != nil {
			open_fleet(g, g.cursor)
		}
	case .Fleet:
		rows, n := fleet_rows(g)
		for i in 0 ..< n {
			if on_row(sy, FLEET_TOP + i * ROW_H) {
				g.row = i
				col := (sx - PANEL_TEXT_X) / GLYPH_W
				if col >= COUNT_COL && col < COUNT_COL + 2 {
					change_send(g, rows[i], -1)
				} else if col >= COUNT_COL + 2 {
					change_send(g, rows[i], 1)
				}
				return
			}
		}
		if on_row(sy, ACTION_Y) {
			choose_destination(g)
		} else if on_row(sy, BACK_Y) {
			g.mode = .Map
		}
	case .Destination:
		if on_row(sy, ACTION_Y) {
			try_send(g, g.cursor)
		} else if on_row(sy, BACK_Y) {
			g.cursor = g.source
			g.mode = .Fleet
		}
	}
}

// ---- Messages and text without core:fmt ----

LOG_CAP :: 96 // characters per remembered message

Message :: struct {
	text: [LOG_CAP]u8,
	n:    int,
}

// Adds a message to the news ticker, wrapped at spaces to its width (a long one takes two lines).
say :: proc(g: ^Game, s: string) {
	rest := s
	for len(rest) > 0 {
		cut := min(len(rest), NEWS_COLS, LOG_CAP)
		if cut < len(rest) {
			for i := cut; i > 0; i -= 1 {
				if rest[i] == ' ' {
					cut = i
					break
				}
			}
		}
		for i in 0 ..< NEWS_LINES - 1 {
			g.news[i] = g.news[i + 1]
		}
		m := &g.news[NEWS_LINES - 1]
		m^ = {}
		m.n = cut
		copy(m.text[:m.n], rest[:m.n])
		rest = rest[cut:]
		for len(rest) > 0 && rest[0] == ' ' {
			rest = rest[1:]
		}
	}
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
