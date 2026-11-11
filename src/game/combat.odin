package game

// Combat (slice 1 step 6): when two empires' ships (or one's ships and the other's defence bases) are
// at the same star, they fight on a 10 by 8 grid. Each side's ships are stacks of one type with a
// count; every round each armed stack closes on its target and fires. Rolls are hidden: the news says
// only what was lost. A side may retreat; the player may fight round by round, or fight it out.
// Numbers are starting values to tune by playing (PLAN.md).

GRID_W :: 10
GRID_H :: 8
MAX_STACKS :: 16
MAX_ROUNDS :: 10 // a battle not decided by then is broken off; both sides stay (and fight next turn)
BASE_HIT_CHANCE :: 50 // percent, before kit and species
HIT_PER_TO_HIT :: 10 // percent per point of aiming kit
GEESE_HIT :: 10 // Geese aim a fifth better: 50 becomes 60
SHOT_DAMAGE :: 3 // per hit, before weapons kit and the target's shields
AI_RETREAT_PERCENT :: 25 // a computer side leaves when its armed strength falls below this share of the enemy's

Combat_Info :: struct {
	hp:      int, // hits a ship takes before it is lost
	weapons: int, // shots a round
	range:   int, // grid cells
	move:    int, // grid cells a round
}

COMBAT := [Ship_Type]Combat_Info {
	.Inspector     = {2, 0, 0, 3},
	.Moving_Van    = {4, 0, 0, 2},
	.Carpool       = {4, 0, 0, 2},
	.Gas_Can       = {3, 0, 0, 2},
	.Golf_Cart     = {4, 1, 2, 3},
	.Pickup        = {10, 2, 3, 2},
	.Monster_Truck = {24, 4, 4, 1},
}

BASE_COMBAT :: Combat_Info{15, 2, 4, 0} // a defence base: never moves
MOTH_COMBAT :: Combat_Info{72, 12, 4, 0} // the very large space moth: about three Monster Trucks, never leaves
MOTH_DAMAGE :: 4
MOTH_HIT :: 50

Stack :: struct {
	side:    int, // 0 or 1
	base:    bool, // defence bases rather than ships
	moth:    bool, // the Clubhouse's guardian
	kind:    Ship_Type,
	count:   int,
	start:   int, // count when the battle began
	hp:      int, // hits left on the front ship
	full:    int, // hits a fresh one takes
	x, y:    int,
	weapons: int,
	range:   int,
	move:    int,
	to_hit:  int, // percent
	damage:  int,
	shield:  int,
}

Battle :: struct {
	star:    int,
	owners:  [2]int, // side 0 (yers, when you are in it) and side 1
	stacks:  [MAX_STACKS]Stack,
	n:       int,
	round:   int,
	target:  int, // the enemy stack side 0 aims at, chosen by the player
	row:     int, // the highlighted action
	over:    bool,
	retreat: int, // the side that retreated, or -1
}

// An empire's presence at a star: its docked fleet, and its colony's bases.
present :: proc(g: ^Game, star, owner: int) -> bool {
	return fleet_of(g, star, owner) != nil || colony_of(g, star, owner) != nil
}

armed :: proc(g: ^Game, star, owner: int) -> bool {
	if f := fleet_of(g, star, owner); f != nil {
		for c, t in f.ships {
			if c > 0 && COMBAT[t].weapons > 0 {
				return true
			}
		}
	}
	if c := colony_of(g, star, owner); c != nil && c.bases > 0 {
		return true
	}
	return false
}

// Something of the owner's at the star that can be shot at: ships, or bases.
targets :: proc(g: ^Game, star, owner: int) -> bool {
	if fleet_of(g, star, owner) != nil {
		return true
	}
	c := colony_of(g, star, owner)
	return c != nil && c.bases > 0
}

// Whether two empires at a star come to blows: one can shoot and the other has something to shoot.
will_fight :: proc(g: ^Game, star, a, b: int) -> bool {
	return (armed(g, star, a) && targets(g, star, b)) || (armed(g, star, b) && targets(g, star, a))
}

hit_chance :: proc(g: ^Game, owner, to_hit_kit: int) -> int {
	c := BASE_HIT_CHANCE + HIT_PER_TO_HIT * to_hit_kit
	if g.empires[owner].race == .Geese {
		c += GEESE_HIT
	}
	return clamp(c, 5, 95)
}

