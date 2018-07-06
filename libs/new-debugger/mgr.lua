local srv = require 'new-debugger.server'
local json = require 'cjson'
local cdebug = require 'debugger.core'

local workerThreads = cdebug.start('master', function(w, msg)
    local threads = require 'new-debugger.threads'
    local pkg = assert(json.decode(msg))
    if threads[pkg.cmd] then
        threads[pkg.cmd](w, pkg)
    end
end)

local mgr = {}

local seq = 0
local state = 'birth'

function mgr.newSeq()
    seq = seq + 1
    return seq
end

function mgr.sendToClient(pkg)
    return srv.send(pkg)
end

function mgr.sendToWorker(w, pkg)
    return workerThreads:send(w, assert(json.encode(pkg)))
end

function mgr.broadcastToWorker(pkg)
    local msg = assert(json.encode(pkg))
    for w in workerThreads:foreach() do
        workerThreads:send(w, msg)
    end
end

function mgr.threads()
    local t = {}
    for w in workerThreads:foreach() do
        t[#t + 1] = w
    end
    return t
end

function mgr.hasThread(w)
    return workerThreads:exists(w)
end

function mgr.update()
    return workerThreads:update()
end

function mgr.isState(s)
    return state == s
end

function mgr.setState(s)
    state = s
end

return mgr
