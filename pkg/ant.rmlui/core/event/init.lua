local rmlui = require "rmlui"
local console = require "core.sandbox.console"
local constructor = require "core.DOM.constructor"
local environment = require "core.environment"
local event = require "core.event"

local function invoke(f, ...)
    local ok, err = xpcall(f, function(msg)
        return debug.traceback(msg)
    end, ...)
    if not ok then
        console.warn(err)
    end
    return ok, err
end

local function OnEventAttach(document, element, source)
    if source == "" then
        return
    end
    local globals = environment[document]
    local code = ("local event;local this=...;return function()%s;end"):format(source)
    local payload, err = load(code, source, "t", globals)
    if not payload then
        console.warn(err)
        return
    end
    local ok, f = invoke(payload, constructor.Element(document, false, element))
    if not ok then
        return
    end
    local upvalue = {}
    local i = 1
    while true do
        local name = debug.getupvalue(f, i)
        if not name then
            break
        end
        upvalue[name] = i
        i = i + 1
    end
    return f, upvalue.event
end

local events = {}

function event.OnCreateElement(document, element)
    local listeners = {}
    for name, value in pairs(rmlui.ElementGetAttributes(element)) do
        if name:sub(1,2) == "on" then
            local f, upvalue = OnEventAttach(document, element, value)
            if f then
                listeners[#listeners+1] = rmlui.ElementAddEventListener(element, name:sub(2,-1), function (e)
                    if upvalue then
                        debug.setupvalue(f, upvalue, constructor.Event(e))
                    end
                    invoke(f)
                end)
            end
        end
    end
    if #listeners > 0 then
        events[element] = listeners
    end
end

function event.OnDestroyNode(_, element)
    for _, listener in pairs(events[element]) do
        rmlui.ElementRemoveEventListener(element, listener)
    end
end