// Lays out a battle: side 0 on the left, side 1 on the right, bases at the back.
setup_battle :: proc(g: ^Game, star, a, b: int) -> Battle {
	bt := Battle {
		star    = star,
		owners  = {a, b},
		retreat = -1,
		target  = -1,
	}
	used: [GRID_W][GRID_H]bool
	free_row :: proc(used: ^[GRID_W][GRID_H]bool, x: int, order: []int) -> int {
		for y in order {
			if !used[x][y] {
				used[x][y] = true
				return y
			}
		}
		return 0
	}
	SHIP_ROWS := [GRID_H]int{1, 3, 5, 7, 0, 2, 4, 6}
	BASE_ROWS := [GRID_H]int{4, 3, 5, 2, 6, 1, 7, 0}
	for side in 0 ..< 2 {
		owner := bt.owners[side]
		front := side == 0 ? 1 : GRID_W - 2
		back := side == 0 ? 0 : GRID_W - 1
		if f := fleet_of(g, star, owner); f != nil {
			for c, t in f.ships {
				if c == 0 || bt.n >= MAX_STACKS {
					continue
				}
				info := COMBAT[t]
				full := info.hp * (4 + f.kit[.Armour]) / 4
				x := info.weapons > 0 ? front : back
				bt.stacks[bt.n] = {
					side    = side,
					kind    = t,
					count   = c,
					start   = c,
					hp      = full,
					full    = full,
					x       = x,
					y       = free_row(&used, x, SHIP_ROWS[:]),
					weapons = info.weapons,
					range   = info.range,
					move    = info.move,
					to_hit  = hit_chance(g, owner, f.kit[.To_Hit]),
					damage  = SHOT_DAMAGE + f.kit[.Weapon],
					shield  = f.kit[.Shield],
				}
				bt.n += 1
			}
		}
		if owner == MOTH {
			bt.stacks[bt.n] = {
				side    = side,
				moth    = true,
				count   = 1,
				start   = 1,
				hp      = MOTH_COMBAT.hp,
				full    = MOTH_COMBAT.hp,
				x       = back - 1,
				y       = free_row(&used, back - 1, BASE_ROWS[:]),
				weapons = MOTH_COMBAT.weapons,
				range   = MOTH_COMBAT.range,
				to_hit  = MOTH_HIT,
				damage  = MOTH_DAMAGE,
			}
			bt.n += 1
			continue
		}
		if c := colony_of(g, star, owner); c != nil && c.bases > 0 && bt.n < MAX_STACKS {
			d := bonus(g, owner, .Base_Defence)
			bt.stacks[bt.n] = {
				side    = side,
				base    = true,
				count   = c.bases,
				start   = c.bases,
				hp      = BASE_COMBAT.hp,
				full    = BASE_COMBAT.hp,
				x       = back,
				y       = free_row(&used, back, BASE_ROWS[:]),
				weapons = BASE_COMBAT.weapons,
				range   = BASE_COMBAT.range,
				to_hit  = hit_chance(g, owner, d),
				damage  = SHOT_DAMAGE + d,
				shield  = d,
			}
			bt.n += 1
		}
	}
	bt.target = nearest_enemy(&bt, -1, 0)
	return bt
}

alive :: proc(s: ^Stack) -> bool {
	return s.count > 0
}

grid_distance :: proc(a, b: ^Stack) -> int {
	return max(abs(a.x - b.x), abs(a.y - b.y))
}

// The nearest live enemy of a stack (or, with from = -1, of the given side), or -1.
nearest_enemy :: proc(bt: ^Battle, from: int, side: int) -> int {
	best, best_d := -1, max(int)
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == side || !alive(s) {
			continue
		}
		d := 0
		if from >= 0 {
			d = grid_distance(&bt.stacks[from], s)
		} else {
			d = side == 0 ? s.x : GRID_W - 1 - s.x
		}
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// Total hits an armed side has left, counting bases: how the computer judges whether to stay.
strength :: proc(bt: ^Battle, side: int) -> int {
	n := 0
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == side && alive(s) && s.weapons > 0 {
			n += (s.count - 1) * s.full + s.hp
		}
	}
	return n
}

