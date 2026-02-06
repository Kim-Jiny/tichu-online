class_name CardValidator

# Client-side card combo pre-validation (mirrors server logic for UX)

enum ComboType {
	INVALID,
	SINGLE,
	PAIR,
	TRIPLE,
	STRAIGHT,
	FULL_HOUSE,
	STEPS,
	BOMB_FOUR,
	BOMB_STRAIGHT_FLUSH,
	DOG,
}

const RANK_VALUES := {
	"2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
	"9": 9, "10": 10, "J": 11, "Q": 12, "K": 13, "A": 14,
}

static func get_card_value(card_id: String) -> float:
	if card_id == "special_bird": return 1
	if card_id == "special_dog": return 0
	if card_id == "special_phoenix": return -1
	if card_id == "special_dragon": return 15
	var parts := card_id.split("_")
	if parts.size() >= 2:
		return float(RANK_VALUES.get(parts[1], 0))
	return 0

static func get_combo_type(card_ids: Array) -> Dictionary:
	if card_ids.is_empty():
		return {"type": ComboType.INVALID}

	# Dog
	if card_ids.size() == 1 and card_ids[0] == "special_dog":
		return {"type": ComboType.DOG, "value": 0}

	if card_ids.has("special_dog"):
		return {"type": ComboType.INVALID}

	var has_phoenix := card_ids.has("special_phoenix")
	var normal_cards: Array = card_ids.filter(func(c): return c != "special_phoenix")

	# Single
	if card_ids.size() == 1:
		return {"type": ComboType.SINGLE, "value": get_card_value(card_ids[0])}

	# Pair
	if card_ids.size() == 2:
		if has_phoenix and normal_cards.size() == 1:
			if not normal_cards[0].begins_with("special_"):
				return {"type": ComboType.PAIR, "value": get_card_value(normal_cards[0])}
		elif normal_cards.size() == 2:
			var v1 := get_card_value(normal_cards[0])
			var v2 := get_card_value(normal_cards[1])
			if v1 == v2 and not normal_cards[0].begins_with("special_") and not normal_cards[1].begins_with("special_"):
				return {"type": ComboType.PAIR, "value": v1}

	# Triple
	if card_ids.size() == 3:
		var values: Array = normal_cards.map(func(c): return get_card_value(c))
		if has_phoenix and normal_cards.size() == 2:
			if values[0] == values[1] and not normal_cards[0].begins_with("special_"):
				return {"type": ComboType.TRIPLE, "value": values[0]}
		elif normal_cards.size() == 3:
			if values[0] == values[1] and values[1] == values[2] and not normal_cards[0].begins_with("special_"):
				return {"type": ComboType.TRIPLE, "value": values[0]}

	# 4 cards: bomb or steps
	if card_ids.size() == 4:
		if not has_phoenix:
			var values: Array = normal_cards.map(func(c): return get_card_value(c))
			if values[0] == values[1] and values[1] == values[2] and values[2] == values[3]:
				if not normal_cards[0].begins_with("special_"):
					return {"type": ComboType.BOMB_FOUR, "value": values[0]}

	# 5+ cards: straight, full house, steps, straight flush bomb
	if card_ids.size() >= 5:
		# Check straight flush bomb
		if not has_phoenix:
			var sf := _check_straight_flush(normal_cards)
			if sf.get("type") == ComboType.BOMB_STRAIGHT_FLUSH:
				return sf

		# Full house (5 cards)
		if card_ids.size() == 5:
			var fh := _check_full_house(normal_cards, has_phoenix)
			if fh.get("type") == ComboType.FULL_HOUSE:
				return fh

	# Straight (5+)
	if card_ids.size() >= 5:
		var st := _check_straight(normal_cards, has_phoenix, card_ids.size())
		if st.get("type") == ComboType.STRAIGHT:
			return st

	# Steps (4, 6, 8...)
	if card_ids.size() >= 4 and card_ids.size() % 2 == 0:
		var steps := _check_steps(normal_cards, has_phoenix, card_ids.size())
		if steps.get("type") == ComboType.STEPS:
			return steps

	return {"type": ComboType.INVALID}

static func _check_straight_flush(cards: Array) -> Dictionary:
	if cards.size() < 5:
		return {"type": ComboType.INVALID}
	# All same suit
	var suits: Array = cards.map(func(c):
		if c.begins_with("special_"): return "special"
		return c.split("_")[0])
	if not suits.all(func(s): return s == suits[0]):
		return {"type": ComboType.INVALID}
	if suits[0] == "special":
		return {"type": ComboType.INVALID}

	var values: Array = cards.map(func(c): return get_card_value(c))
	values.sort()
	for i in range(1, values.size()):
		if values[i] != values[i - 1] + 1:
			return {"type": ComboType.INVALID}
	return {"type": ComboType.BOMB_STRAIGHT_FLUSH, "value": values[values.size() - 1]}

