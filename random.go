package chd

import (
	rand "github.com/remerge/go-xorshift"
)

func pickRandom(slice [][]byte) (v []byte) {
	length := len(slice)
	from := rand.Intn(length)
	v = slice[from]
	if len(v) > 0 {
		return v
	}

	for i := 0; i < length; i++ {
		shift := rand.Intn(2)
		if shift == 0 {
			shift = -1
		}
		if v = pickFromSlice(slice, from+(i+1)*shift); len(v) > 0 {
			return v
		}
		shift = shift * -1
		if v = pickFromSlice(slice, from+(i+1)*shift); len(v) > 0 {
			return v
		}

	}
	return nil
}

func pickFromSlice(slice [][]byte, i int) []byte {
	if i < 0 || i >= len(slice) {
		return nil
	}
	return slice[i]
}