side_alive :: proc(bt: ^Battle, side: int) -> bool {
	for i in 0 ..< bt.n {
		if bt.stacks[i].side == side && alive(&bt.stacks[i]) {
			return true
		}
	}
	return false
}

// One round: fastest stacks first, each armed stack closes on its target and fires. Losses are told
// in the news when the player is in it.
battle_round :: proc(g: ^Game, bt: ^Battle) {
	if bt.over {
		return
	}
	bt.round += 1
	before: [MAX_STACKS]int
	for i in 0 ..< bt.n {
		before[i] = bt.stacks[i].count
	}
	for move := 3; move >= 0; move -= 1 {
		for i in 0 ..< bt.n {
			s := &bt.stacks[i]
			if s.move != move || !alive(s) || s.weapons == 0 {
				continue
			}
			t := -1
			if s.side == 0 && bt.owners[0] == PLAYER && bt.target >= 0 && alive(&bt.stacks[bt.target]) {
				t = bt.target
			} else {
				t = nearest_enemy(bt, i, s.side)
			}
			if t < 0 {
				continue
			}
			target := &bt.stacks[t]
			for step := 0; step < s.move && grid_distance(s, target) > s.range; step += 1 {
				if !step_toward(bt, i, target.x, target.y) {
					break
				}
			}
			if grid_distance(s, target) > s.range {
				continue
			}
			for _ in 0 ..< s.count * s.weapons {
				if !alive(target) {
					break
				}
				if rng_int(&g.rng, 100) >= s.to_hit {
					continue
				}
				dmg := max(1, s.damage - target.shield)
				if dmg >= target.hp {
					target.count -= 1
					target.hp = target.full
				} else {
					target.hp -= dmg
				}
			}
		}
	}
	if bt.owners[0] == PLAYER || bt.owners[1] == PLAYER {
		b: Text
		add(&b, "Round ")
		add_int(&b, bt.round)
		add(&b, ":")
		any_loss := false
		for side in 0 ..< 2 {
			lost := 0
			for i in 0 ..< bt.n {
				if bt.stacks[i].side == side {
					lost += before[i] - bt.stacks[i].count
				}
			}
			if lost > 0 {
				add(&b, any_loss ? "; " : " ")
				add(&b, bt.owners[side] == PLAYER ? "you lose " : "the ")
				if bt.owners[side] != PLAYER {
					add(&b, empire_name(g, bt.owners[side]))
					add(&b, " lose ")
				}
				add_int(&b, lost)
				any_loss = true
			}
		}
		add(&b, any_loss ? "." : " nobody hits anything.")
		say(g, text(&b))
	}
	check_over(bt)
	if !bt.over && bt.owners[0] != PLAYER {
		ai_battle_choice(g, bt, 0)
	}
	if !bt.over && bt.owners[1] != PLAYER {
		ai_battle_choice(g, bt, 1)
	}
	if !bt.over && bt.target >= 0 && !alive(&bt.stacks[bt.target]) {
		bt.target = nearest_enemy(bt, -1, 0)
	}
}

// Moves a stack one cell towards a spot, never onto a cell another live stack holds: straight at it
// if it can, else along one axis. False if every way is blocked.
step_toward :: proc(bt: ^Battle, i: int, tx, ty: int) -> bool {
	s := &bt.stacks[i]
	dx, dy := sign(tx - s.x), sign(ty - s.y)
	tries := [3][2]int{{dx, dy}, {dx, 0}, {0, dy}}
	for d in tries {
		if d == {0, 0} {
			continue
		}
		nx, ny := s.x + d.x, s.y + d.y
		if nx < 0 || ny < 0 || nx >= GRID_W || ny >= GRID_H || occupied(bt, nx, ny) {
			continue
		}
		s.x, s.y = nx, ny
		return true
	}
	return false
}

occupied :: proc(bt: ^Battle, x, y: int) -> bool {
	for i in 0 ..< bt.n {
		if alive(&bt.stacks[i]) && bt.stacks[i].x == x && bt.stacks[i].y == y {
			return true
		}
	}
	return false
}

sign :: proc(v: int) -> int {
	return v > 0 ? 1 : v < 0 ? -1 : 0
}

