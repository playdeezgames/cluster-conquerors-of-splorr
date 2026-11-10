package game

// A small deterministic generator (splitmix64), so a cluster made from a seed is the same on wasm and
// native and the same every time it is regenerated. splitmix has no bad state, so any seed works.

Rng :: struct {
	state: u64,
}

rng_next :: proc(r: ^Rng) -> u64 {
	r.state += 0x9E3779B97F4A7C15
	z := r.state
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// A whole number in [0, n); n must be positive and fit in an int on wasm (32 bits).
rng_int :: proc(r: ^Rng, n: int) -> int {
	assert(n > 0)
	return int(rng_next(r) % u64(n))
}

// A whole number in [lo, hi].
rng_range :: proc(r: ^Rng, lo, hi: int) -> int {
	return lo + rng_int(r, hi - lo + 1)
}

// Picks an index from a table of weights.
rng_weighted :: proc(r: ^Rng, weights: []int) -> int {
	total := 0
	for w in weights {
		total += w
	}
	roll := rng_int(r, total)
	for w, i in weights {
		if roll < w {
			return i
		}
		roll -= w
	}
	return len(weights) - 1
}
