package game

// The rules, independent of the platform. Slice 1 step 5 (PLAN.md): two computer rivals, technology,
// colonies, turns, fleets, fuel and surveying over a generated cluster. Combat and the rest arrive in
// later steps.

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
	Research,
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
	.Research   = {0, 0},
}

// How a click or tap reached the game (the page sends these numbers).
Pointer :: enum i32 {
	Mouse,
	Right_Mouse,
	Touch,
}

// What the controls are doing: choosing yer species, looking at the map, sharing out research, running a colony, picking
// ships to send, or picking where.
Mode :: enum u8 {
	Choose_Race,
	Map,
	Research,
	Colony,
	Fleet,
	Destination,
	Battle,
	Council,
	Game_Over,
}

Game :: struct {
	seed:       u64,
	rng:        Rng, // everything random after the cluster is made
	stars:      [MAX_STARS]Star,
	star_count: int,
	home:       int, // yer home star
	clubhouse:  int, // the legendary star
	moth_alive: bool, // its guardian
	cursor:     int, // the star under the cursor; the panel shows it
	turn:       int,
	empires:    [MAX_EMPIRES]Empire, // yers first, then the computer rivals
	empire_count: int,
	fleets:     [MAX_FLEETS]Fleet,
	mode:       Mode,
	source:     int, // the star ships are being sent from
	send:       [Ship_Type]int, // how many of each are going
	row:        int, // the highlighted row of the ship list
	outcome:    Outcome, // still playing, won or lost
	council:    Council, // the Homeowners' Association
	battle:     Battle, // the player's battle on screen
	pending:    [8][2]int, // the player's battles this turn: star, enemy
	pending_n:  int,
	pending_i:  int,
	news:       [NEWS_LINES]Message, // oldest first
}

init_game :: proc(g: ^Game, seed: u64) {
	g^ = {}
	g.seed = seed
	g.rng = Rng{seed ~ 0x5A17_C0DE_0000_0001}
	make_cluster(g, seed)
	g.empires[PLAYER].race = .Geese // until chosen; their trait waits for combat, so tests see plain numbers
	assign_rivals(g)
	for e in 0 ..< g.empire_count {
		offer_techs(&g.empires[e].tech, &g.rng)
		home := found_colony(g, g.empires[e].home, HOME_HOUSEHOLDS, e)
		home.factories = HOME_FACTORIES
		home.slider = HOME_SLIDERS
		f := new_fleet(g, e)
		f.ships = START_SHIPS
		f.star = g.empires[e].home
		f.refills = f.ships[.Gas_Can] * GAS_CAN_REFILLS
	}
	g.cursor = g.home
	g.turn = 1
	g.mode = .Map
	g.council.president = NO_OWNER
	update_sight(g)
	b: Text
	add(&b, "Welcome to ")
	add(&b, g.stars[g.home].name)
	add(&b, ". The Homeowners' Association has been notified.")
	say(g, text(&b))
	say(g, "(Slice 1, step 8: Enter/OK on a colony runs it; R or Tech for research; T ends the turn.)")
}

// A new game in the browser starts on the species screen; tests start straight on the map as Geese.
start_choosing :: proc(g: ^Game) {
	g.mode = .Choose_Race
	g.row = 0
}

choose_race :: proc(g: ^Game, r: Race) {
	g.empires[PLAYER].race = r
	assign_rivals(g)
	for i in 0 ..< g.star_count {
		if c := any_colony(g, i); c != nil {
			c.race = g.empires[c.owner].race
		}
	}
	g.mode = .Map
	b: Text
	add(&b, "Yer the ")
	add(&b, RACES[r].name)
	add(&b, ". The ")
	add(&b, empire_name(g, 1))
	add(&b, " and the ")
	add(&b, empire_name(g, 2))
	add(&b, " are out there somewhere. Everybody hates everybody.")
	say(g, text(&b))
}

// Up and Down pick a species, Enter/OK picks it.
race_command :: proc(g: ^Game, c: Command) {
	n := len(Race)
	#partial switch c {
	case .North:
		g.row = (g.row + n - 1) % n
	case .South:
		g.row = (g.row + 1) % n
	case .Confirm:
		choose_race(g, Race(g.row))
	}
}

