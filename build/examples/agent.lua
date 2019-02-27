local skynet = require "skynet"
local socket = require "skynet.socket"
local sproto = require "sproto"
require "dump"

local sprotoloader = require "sprotoloader"
local json_safe = require "cjson.safe"

local WATCHDOG
local host
local send_request

local CMD = {}
local REQUEST = {}
local client_fd

function REQUEST:get()
	print("get", self.what)
	local r = skynet.call("SIMPLEDB", "lua", "get", self.what)
	return { result = r }
end

function REQUEST:set()
	print("set", self.what, self.value)
	dump(self)
	local r = skynet.call("SIMPLEDB", "lua", "set", self.what, self.value)
end

function REQUEST:handshake()
	return { msg = "Welcome to skynet, I will send heartbeat every 5 sec." }
end

function REQUEST:quit()
	skynet.call(WATCHDOG, "lua", "close", client_fd)
end

local function request(msg)
	dump(msg)
	local f = assert(REQUEST[msg.cmd])
	-- dump(REQUEST)
	local r = f(msg.val)
	print("request", r)
	-- if response then
	-- 	return response(r)
	-- end
	return (json_safe.encode(r))
end

local function send_package(pack)
	local package = string.pack(">s2", pack)
	socket.write(client_fd, package)
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		-- local s = string.unpack(">2", msg)
		print("agent unpack: ", msg, sz)
		local str = skynet.tostring(msg, sz)
		-- local t = table.pack(host:dispatch(msg, sz))
		-- dump(t)
		-- return host:dispatch(msg, sz)
		print("unpack", str)
		local reqMsg, err = json_safe.decode(str)
		if err then
			skynet.error(err)
		end
		return "REQUEST", reqMsg
	end,
	dispatch = function (fd, _, type, msg)
		print("=== agent 收到消息", type)
		assert(fd == client_fd)	-- You can use fd to reply message
		skynet.ignoreret()	-- session is fd, don't call skynet.ret
		skynet.trace()
		if type == "REQUEST" then
			local ok, result  = pcall(request, msg)
			if ok then
				if result then
					send_package(result)
				end
			else
				skynet.error(result)
			end
		else
			assert(type == "RESPONSE")
			error "This example doesn't support request client"
		end
	end
}

function CMD.start(conf)
	local fd = conf.client
	local gate = conf.gate
	WATCHDOG = conf.watchdog
	-- slot 1,2 set at main.lua
	host = sprotoloader.load(1):host "package"
	send_request = host:attach(sprotoloader.load(2))
	-- skynet.fork(function()
	-- 	while true do
	-- 		send_package(send_request "heartbeat")
	-- 		skynet.sleep(500)
	-- 	end
	-- end)

	client_fd = fd
	skynet.call(gate, "lua", "forward", fd)
	print("==== agent-start")
end

function CMD.disconnect()
	-- todo: do something before exit
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, command, ...)
		skynet.trace()
		local f = CMD[command]
		skynet.ret(skynet.pack(f(...)))
	end)
end)
