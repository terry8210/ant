local rmlui = require "rmlui"
local event = require "core.event"
local timer = require "core.timer"
local task = require "core.task"
local contextManager = require "core.contextManager"
local windowManager = require "core.windowManager"
local constructor = require "core.DOM.constructor"
local datamodel = require "core.datamodel.api"

local function createWindow(document, source)
    --TODO: pool
    local window = {}
    local timer_object = setmetatable({}, {__mode = "k"})
    function window.createModel(view)
        return datamodel.create(document, view)
    end
    function window.open(url)
        local newdoc = contextManager.open(url)
        if not newdoc then
            return
        end
        contextManager.onload(newdoc)
        return createWindow(newdoc, document)
    end
    function window.close()
        task.new(function ()
            contextManager.close(document)
            for t in pairs(timer_object) do
                t:remove()
            end
        end)
    end
    function window.show()
        contextManager.show(document)
    end
    function window.hide()
        contextManager.hide(document)
    end
    function window.flush()
        contextManager.flush(document)
    end
    function window.setTimeout(f, delay)
        local t = timer.wait(delay, f)
        timer_object[t] = true
        return t
    end
    function window.setInterval(f, delay)
        local t = timer.loop(delay, f)
        timer_object[t] = true
        return t
    end
    function window.clearTimeout(t)
        t:remove()
    end
    function window.clearInterval(t)
        t:remove()
    end
    function window.addEventListener(type, listener, useCapture)
        rmlui.ElementAddEventListener(rmlui.DocumentGetBody(document), type, function(e) listener(constructor.Event(e)) end, useCapture)
    end
    function window.postMessage(data)
        rmlui.ElementDispatchEvent(rmlui.DocumentGetBody(document), "message", {
            source = source,
            data = data,
        })
    end
    if source == nil then
        window.extern = {
            postMessage = function (data)
                return windowManager.postExternMessage(document, data)
            end
        }
    end
    local ctors = {}
    local customElements = {}
    function customElements.define(name, ctor)
        if ctors[name] then
            error "Already contains a custom element with the same name."
        end
        if not name:match "[a-z][0-9a-z_%-]*" then
            error "Invalid custom element name."
        end
        if type(ctor) ~= "function" then
            error "Invalid constructor."
        end
        ctors[name] = ctor
    end
    function customElements.get(name)
        return ctors[name]
    end
    window.customElements = customElements
    local mt = {}
    function mt:__newindex(name, f)
        if name == "onload" then
            rawset(self, "onload", f)
            self.addEventListener("load", f)
        end
    end
    return setmetatable(window, mt)
end

function event.OnDocumentCreate(document, globals)
    globals.window = createWindow(document)
end

return createWindow