command :: proc(g: ^Game, c: Command) {
	if c == .Research {
		// R, gamepad Y or the Tech pad opens the research screen from anywhere but the middle of an order.
		if g.mode == .Research {
			g.mode = .Map
		} else if g.mode == .Map || g.mode == .Colony {
			open_research(g)
		}
		return
	}
	switch g.mode {
	case .Council:
		council_command(g, c)
	case .Game_Over:
		// Enter/OK starts a new cluster.
		if c == .Confirm {
			seed := g.seed + 1
			init_game(g, seed)
			start_choosing(g)
		}
	case .Battle:
		battle_command(g, c)
	case .Choose_Race:
		race_command(g, c)
	case .Map:
		map_command(g, c)
	case .Research:
		research_command(g, c)
	case .Colony:
		colony_command(g, c)
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
		if colony_at(g, g.cursor) != nil {
			open_colony(g, g.cursor)
			return
		}
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
	case .Research:
		open_research(g)
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

// ---- The battle screen: pick a target, then fight a round, fight it out, or retreat ----

BATTLE_ROWS :: 3 // Fight a round, Fight it out, Retreat
BATTLE_ROW_NAMES := [BATTLE_ROWS]string{"Fight a round", "Fight it out", "Retreat"}

// Up and Down pick an action, Left and Right change the target, Enter/OK does the action.
battle_command :: proc(g: ^Game, c: Command) {
	bt := &g.battle
	#partial switch c {
	case .North:
		bt.row = (bt.row + BATTLE_ROWS - 1) % BATTLE_ROWS
	case .South:
		bt.row = (bt.row + 1) % BATTLE_ROWS
	case .West, .East:
		cycle_target(bt, c == .West ? -1 : 1)
	case .Confirm:
		battle_action(g, bt.row)
	}
}

// Steps the target through the live enemy stacks.
cycle_target :: proc(bt: ^Battle, by: int) {
	start := max(bt.target, 0)
	for k in 1 ..= bt.n {
		i := ((start + by * k) % bt.n + bt.n) % bt.n
		if bt.stacks[i].side == 1 && alive(&bt.stacks[i]) {
			bt.target = i
			return
		}
	}
}

battle_action :: proc(g: ^Game, row: int) {
	bt := &g.battle
	switch row {
	case 0:
		battle_round(g, bt)
	case 1:
		fight_it_out(g, bt)
	case 2:
		player_retreat(g, bt)
	}
	if bt.over {
		finish_battle(g, bt)
		next_battle(g)
	}
}

// ---- The research screen: six field rows, then Back ----

RESEARCH_BACK_ROW :: len(Field)
RESEARCH_ROWS :: RESEARCH_BACK_ROW + 1

open_research :: proc(g: ^Game) {
	g.mode = .Research
	g.row = 0
}

// Up and Down pick a field, Left and Right move its slider by 5, Enter/OK locks it (or, on Back,
// goes back); Escape/Back goes back to the map.
research_command :: proc(g: ^Game, c: Command) {
	res := &g.empires[PLAYER].tech
	#partial switch c {
	case .North:
		g.row = (g.row + RESEARCH_ROWS - 1) % RESEARCH_ROWS
	case .South:
		g.row = (g.row + 1) % RESEARCH_ROWS
	case .West, .East:
		if g.row < len(Field) {
			f := Field(g.row)
			v := res.slider[f]
			v = c == .West ? (v - 1) / SLIDER_STEP * SLIDER_STEP : (v / SLIDER_STEP + 1) * SLIDER_STEP
			set_research_slider(res, f, max(0, v))
		}
	case .Confirm:
		if g.row < len(Field) {
			res.locked[Field(g.row)] = !res.locked[Field(g.row)]
		} else {
			g.mode = .Map
		}
	case .Cancel:
		g.mode = .Map
	case .End_Turn:
		g.mode = .Map
		next_turn(g)
	}
}

// ---- The colony screen: five slider rows, then the ship order, yer ships there, and Back ----

