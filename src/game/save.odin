package game

// Saves (slice 1 step 9): the whole game, as it is, in one block of bytes behind a small header. The
// game holds no pointers but the stars' names, which a load points back at the name list. The page
// keeps the block in localStorage; a save from a different build (another size or version) is ignored
// and a new cluster starts.

SAVE_MAGIC :: u32(0x5343_4343) // "CCCS"
SAVE_VERSION :: u32(6) // 2: slice 2 step 1 (grudges); 3: step 2 (forms); 4: step 3 (alliances, trade); 5: step 4 (the Watch); 6: step 5 (framing)

Save_Header :: struct {
	magic:   u32,
	version: u32,
	size:    u32,
}

SAVE_SIZE :: size_of(Save_Header) + size_of(Game)

// Writes the game into `out` (at least SAVE_SIZE bytes); returns the bytes written.
write_save :: proc(g: ^Game, out: []u8) -> int {
	if len(out) < SAVE_SIZE {
		return 0
	}
	h := Save_Header{SAVE_MAGIC, SAVE_VERSION, u32(size_of(Game))}
	copy(out[:size_of(Save_Header)], (cast([^]u8)&h)[:size_of(Save_Header)])
	copy(out[size_of(Save_Header):SAVE_SIZE], (cast([^]u8)g)[:size_of(Game)])
	return SAVE_SIZE
}

// Reads a save back into the game; false (and the game untouched) if it is not one of this build's.
read_save :: proc(g: ^Game, data: []u8) -> bool {
	if len(data) != SAVE_SIZE {
		return false
	}
	h: Save_Header
	copy((cast([^]u8)&h)[:size_of(Save_Header)], data[:size_of(Save_Header)])
	if h.magic != SAVE_MAGIC || h.version != SAVE_VERSION || int(h.size) != size_of(Game) {
		return false
	}
	loaded := new(Game)
	defer free(loaded)
	copy((cast([^]u8)loaded)[:size_of(Game)], data[size_of(Save_Header):])
	if loaded.star_count <= 0 || loaded.star_count > MAX_STARS || loaded.empire_count != MAX_EMPIRES {
		return false
	}
	for i in 0 ..< loaded.star_count {
		s := &loaded.stars[i]
		switch {
		case s.name_id == CLUBHOUSE_NAME:
			s.name = "The Clubhouse"
		case s.name_id >= 0 && s.name_id < len(STAR_NAMES):
			s.name = STAR_NAMES[s.name_id]
		case:
			return false
		}
	}
	for i in loaded.star_count ..< MAX_STARS {
		loaded.stars[i].name = ""
	}
	g^ = loaded^
	return true
}
