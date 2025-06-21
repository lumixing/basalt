package basalt

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:net"
import "core:thread"
import "core:reflect"
import "core:encoding/endian"
import "core:encoding/json"

import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"
import "vendor:glfw"
import gl "vendor:OpenGL"

DISABLE_DOCKING :: #config(DISABLE_DOCKING, false)

RECV_BUFFER_SIZE :: 4096
VERSION          :: "1.8.9"
PACKET_PROTOCOL  :: 47

PORT           :: 25565
ONLINE_PLAYERS :: 0
MAX_PLAYERS    :: 69
MOTD           :: "awesome awesome awesome!!1"

window: glfw.WindowHandle

packets: [dynamic]union {
	ServerBoundPacket,
	ClientBoundPacket,
}

ui_deinit :: proc() {
	defer glfw.Terminate()
	defer glfw.DestroyWindow(window)
	defer im.DestroyContext()
	defer imgui_impl_glfw.Shutdown()
	defer imgui_impl_opengl3.Shutdown()
}

ui_init :: proc() {
	assert(cast(bool)glfw.Init())

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1) // i32(true)

	window = glfw.CreateWindow(800, 600, "basalt view", nil, nil)
	assert(window != nil)

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1) // vsync

	gl.load_up_to(3, 2, proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetProcAddress(name)
	})

	im.CHECKVERSION()
	im.CreateContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
	when !DISABLE_DOCKING {
		io.ConfigFlags += {.DockingEnable}
		// io.ConfigFlags += {.ViewportsEnable}

		style := im.GetStyle()
		style.WindowRounding = 0
		style.Colors[im.Col.WindowBg].w = 1
	}

	// im.StyleColorsDark()
	im.StyleColorsLight()

	imgui_impl_glfw.InitForOpenGL(window, true)
	imgui_impl_opengl3.Init("#version 150")
}

ui_loop :: proc() {
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}

		imgui_impl_opengl3.NewFrame()
		imgui_impl_glfw.NewFrame()
		im.NewFrame()

		im.DockSpaceOverViewport()

		im.ShowDemoWindow()

		if im.Begin("packets") {
			if im.BeginChild("scrolling", window_flags = {.HorizontalScrollbar}) {
				for p, p_idx in packets {
					switch pp in p {
					case ServerBoundPacket:
						tt := reflect.union_variant_type_info(pp)
						name := fmt.ctprintf("%s", tt)
						// im.Text(fmt.ctprintf("recv %v", p))
						id := fmt.ctprintf("p%d", p_idx)
						im.PushID(id)
						if im.TreeNode(name) {
							for field in reflect.struct_fields_zipped(tt.id) {
								im.Text(fmt.ctprintf("%s -> %v", field.name, reflect.struct_field_value(p, field)))
							}
							im.TreePop()
						}
						im.PopID()
					case ClientBoundPacket:
						tt := reflect.union_variant_type_info(pp)
						name := fmt.ctprintf("%s", tt)
						// im.Text(fmt.ctprintf("recv %v", p))
						id := fmt.ctprintf("p%d", p_idx)
						im.PushID(id)
						if im.TreeNode(name) {
							for field in reflect.struct_fields_zipped(tt.id) {
								im.Text(fmt.ctprintf("%s -> %v", field.name, reflect.struct_field_value(p, field)))
							}
							im.TreePop()
						}
						im.PopID()
					}
				}
			}
			if im.GetScrollY() >= im.GetScrollMaxY() {
				im.SetScrollHereY(1)
			}
			im.EndChild()
		}
		im.End()

		im.Render()
		display_w, display_h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, display_w, display_h)
		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())

		when !DISABLE_DOCKING {
			backup_current_window := glfw.GetCurrentContext()
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
			glfw.MakeContextCurrent(backup_current_window)
		}

		glfw.SwapBuffers(window)
	}
}

main :: proc() {
	context.logger = log.create_console_logger(.Debug, {.Level})

	ui_init()
	defer ui_deinit()

	defer delete(packets)

	listen_socket, listen_err := net.listen_tcp({
		address = net.IP4_Loopback,
		port = PORT,
	})

	if listen_err != nil {
		log.panic("Could not init listen socket:", listen_err)
	}

	defer net.close(listen_socket)

	log.info("Server listening on port", PORT)
	defer log.info("Server stopped listening")

	thread.create_and_start_with_poly_data(listen_socket, thread_loop)

	ui_loop()
}

thread_loop :: proc(listen_socket: net.TCP_Socket) {
	for {
		client_socket, client_endpoint, accept_err := net.accept_tcp(listen_socket)

		if accept_err != nil {
			log.panic("Could not accept listen socket:", accept_err)
		}

		log.debug("New connection:", client_endpoint)

		thread_data := HandleClientData {
			client_socket = client_socket,
			ctx = context,
		}

		thread.create_and_start_with_poly_data(&thread_data, handle_client)
	}
}

HandleClientData :: struct {
	client_socket: net.TCP_Socket,
	ctx:           runtime.Context, // used for logging
}

handle_client :: proc(thread_data: ^HandleClientData) {
	context = thread_data.ctx
	defer net.close(thread_data.client_socket)

	recv_buffer: [RECV_BUFFER_SIZE]u8

	for {
		bytes_read, read_err := net.recv(thread_data.client_socket, recv_buffer[:])

		if read_err != nil {
			log.error("Could not receive data or client disconnected:", read_err)
			break
		}

		if bytes_read == 0 {
			log.debug("Client disconnected")
			break
		}

		log.debugf("Received %d bytes", bytes_read)
		log.debug(recv_buffer[:bytes_read])

		sbp, sbp_err := sbp_decode(recv_buffer[:bytes_read])
		if sbp_err != nil {
			log.error("Could not parse SBP:", sbp_err)
			break
		}

		append(&packets, sbp)

		log.debug(sbp)

		switch p in sbp {
		case SBP_Handshake:
			state = p.next_state
		case SBP_Request:
			handshake_response := HandshakeResponse {
				version = {
					name     = VERSION,
					protocol = PACKET_PROTOCOL,
				},
				players = {
					online = ONLINE_PLAYERS,
					max    = MAX_PLAYERS,
				},
				description = {
					text = MOTD,
				},
			}
			json_str, json_err := json.marshal(handshake_response)
			if json_err != nil {
				log.error("Could not marshal handshake response:", json_err)
				break
			}
			res := CBP_Response {
				json = string(json_str),
			}
			append(&packets, ClientBoundPacket(res))
			log.debug(res)
			res_packet := cbp_encode(res)
			defer delete(res_packet)
			
			bytes_sent, send_err := net.send_tcp(thread_data.client_socket, res_packet[:])
			if send_err != nil {
				log.error("Could not send data:", send_err)
				break
			}

			log.debugf("Sending %d bytes", bytes_sent)
			log.debug(res_packet[:bytes_sent])
		case SBP_Ping:
			res := CBP_Pong {
				payload = p.payload,
			}
			append(&packets, ClientBoundPacket(res))
			log.debug(res)
			res_packet := cbp_encode(res)
			defer delete(res_packet)
			
			bytes_sent, send_err := net.send_tcp(thread_data.client_socket, res_packet[:])
			if send_err != nil {
				log.error("Could not send data:", send_err)
				break
			}

			log.debugf("Sending %d bytes", bytes_sent)
			log.debug(res_packet[:bytes_sent])
		}
	}
}