BUILD_ROW :: len(Chore)
SHIPS_ROW :: BUILD_ROW + 1
COLONY_BACK_ROW :: SHIPS_ROW + 1
COLONY_ROWS :: COLONY_BACK_ROW + 1
SLIDER_STEP :: 5 // percent a key press moves a slider

open_colony :: proc(g: ^Game, star: int) {
	g.mode = .Colony
	g.source = star
	g.row = 0
}

// Up and Down pick a row; Left and Right move a slider or change the ship order; Enter/OK locks or
// unlocks a slider, or does what the row says; Escape/Back goes back to the map.
colony_command :: proc(g: ^Game, c: Command) {
	col := colony_at(g, g.source)
	if col == nil {
		g.mode = .Map
		return
	}
	#partial switch c {
	case .North:
		g.row = (g.row + COLONY_ROWS - 1) % COLONY_ROWS
	case .South:
		g.row = (g.row + 1) % COLONY_ROWS
	case .West, .East:
		by := c == .West ? -1 : 1
		if g.row < len(Chore) {
			ch := Chore(g.row)
			// Snap to the step, so repeated presses land on round numbers.
			v := col.slider[ch]
			v = by < 0 ? (v - 1) / SLIDER_STEP * SLIDER_STEP : (v / SLIDER_STEP + 1) * SLIDER_STEP
			set_slider(col, ch, max(0, v))
		} else if g.row == BUILD_ROW {
			cycle_build(col, by)
		}
	case .Confirm:
		colony_row_action(g, col, g.row)
	case .Cancel:
		g.mode = .Map
	case .End_Turn:
		g.mode = .Map
		next_turn(g)
	}
}

cycle_build :: proc(col: ^Colony, by: int) {
	n := len(Ship_Type)
	col.build = Ship_Type((int(col.build) + by + n) % n)
}

colony_row_action :: proc(g: ^Game, col: ^Colony, row: int) {
	switch {
	case row < len(Chore):
		col.locked[Chore(row)] = !col.locked[Chore(row)]
	case row == BUILD_ROW:
		cycle_build(col, 1)
	case row == SHIPS_ROW:
		if fleet_at(g, g.source) != nil {
			open_fleet(g, g.source)
		} else {
			say(g, "No ships parked here.")
		}
	case:
		g.mode = .Map
	}
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
// choosing where (or, on the "Pay" row, pays the fleet's upgrade fees), Escape/Back closes the list.
fleet_command :: proc(g: ^Game, c: Command) {
	rows, n := fleet_rows(g)
	if n == 0 {
		g.mode = .Map
		return
	}
	total := n
	src := fleet_at(g, g.source)
	if src != nil && owed(g, src) > 0 {
		total += 1 // the Pay row
	}
	#partial switch c {
	case .North:
		g.row = (g.row + total - 1) % total
	case .South:
		g.row = (g.row + 1) % total
	case .West:
		if g.row < n {
			change_send(g, rows[g.row], -1)
		}
	case .East:
		if g.row < n {
			change_send(g, rows[g.row], 1)
		}
	case .Confirm:
		if g.row == n {
			pay_from_list(g)
			return
		}
		choose_destination(g)
	case .Cancel:
		g.mode = .Map
	case .End_Turn:
		say(g, "Finish the orders first (Escape/Back closes them).")
	}
}

