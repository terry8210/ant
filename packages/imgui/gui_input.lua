local gui_input = {}
gui_input.key_state = {}
gui_input.mouse = {}
gui_input.key_down = {}
gui_input.screen_size = {0,0}
local called = {}
gui_input.called = called
function gui_input.mouse_move(x,y)
    local gm = gui_input.mouse
    gm.x = x
    gm.y = y
    called.mouse_move = true
end

function gui_input.mouse_wheel(x,y,delta)
    local gm = gui_input.mouse
    gm.scroll = delta
    gm.x = x
    gm.y = y
    called.mouse_wheel = true
end

function gui_input.mouse_click(x, y, what, pressed)
    local gm = gui_input.mouse
    gm.x = x
    gm.y = y
    gm[what] = pressed
    called[what] = true
    called.mouse_click = true
end

function gui_input.keyboard( key, press, state )
    local gk = gui_input.key_state
    gk.ctrl = (state & 0x1) ~= 0
    gk.alt = (state & 0x2) ~= 0
    gk.shift = (state & 0x4) ~= 0
    gk.sys = (state & 0x8) ~= 0
    table.insert(gui_input.key_down,{key,press})
end

function gui_input.clean()
    called = {}
    gui_input.called = called
    gui_input.key_down = {}

end

function gui_input.size(w,h,t)
    gui_input.screen_size[1] = w
    gui_input.screen_size[2] = h
    gui_input.screen_size["type"] = t
end


return gui_input