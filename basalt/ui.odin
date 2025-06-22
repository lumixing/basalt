package basalt

import "core:fmt"

import im "../odin-imgui"
import "../odin-imgui/imgui_impl_glfw"
import "../odin-imgui/imgui_impl_opengl3"
import "vendor:glfw"
import gl "vendor:OpenGL"

DISABLE_DOCKING :: #config(DISABLE_DOCKING, false)

window: glfw.WindowHandle

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

		style := im.GetStyle()
		style.WindowRounding = 0
		style.Colors[im.Col.WindowBg].w = 1
	}

	im.StyleColorsLight()

	imgui_impl_glfw.InitForOpenGL(window, true)
	imgui_impl_opengl3.Init("#version 150")
}

ui_loop :: proc() {
	@(static) show_timestamps := false

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

		if im.Begin("logger") {
			im.Checkbox("show timestamps", &show_timestamps)
			im.Separator()
			if im.BeginChild("logger_scroll", window_flags = {.HorizontalScrollbar}) {
				for log in logs {
					if show_timestamps {
						im.Text("[%ld]", log.time._nsec / 1_000_000)
						im.SameLine()
					}
					if log.level == .FATAL {
						im.TextColored(log_level_color(log.level), "!!!")
						im.SameLine()
					}
					im.TextColored(log_level_color(log.level), "%s", log.text)
				}
			}
			if im.GetScrollY() >= im.GetScrollMaxY() {
				im.SetScrollHereY(1)
			}
			im.EndChild()
		}
		im.End()

		if im.Begin("clients") {
			im.Text("%d clients", len(clients))
			im.Separator()
			if im.BeginChild("clients_scrol", window_flags = {.HorizontalScrollbar}) {
				for client_end, client in clients {
					im.Text("%ld (%d.%d.%d.%d:%d)", client_end, client_end.ip0, client_end.ip1, client_end.ip2, client_end.ip3, client_end.port)
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
