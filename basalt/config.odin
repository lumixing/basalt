package basalt

import "core:os"
import "core:encoding/json"

ServerConfig :: struct {
	port:        u16,
	max_players: uint,
	motd:        string,
}

server_config_default :: proc() -> ServerConfig {
	return {
		port = 25565,
		max_players = 69,
		motd = "a minecraft server (i think)",
	}
}

server_config_init :: proc() -> ServerConfig {
	config_data, config_ok := os.read_entire_file("config.json")
	lassert(config_ok, "no config.json found", level = .WARN)

	server_config := server_config_default()
	config_err := json.unmarshal(config_data, &server_config)
	lassert(config_err == nil, "config.json unmarshal error:", config_err)

	return server_config
}
