#+build !js
package game

import "core:strings"
import "core:testing"

// A rival fleet of these ships docked at a star.
rival_fleet :: proc(g: ^Game, star, owner: int, ships: [Ship_Type]int) -> ^Fleet {
	f := new_fleet(g, owner)
	f.ships = ships
	dock(g, f, star)
	return fleet_of(g, star, owner)
}

@(test)
test_who_fights_whom :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Inspector, 1))
	f := new_fleet(g)
	f.ships = only(.Inspector, 1)
	dock(g, f, to)
	testing.expect(t, !will_fight(g, to, PLAYER, 1)) // nobody can shoot
	fleet_at(g, to).ships[.Golf_Cart] = 1
	testing.expect(t, will_fight(g, to, PLAYER, 1))
	// Warships at a colony with no bases and no ships: nothing to shoot (landing troops is step 7).
	h := g.empires[1].home
	fleet_of(g, h, 1)^ = {}
	rival_fleet(g, h, PLAYER, only(.Golf_Cart, 2))
	testing.expect(t, !will_fight(g, h, PLAYER, 1))
	colony_of(g, h, 1).bases = 1
	testing.expect(t, will_fight(g, h, PLAYER, 1))
}

@(test)
test_battle_layout :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[1].home
	colony_of(g, h, 1).bases = 2
	rival_fleet(g, h, PLAYER, only(.Pickup, 3))
	bt := setup_battle(g, h, PLAYER, 1)
	bases, pickups := 0, 0
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.base {
			bases += s.count
			testing.expect_value(t, s.side, 1)
			testing.expect_value(t, s.x, GRID_W - 1)
		}
		if s.side == 0 {
			testing.expect_value(t, s.kind, Ship_Type.Pickup)
			pickups += s.count
			testing.expect_value(t, s.x, 1)
		}
	}
	testing.expect_value(t, bases, 2)
	testing.expect_value(t, pickups, 3)
	testing.expect(t, bt.target >= 0 && bt.stacks[bt.target].side == 1)
}

@(test)
test_the_stronger_side_wins_and_losses_are_written_back :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	wins := 0
	for seed in u64(1) ..= 30 {
		init_game(g, seed)
		to := nearest_other(g)
		rival_fleet(g, to, 1, only(.Golf_Cart, 1))
		rival_fleet(g, to, PLAYER, only(.Pickup, 4))
		bt := setup_battle(g, to, PLAYER, 1)
		fight_it_out(g, &bt)
		finish_battle(g, &bt)
		if fleet_of(g, to, 1) == nil {
			wins += 1
		}
		mine := fleet_at(g, to)
		testing.expect(t, mine != nil && mine.ships[.Pickup] == 4) // a Golf Cart cannot sink a Pickup in time
	}
	testing.expect(t, wins >= 28)
}

@(test)
test_geese_aim_better :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	g.empires[PLAYER].race = .Beavers
	plain := hit_chance(g, PLAYER, 0)
	g.empires[PLAYER].race = .Geese
	testing.expect_value(t, hit_chance(g, PLAYER, 0), plain + GEESE_HIT)
	testing.expect_value(t, hit_chance(g, PLAYER, 1), plain + GEESE_HIT + HIT_PER_TO_HIT)
	testing.expect_value(t, hit_chance(g, PLAYER, 100), 95)
}

@(test)
test_kit_counts_in_battle :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	f := rival_fleet(g, to, PLAYER, only(.Golf_Cart, 1))
	f.kit[.Weapon], f.kit[.Shield], f.kit[.Armour], f.kit[.To_Hit] = 2, 1, 4, 1
	rival_fleet(g, to, 1, only(.Golf_Cart, 1))
	bt := setup_battle(g, to, PLAYER, 1)
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == 0 {
			testing.expect_value(t, s.damage, SHOT_DAMAGE + 2)
			testing.expect_value(t, s.shield, 1)
			testing.expect_value(t, s.full, COMBAT[.Golf_Cart].hp * 2)
			testing.expect_value(t, s.to_hit, hit_chance(g, PLAYER, 1))
		}
	}
}

@(test)
test_a_battle_nobody_can_win_is_broken_off :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Monster_Truck, 1))
	rival_fleet(g, to, PLAYER, only(.Monster_Truck, 1))
	bt := setup_battle(g, to, PLAYER, 1)
	for i in 0 ..< bt.n {
		bt.stacks[i].to_hit = 0
	}
	fight_it_out(g, &bt)
	testing.expect_value(t, bt.round, MAX_ROUNDS)
	finish_battle(g, &bt)
	testing.expect(t, fleet_of(g, to, 1) != nil && fleet_at(g, to) != nil)
}