static func _check_full_house(normal_cards: Array, has_phoenix: bool) -> Dictionary:
	var value_counts := {}
	for c in normal_cards:
		var v := get_card_value(c)
		value_counts[v] = value_counts.get(v, 0) + 1

	var entries: Array = []
	for v in value_counts:
		entries.append({"value": v, "count": value_counts[v]})

	if has_phoenix:
		if entries.size() == 2:
			var c1: int = entries[0]["count"]
			var c2: int = entries[1]["count"]
			var v1: float = entries[0]["value"]
			var v2: float = entries[1]["value"]
			if c1 == 3 and c2 == 1: return {"type": ComboType.FULL_HOUSE, "value": v1}
			if c1 == 1 and c2 == 3: return {"type": ComboType.FULL_HOUSE, "value": v2}
			if c1 == 2 and c2 == 2: return {"type": ComboType.FULL_HOUSE, "value": maxf(v1, v2)}
	else:
		if entries.size() == 2:
			var c1: int = entries[0]["count"]
			var c2: int = entries[1]["count"]
			var v1: float = entries[0]["value"]
			var v2: float = entries[1]["value"]
			if c1 == 3 and c2 == 2: return {"type": ComboType.FULL_HOUSE, "value": v1}
			if c1 == 2 and c2 == 3: return {"type": ComboType.FULL_HOUSE, "value": v2}

	return {"type": ComboType.INVALID}

static func _check_straight(normal_cards: Array, has_phoenix: bool, total_length: int) -> Dictionary:
	if total_length < 5:
		return {"type": ComboType.INVALID}
	# No dragon/dog in straights
	for c in normal_cards:
		if c == "special_dragon" or c == "special_dog":
			return {"type": ComboType.INVALID}

	var values: Array = normal_cards.map(func(c): return get_card_value(c))
	values.sort()

	if not has_phoenix:
		var unique: Array = []
		for v in values:
			if not unique.has(v):
				unique.append(v)
		if unique.size() != total_length:
			return {"type": ComboType.INVALID}
		for i in range(1, unique.size()):
			if unique[i] != unique[i - 1] + 1:
				return {"type": ComboType.INVALID}
		return {"type": ComboType.STRAIGHT, "value": unique[unique.size() - 1]}
	else:
		var unique: Array = []
		for v in values:
			if not unique.has(v):
				unique.append(v)
		if unique.size() != normal_cards.size():
			return {"type": ComboType.INVALID}
		if unique.size() + 1 != total_length:
			return {"type": ComboType.INVALID}
		unique.sort()
		var gaps := 0
		for i in range(1, unique.size()):
			var diff: float = unique[i] - unique[i - 1]
			if diff == 1: continue
			if diff == 2: gaps += 1
			else: return {"type": ComboType.INVALID}
		if gaps <= 1:
			var high_value: float = unique[unique.size() - 1]
			if gaps == 0:
				high_value = unique[unique.size() - 1] + 1
				if high_value > 14:
					high_value = unique[unique.size() - 1]
			return {"type": ComboType.STRAIGHT, "value": high_value}

	return {"type": ComboType.INVALID}

static func _check_steps(normal_cards: Array, has_phoenix: bool, total_length: int) -> Dictionary:
	if total_length % 2 != 0 or total_length < 4:
		return {"type": ComboType.INVALID}
	var num_pairs: int = total_length / 2

	var value_counts := {}
	for c in normal_cards:
		var v := get_card_value(c)
		value_counts[v] = value_counts.get(v, 0) + 1

	var entries: Array = []
	for v in value_counts:
		entries.append({"value": v, "count": value_counts[v]})
	entries.sort_custom(func(a, b): return a["value"] < b["value"])

	if has_phoenix:
		var phoenix_used := false
		var pairs: Array = []
		for e in entries:
			if e["count"] == 2:
				pairs.append(e["value"])
			elif e["count"] == 1 and not phoenix_used:
				pairs.append(e["value"])
				phoenix_used = true
			else:
				return {"type": ComboType.INVALID}
		if pairs.size() != num_pairs:
			return {"type": ComboType.INVALID}
		pairs.sort()
		for i in range(1, pairs.size()):
			if pairs[i] != pairs[i - 1] + 1:
				return {"type": ComboType.INVALID}
		return {"type": ComboType.STEPS, "value": pairs[pairs.size() - 1]}
	else:
		if entries.size() != num_pairs:
			return {"type": ComboType.INVALID}
		for e in entries:
			if e["count"] != 2:
				return {"type": ComboType.INVALID}
		for i in range(1, entries.size()):
			if entries[i]["value"] != entries[i - 1]["value"] + 1:
				return {"type": ComboType.INVALID}
		return {"type": ComboType.STEPS, "value": entries[entries.size() - 1]["value"]}

static func get_combo_name(combo_type: ComboType) -> String:
	match combo_type:
		ComboType.SINGLE: return "싱글"
		ComboType.PAIR: return "페어"
		ComboType.TRIPLE: return "트리플"
		ComboType.STRAIGHT: return "스트레이트"
		ComboType.FULL_HOUSE: return "풀하우스"
		ComboType.STEPS: return "연속 페어"
		ComboType.BOMB_FOUR: return "폭탄 (4장)"
		ComboType.BOMB_STRAIGHT_FLUSH: return "폭탄 (스트레이트 플러시)"
		ComboType.DOG: return "개"
	return "유효하지 않음"
