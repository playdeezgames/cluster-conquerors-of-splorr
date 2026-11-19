package game

// Sound (made in the Anvil: the PLAY texts are in assets/anvil/world.json, the WAVs in assets/sfx). The
// game does not keep a queue in the Game struct (saves copy it whole): each command or tap is looked at
// before and after, and the page plays the one sound that says most about what changed.

Sfx :: enum u8 {
	None,
	Blip, // a move of the cursor or a row, a value changed
	Open, // a screen opened
	Close, // back to the map
	Confirm, // a form filed, a slider locked, ships sent: Enter/OK did something in place
	Turn, // the turn ended
	Hit, // a battle round fought
	Gavel, // the Homeowners' Association meets
	Gain, // a colony settled or taken
	Loss, // a colony lost
	Win,
	Lose,
}

// What the sounds look at, taken before a command or tap.
Sound_Look :: struct {
	mode:     Mode,
	cursor:   int,
	row:      int,
	turn:     int,
	round:    int,
	colonies: int,
	outcome:  Outcome,
}

sound_look :: proc(g: ^Game) -> Sound_Look {
	return {g.mode, g.cursor, g.row, g.turn, g.battle.round, colonies_of(g, PLAYER), g.outcome}
}

// The sound for what changed since `b`; `confirm` when it was Enter/OK, `moved` when a direction or a tap.
sound_after :: proc(b: Sound_Look, g: ^Game, confirm, moved: bool) -> Sfx {
	setting_up := b.mode == .Choose_Race || b.mode == .New_Game || b.mode == .Game_Over
	if !setting_up && g.outcome != b.outcome {
		return g.outcome == .Won ? .Win : .Lose
	}
	if !setting_up {
		n := colonies_of(g, PLAYER)
		if n > b.colonies {
			return .Gain
		}
		if n < b.colonies {
			return .Loss
		}
	}
	if g.mode == .Council && b.mode != .Council {
		return .Gavel
	}
	if g.mode == .Battle && (b.mode != .Battle || g.battle.round != b.round) {
		return .Hit
	}
	if g.turn != b.turn {
		return .Turn
	}
	if g.mode != b.mode {
		return g.mode == .Map ? .Close : .Open
	}
	if confirm {
		return .Confirm
	}
	if moved || g.cursor != b.cursor || g.row != b.row {
		return .Blip
	}
	return .None
}