pay_from_list :: proc(g: ^Game) {
	src := fleet_at(g, g.source)
	if src == nil {
		return
	}
	due := owed(g, src)
	if pay_upgrades(g, src) {
		b: Text
		add(&b, "Paid ")
		add_int(&b, due)
		add(&b, " BJ. The ships at Lot ")
		add_int(&b, g.source + 1)
		add(&b, " are up to date.")
		say(g, text(&b))
		_, n := fleet_rows(g)
		g.row = min(g.row, n - 1)
	} else {
		say(g, "Not enough BJ for the upgrades.")
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
	problem := send_problem(g, PLAYER, g.source, to, g.send)
	if problem != "" {
		say(g, problem)
		return
	}
	trial := Fleet {
		ships = g.send,
	}
	turns := trip_turns(g, g.source, to, fleet_speed(&trial))
	send_fleet(g, PLAYER, g.source, to, g.send)
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
	if s.wormhole_known[PLAYER] {
		add(b, ": a wormhole.")
		return
	}
	if !s.reports[PLAYER].filed {
		add(b, ": not surveyed.")
		return
	}
	add(b, i == g.home ? ": yer home, " : colony_at(g, i) != nil ? ": yer colony, " : ": ")
	describe_report(b, &s.reports[PLAYER])
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
	if g.mode == .Game_Over {
		command(g, .Confirm)
		return
	}
	if g.mode == .Council {
		council_pointer(g, sx, sy)
		return
	}
	if g.mode == .Battle {
		battle_pointer(g, sx, sy)
		return
	}
	if g.mode == .Choose_Race {
		for i in 0 ..< len(Race) {
			y := race_row_y(i)
			if sy >= y - 3 && sy < y - 3 + RACE_H {
				if g.row == i {
					choose_race(g, Race(i))
				} else {
					g.row = i
				}
				return
			}
		}
		return
	}
	if sx >= PANEL_X {
		panel_pointer(g, sx, sy)
		return
	}
	if g.mode == .Colony {
		colony_pointer(g, sx, sy)
		return
	}
	if g.mode == .Research {
		research_pointer(g, sx, sy)
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
		if i == g.cursor && colony_at(g, i) != nil {
			open_colony(g, i)
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
	case .Council, .Game_Over, .Battle, .Choose_Race, .Research, .Colony, .Fleet:
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

// Where the colony screen draws its rows (in the map's place).
COLONY_X :: 6
SLIDER_TOP :: 66
SLIDER_H :: 14
BAR_COL :: 17 // the slider bar: 20 cells of a glyph's width from here
BAR_CELLS :: 20
PCT_COL :: 38
LOCK_COL :: 43
EFFECT_COL :: 46
BUILD_LEFT_COL :: 16 // "<" of the ship order
BUILD_RIGHT_COL :: 32 // ">" of the ship order

colony_row_y :: proc(row: int) -> int {
	return SLIDER_TOP + row * SLIDER_H
}

// A tap on the colony screen: on a bar sets the slider there, on the lock toggles it, on the ship
// order's arrows changes it, on a row picks it (and does what it says if it is not a slider).
colony_pointer :: proc(g: ^Game, sx, sy: int) {
	col := colony_at(g, g.source)
	if col == nil {
		return
	}
	cx := (sx - COLONY_X) / GLYPH_W
	for row in 0 ..< COLONY_ROWS {
		y := colony_row_y(row)
		if sy < y - 3 || sy >= y - 3 + SLIDER_H {
			continue
		}
		g.row = row
		switch {
		case row < len(Chore):
			ch := Chore(row)
			bar_x := COLONY_X + BAR_COL * GLYPH_W
			if sx >= bar_x - 3 && sx < bar_x + BAR_CELLS * GLYPH_W + 3 {
				v := (sx - bar_x) * 100 / (BAR_CELLS * GLYPH_W)
				set_slider(col, ch, (clamp(v, 0, 100) + SLIDER_STEP / 2) / SLIDER_STEP * SLIDER_STEP)
			} else if cx >= LOCK_COL - 1 && cx <= LOCK_COL + 1 {
				col.locked[ch] = !col.locked[ch]
			}
		case row == BUILD_ROW:
			if cx >= BUILD_LEFT_COL - 1 && cx <= BUILD_LEFT_COL + 1 {
				cycle_build(col, -1)
			} else if cx >= BUILD_RIGHT_COL - 1 && cx <= BUILD_RIGHT_COL + 1 {
				cycle_build(col, 1)
			}
		case:
			colony_row_action(g, col, row)
		}
		return
	}
}

// Where the battle screen draws: the grid of 24-pixel cells, and the action rows in the panel.
BATTLE_X :: 6
BATTLE_Y :: 26
BATTLE_CELL :: 24
BATTLE_ACTION_Y :: 190

battle_action_y :: proc(row: int) -> int {
	return BATTLE_ACTION_Y + row * 12
}

// A tap on an enemy stack targets it; a tap on an action row does it.
battle_pointer :: proc(g: ^Game, sx, sy: int) {
	bt := &g.battle
	if sx >= PANEL_X {
		for row in 0 ..< BATTLE_ROWS {
			if on_row(sy, battle_action_y(row)) {
				bt.row = row
				battle_action(g, row)
				return
			}
		}
		return
	}
	gx, gy := (sx - BATTLE_X) / BATTLE_CELL, (sy - BATTLE_Y) / BATTLE_CELL
	if sx < BATTLE_X || sy < BATTLE_Y || gx >= GRID_W || gy >= GRID_H {
		return
	}
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == 1 && alive(s) && s.x == gx && s.y == gy {
			bt.target = i
			return
		}
	}
}

// Where the council screen draws: the minutes from the top, the vote's choices near the foot.
MINUTES_Y :: 8
VOTE_Y :: 176

vote_row_y :: proc(row: int) -> int {
	return VOTE_Y + row * 12
}

// A tap on a vote's choice votes it; anywhere else closes the minutes once the vote is done.
council_pointer :: proc(g: ^Game, sx, sy: int) {
	c := &g.council
	if c.voting {
		for row in 0 ..< COUNCIL_CHOICES {
			if on_row(sy, vote_row_y(row)) {
				c.choice = row
				cast_votes(g, council_vote_of(row))
				return
			}
		}
		return
	}
	g.mode = .Map
}

// Where the species screen draws its rows: name, blurb and trait on three lines.
RACE_TOP :: 40
RACE_H :: 40

race_row_y :: proc(row: int) -> int {
	return RACE_TOP + row * RACE_H
}

// Where the research screen draws its rows: a field takes two lines.
RESEARCH_TOP :: 36
RESEARCH_H :: 26

research_row_y :: proc(row: int) -> int {
	return RESEARCH_TOP + row * RESEARCH_H
}

// A tap on the research screen: on a bar sets the field's slider there, on the lock toggles it,
// on Back goes back.
research_pointer :: proc(g: ^Game, sx, sy: int) {
	res := &g.empires[PLAYER].tech
	cx := (sx - COLONY_X) / GLYPH_W
	for row in 0 ..< RESEARCH_ROWS {
		y := research_row_y(row)
		if sy < y - 3 || sy >= y - 3 + RESEARCH_H {
			continue
		}
		g.row = row
		if row == RESEARCH_BACK_ROW {
			g.mode = .Map
			return
		}
		f := Field(row)
		bar_x := COLONY_X + BAR_COL * GLYPH_W
		if sx >= bar_x - 3 && sx < bar_x + BAR_CELLS * GLYPH_W + 3 {
			v := (sx - bar_x) * 100 / (BAR_CELLS * GLYPH_W)
			set_research_slider(res, f, (clamp(v, 0, 100) + SLIDER_STEP / 2) / SLIDER_STEP * SLIDER_STEP)
		} else if cx >= LOCK_COL - 1 && cx <= LOCK_COL + 1 {
			res.locked[f] = !res.locked[f]
		}
		return
	}
}

RESEARCH_LINK_Y :: VIEW_H * TILE - 12 // "R: research" at the foot of the panel

panel_pointer :: proc(g: ^Game, sx, sy: int) {
	if on_row(sy, RESEARCH_LINK_Y) && (g.mode == .Map || g.mode == .Colony || g.mode == .Research) {
		command(g, .Research)
		return
	}
	switch g.mode {
	case .Council, .Game_Over, .Battle, .Choose_Race, .Research, .Colony:
	case .Map:
		if on_row(sy, ACTION_Y) && colony_at(g, g.cursor) != nil {
			open_colony(g, g.cursor)
		} else if on_row(sy, ACTION_Y) && fleet_at(g, g.cursor) != nil {
			open_fleet(g, g.cursor)
		}
	case .Fleet:
		rows, n := fleet_rows(g)
		if src := fleet_at(g, g.source); src != nil && owed(g, src) > 0 && on_row(sy, FLEET_TOP + n * ROW_H + 4) {
			g.row = n
			pay_from_list(g)
			return
		}
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