check_over :: proc(bt: ^Battle) {
	if !side_alive(bt, 0) || !side_alive(bt, 1) || bt.round >= MAX_ROUNDS {
		bt.over = true
	}
	if strength(bt, 0) == 0 && strength(bt, 1) == 0 {
		bt.over = true // nobody left who can shoot
	}
}

// A computer side leaves a battle it is losing badly, if it has somewhere to go.
ai_battle_choice :: proc(g: ^Game, bt: ^Battle, side: int) {
	mine, theirs := strength(bt, side), strength(bt, 1 - side)
	if theirs > 0 && mine * 100 < theirs * AI_RETREAT_PERCENT && retreat_to(g, bt, side) != NO_STAR {
		bt.retreat = side
		bt.over = true
	}
}

// Where a side's ships can retreat to: the nearest of its colonies they can reach (not this star).
retreat_to :: proc(g: ^Game, bt: ^Battle, side: int) -> int {
	owner := bt.owners[side]
	f := fleet_of(g, bt.star, owner)
	if f == nil {
		return NO_STAR
	}
	ships := surviving_ships(bt, side)
	best, best_d := NO_STAR, max(int)
	a := g.stars[bt.star]
	for i in 0 ..< g.star_count {
		if i == bt.star || colony_of(g, i, owner) == nil {
			continue
		}
		if send_problem_with(g, owner, bt.star, i, ships, f) != "" {
			continue
		}
		s := g.stars[i]
		d := (a.x - s.x) * (a.x - s.x) + (a.y - s.y) * (a.y - s.y)
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// send_problem, but for ships counted from a battle rather than the fleet as it stands.
send_problem_with :: proc(g: ^Game, owner, from, to: int, ships: [Ship_Type]int, f: ^Fleet) -> string {
	trial := Fleet {
		ships = ships,
		away  = f.away,
		kit   = f.kit,
	}
	if fleet_size(&trial) == 0 {
		return "Nobody is going."
	}
	if trip_turns(g, from, to, fleet_speed(&trial)) > fleet_range(&trial) {
		return "Out of range."
	}
	return ""
}

surviving_ships :: proc(bt: ^Battle, side: int) -> (ships: [Ship_Type]int) {
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == side && !s.base {
			ships[s.kind] += s.count
		}
	}
	return
}

// Fights rounds until the battle is over.
fight_it_out :: proc(g: ^Game, bt: ^Battle) {
	for !bt.over {
		battle_round(g, bt)
	}
}

// The player's side leaves for the nearest colony it can reach.
player_retreat :: proc(g: ^Game, bt: ^Battle) -> bool {
	if retreat_to(g, bt, 0) == NO_STAR {
		say(g, "Nowhere to retreat to.")
		return false
	}
	bt.retreat = 0
	bt.over = true
	return true
}

// Writes a finished battle back into the fleets and colonies, sends retreating ships off, and tells
// the news.
finish_battle :: proc(g: ^Game, bt: ^Battle) {
	lost: [2]int
	for side in 0 ..< 2 {
		owner := bt.owners[side]
		ships := surviving_ships(bt, side)
		if f := fleet_of(g, bt.star, owner); f != nil {
			for c, t in f.ships {
				if c > 0 {
					lost[side] += c - ships[t]
				}
			}
			f.ships = ships
			if fleet_size(f) == 0 {
				f^ = {}
			}
		}
		for i in 0 ..< bt.n {
			s := &bt.stacks[i]
			if s.side == side && s.base {
				if c := colony_of(g, bt.star, owner); c != nil {
					lost[side] += c.bases - s.count
					c.bases = s.count
				}
			}
		}
	}
	for i in 0 ..< bt.n {
		if bt.stacks[i].moth && bt.stacks[i].count == 0 && g.moth_alive {
			g.moth_alive = false
			who := bt.owners[1 - bt.stacks[i].side]
			b: Text
			if who == PLAYER {
				add(&b, "The moth is gone. The porch light is still on. The Clubhouse is anybody's.")
			} else {
				add(&b, "The ")
				add(&b, empire_name(g, who))
				add(&b, " have seen off the moth. The Clubhouse is anybody's.")
			}
			say(g, text(&b))
		}
	}
	if bt.retreat >= 0 {
		owner := bt.owners[bt.retreat]
		to := retreat_to(g, bt, bt.retreat)
		if f := fleet_of(g, bt.star, owner); f != nil && to != NO_STAR {
			send_fleet(g, owner, bt.star, to, f.ships)
		}
	}
	s := &g.stars[bt.star]
	involved := bt.owners[0] == PLAYER || bt.owners[1] == PLAYER
	if !involved && !g.empires[PLAYER].sees[bt.star] {
		return
	}
	b: Text
	if involved {
		mine := bt.owners[0] == PLAYER ? 0 : 1
		add(&b, "Battle at ")
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, bt.star + 1)
		add(&b, "): you lost ")
		add_int(&b, lost[mine])
		add(&b, ", the ")
		add(&b, empire_name(g, bt.owners[1 - mine]))
		if bt.owners[1 - mine] == MOTH {
			add(&b, g.moth_alive ? " lost nothing it would miss." : " lost its appetite.")
		} else {
			add(&b, " lost ")
			add_int(&b, lost[1 - mine])
			add(&b, ".")
		}
		if bt.retreat == mine {
			add(&b, " Yer ships withdrew.")
		} else if bt.retreat == 1 - mine {
			add(&b, " They withdrew.")
		}
	} else {
		add(&b, "The ")
		add(&b, empire_name(g, bt.owners[0]))
		add(&b, " and the ")
		add(&b, empire_name(g, bt.owners[1]))
		add(&b, " fought at ")
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, bt.star + 1)
		add(&b, "). Losses: ")
		add_int(&b, lost[0])
		add(&b, " and ")
		add_int(&b, lost[1])
		add(&b, ".")
	}
	say(g, text(&b))
}

