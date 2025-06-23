package basalt

import "core:fmt"
import "core:time"
import "core:os/os2"

logs: [dynamic]Log
log_file: ^os2.File

Log :: struct {
	level: LogLevel,
	text:  string,
	time:  time.Time,
}

LogLevel :: enum {
	DEBUG,
	INFO,
	WARN,
	ERROR,
	FATAL,
}

log_level_color :: proc(level: LogLevel) -> [4]f32 {
	switch level {
	case .DEBUG: return {1, 0, 1, 1}
	case .INFO:  return {0, 0, 0, 1}
	case .WARN:  return {1, 1, 0, 1}
	case .ERROR: return {1, 0, 0, 1}
	case .FATAL: return {1, 0, 0, 1}
	}

	unreachable()
}

log_init :: proc() {
	log_err: os2.Error
	os2.remove("latest.log")
	log_file, log_err = os2.open("latest.log", {.Read, .Write, .Create, .Append})
	assert(log_err == nil, "could not open log")
}

log_free :: proc() {
	os2.close(log_file)
	for log in logs {
		delete(log.text)
	}
	delete(logs)
}

llog :: proc(level: LogLevel, args: ..any) {
	log := Log {
		level = level,
		text  = fmt.aprint(..args),
		time  = time.now(),
	}
	append(&logs, log)
	n, err := os2.write_string(log_file, fmt.tprintfln("[%v] [%s] %s", log.time, log.level, log.text))
}

lassert :: proc(cond: bool, args: ..any, level := LogLevel.FATAL) -> bool {
	if !cond do llog(level, ..args)
	return cond
}

ldebug :: proc(args: ..any) { llog(.DEBUG, ..args) }
linfo  :: proc(args: ..any) { llog(.INFO,  ..args) }
lwarn  :: proc(args: ..any) { llog(.WARN,  ..args) }
lerror :: proc(args: ..any) { llog(.ERROR, ..args) }
lfatal :: proc(args: ..any) { llog(.FATAL, ..args) }