@(test)
test_retreat :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Monster_Truck, 3))
	rival_fleet(g, to, PLAYER, only(.Golf_Cart, 2))
	bt := setup_battle(g, to, PLAYER, 1)
	testing.expect(t, player_retreat(g, &bt))
	finish_battle(g, &bt)
	testing.expect(t, fleet_at(g, to) == nil)
	going := false
	for &f in g.fleets {
		if f.used && f.owner == PLAYER && f.star == NO_STAR && f.to == g.home && f.ships[.Golf_Cart] == 2 {
			going = true
		}
	}
	testing.expect(t, going)
	// With no colony in reach, there is nowhere to go.
	far := g.empires[2].home
	fleet_of(g, far, 2).ships = only(.Monster_Truck, 3)
	rival_fleet(g, far, PLAYER, only(.Monster_Truck, 1))
	bt2 := setup_battle(g, far, PLAYER, 2)
	testing.expect(t, !player_retreat(g, &bt2))
}

@(test)
test_a_losing_computer_side_withdraws :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	// The rival's own Golf Carts, met at a star next to its home by a much bigger fleet of yers.
	h := g.empires[1].home
	rival_fleet(g, h, PLAYER, only(.Monster_Truck, 4))
	bt := setup_battle(g, h, PLAYER, 1)
	ai_battle_choice(g, &bt, 1)
	// At its own colony it has nowhere else nearer to go only if it has no other colony: it stays.
	testing.expect_value(t, bt.retreat, -1)
}

@(test)
test_battles_found_at_the_turns_end :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Golf_Cart, 1))
	rival_fleet(g, to, PLAYER, only(.Pickup, 2))
	find_battles(g)
	testing.expect_value(t, g.mode, Mode.Battle)
	testing.expect_value(t, g.battle.star, to)
	// Keys: the target, a round, then fight it out.
	command(g, .East)
	testing.expect(t, g.battle.target >= 0)
	command(g, .Confirm)
	testing.expect(t, g.battle.round >= 1 || g.mode == .Map)
	if g.mode == .Battle {
		command(g, .South)
		command(g, .Confirm)
	}
	testing.expect_value(t, g.mode, Mode.Map)
	found := false
	for &m in g.news {
		if strings.contains(message(&m), "lost") || strings.contains(message(&m), "Battle at") {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_battle_by_pointer :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, ship_n(.Golf_Cart, 2))
	fleet_of(g, to, 1).ships[.Inspector] = 1
	rival_fleet(g, to, PLAYER, only(.Pickup, 1))
	find_battles(g)
	bt := &g.battle
	for i in 0 ..< bt.n {
		s := &bt.stacks[i]
		if s.side == 1 && i != bt.target {
			pointer(g, BATTLE_X + s.x * BATTLE_CELL + 5, BATTLE_Y + s.y * BATTLE_CELL + 5, .Touch)
			testing.expect_value(t, bt.target, i)
			break
		}
	}
	pointer(g, PANEL_TEXT_X + 4, battle_action_y(1) + 3, .Touch) // Fight it out
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_computer_battles_happen_out_of_sight :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[2].home
	rival_fleet(g, h, 1, only(.Monster_Truck, 3))
	before := g.news
	find_battles(g)
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect(t, colony_of(g, h, 2) != nil)
	// Rival 2's Golf Carts are gone; you did not see it, so the news says nothing.
	f := fleet_of(g, h, 2)
	testing.expect(t, f == nil || f.ships[.Golf_Cart] == 0)
	testing.expect(t, g.news == before)
}

@(test)
test_rivals_attack_what_they_saw_was_weaker :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[1].home
	fleet_of(g, h, 1).ships[.Pickup] = 6
	fleet_of(g, h, 1).kit[.Fuel] = 10 // so a star is in reach whatever the layout
	// The rival saw one of yer Golf Carts at a star its Pickups can reach.
	target := NO_STAR
	for i in 0 ..< g.star_count {
		if i != h && !g.stars[i].wormhole && send_problem(g, 1, h, i, only(.Pickup, 6)) == "" {
			target = i
			break
		}
	}
	if !testing.expect(t, target != NO_STAR) {
		return
	}
	rival_fleet(g, target, PLAYER, only(.Golf_Cart, 1))
	g.empires[1].intel[target] = {
		seen     = true,
		owner    = NO_OWNER,
		strength = strength_at(g, target, 1),
	}
	ai_attack(g, 1)
	going := false
	for &f in g.fleets {
		if f.used && f.owner == 1 && f.star == NO_STAR && f.to == target && f.ships[.Pickup] > 0 {
			going = true
		}
	}
	testing.expect(t, going)
}
