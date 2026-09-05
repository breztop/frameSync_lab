# SPDX-License-Identifier: GPL-3.0-only
class_name FrameRecord
extends RefCounted
## All samples are retained. Only explicitly marked transition samples are
## excluded from the separately reported stable statistics.

var ticks := PackedInt64Array()
var intervals := PackedInt64Array()
var segments := PackedInt32Array()
var stable := PackedByteArray()
var events: Array[Dictionary] = []
var initial_config: Dictionary = {}
var round_id := ""
var start_usec := 0
var previous_usec := 0
var excluded_until := 0
var segment := 0
var active := false
var recent_head := 0


func begin(now: int, config: Dictionary) -> void:
	ticks.clear()
	intervals.clear()
	segments.clear()
	stable.clear()
	events.clear()
	recent_head = 0
	segment = 0
	start_usec = now
	previous_usec = 0
	initial_config = config.duplicate(true)
	round_id = "%s_%d" % [Time.get_datetime_string_from_system().replace(":", "-"), now]
	active = true
	mark(now, "round_start_and_warmup", config, 3000000)


func mark(now: int, kind: String, config: Dictionary, settling_usec: int = 1000000) -> void:
	if not active:
		return
	segment += 1
	excluded_until = maxi(excluded_until, now + settling_usec)
	events.append({"ticks_usec": now, "elapsed_usec": now - start_usec,
		"next_frame": ticks.size() + 1, "segment": segment, "kind": kind,
		"excluded_until_usec": excluded_until, "config": config.duplicate(true)})


func sample(now: int) -> void:
	if not active:
		return
	var gap := now - previous_usec if previous_usec > 0 else 0
	ticks.append(now)
	intervals.append(gap)
	segments.append(segment)
	stable.append(1 if previous_usec >= excluded_until and gap > 0 else 0)
	previous_usec = now
	while recent_head < ticks.size() - 1 and ticks[recent_head] < now - 5000000:
		recent_head += 1


func recent() -> Dictionary:
	var maximum := 0
	var total := 0
	var count := 0
	for i in range(recent_head, ticks.size()):
		if intervals[i] > 0:
			maximum = maxi(maximum, intervals[i])
			total += intervals[i]
			count += 1
	return {"max_ms": maximum / 1000.0,
		"fps": count * 1000000.0 / total if total > 0 else 0.0}


func finish(now: int, config: Dictionary) -> void:
	mark(now, "round_end", config, 0)
	active = false


static func summarize(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"interval_count": 0, "average_update_fps": null,
			"p50_ms": null, "p95_ms": null, "p99_ms": null, "max_ms": null,
			"over_33_3_ms": 0, "over_100_ms": 0, "over_200_ms": 0}
	values.sort()
	var total := 0
	var over33 := 0
	var over100 := 0
	var over200 := 0
	for value in values:
		total += value
		over33 += int(value > 33300)
		over100 += int(value > 100000)
		over200 += int(value > 200000)
	var count := values.size()
	return {"interval_count": count, "duration_seconds": total / 1000000.0,
		"average_update_fps": count * 1000000.0 / total,
		"p50_ms": values[ceili(count * 0.50) - 1] / 1000.0,
		"p95_ms": values[ceili(count * 0.95) - 1] / 1000.0,
		"p99_ms": values[ceili(count * 0.99) - 1] / 1000.0,
		"max_ms": values[-1] / 1000.0,
		"over_33_3_ms": over33, "over_100_ms": over100, "over_200_ms": over200}