// After the turn's moves: every pair of empires at a star that will fight does. Battles without the
// player are fought out at once; the player's wait for the battle screen, one after another.
find_battles :: proc(g: ^Game) {
	g.pending_n = 0
	if g.outcome != .Playing {
		return
	}
	// Whoever parks at the Clubhouse meets the moth first.
	if g.moth_alive {
		for e in 0 ..< g.empire_count {
			if fleet_of(g, g.clubhouse, e) == nil {
				continue
			}
			if e == PLAYER {
				g.pending[g.pending_n] = {g.clubhouse, MOTH}
				g.pending_n += 1
				continue
			}
			bt := setup_battle(g, g.clubhouse, e, MOTH)
			fight_it_out(g, &bt)
			finish_battle(g, &bt)
		}
	}
	for i in 0 ..< g.star_count {
		for a in 0 ..< g.empire_count {
			for b in a + 1 ..< g.empire_count {
				if !present(g, i, a) || !present(g, i, b) || !will_fight(g, i, a, b) {
					continue
				}
				if a == PLAYER {
					if g.pending_n < len(g.pending) {
						g.pending[g.pending_n] = {i, b}
						g.pending_n += 1
					}
					continue
				}
				bt := setup_battle(g, i, a, b)
				fight_it_out(g, &bt)
				finish_battle(g, &bt)
			}
		}
	}
	g.pending_i = 0
	next_battle(g)
}

// Opens the next of the player's battles, or goes back to the map when there are none left.
next_battle :: proc(g: ^Game) {
	for g.pending_i < g.pending_n {
		p := g.pending[g.pending_i]
		g.pending_i += 1
		moth := p.y == MOTH && g.moth_alive && fleet_at(g, p.x) != nil
		if moth || (p.y != MOTH && present(g, p.x, PLAYER) && present(g, p.x, p.y) && will_fight(g, p.x, PLAYER, p.y)) {
			g.battle = setup_battle(g, p.x, PLAYER, p.y)
			g.mode = .Battle
			g.cursor = p.x
			b: Text
			if moth {
				say(g, "Something very large is drawn to the Clubhouse's porch light. It is a moth.")
			} else {
				add(&b, "The ")
				add(&b, empire_name(g, p.y))
				add(&b, " at ")
				add(&b, g.stars[p.x].name)
				add(&b, " (Lot ")
				add_int(&b, p.x + 1)
				add(&b, "). They hate you. Battle stations.")
				say(g, text(&b))
			}
			return
		}
	}
	if g.mode == .Battle {
		g.mode = .Map
		show_waiting_meeting(g)
	}
}
