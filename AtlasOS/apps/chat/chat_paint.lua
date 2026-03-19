--[[
  Chat — servers + channels on LuaMade net.openChannel / sendChannel / receiveChannel.
]]

local CACHE = "__AtlasOS_chat_paint_factory"
local factory = _G[CACHE]
if not factory then
	factory = function(ctx)
		local UI = ctx.UI
		local window = ctx.window
		local widgets = ctx.widgets
		local atlasgfx = ctx.atlasgfx
		local appkit = dofile("/home/lib/appkit.lua")
		local chatnet = dofile("/home/lib/atlas_chat_net.lua")

		local STORE = "/etc/AtlasOS/chat_app_state.json"
		local net = rawget(_G, "net")

		local st = {
			servers = {},
			sel_srv = 1,
			sel_ch = 1,
			lines = {},
			line_cache = {},
			compose = "",
			prompt = nil,
			status = "",
			net_open = nil,
			srv_scroll = 1,
			ch_scroll = 1,
		}

		local function save_state()
			local payload = { servers = st.servers }
			for _, s in ipairs(st.servers) do
				if type(s.channels) ~= "table" then s.channels = { "general" } end
			end
			if not fs or not fs.write then return end
			pcall(fs.makeDir, "/etc/AtlasOS")
			local json = require("json")
			pcall(fs.write, STORE, json.encode(payload))
		end

		local function load_state()
			st.servers = {}
			if not fs or not fs.read then return end
			local ok, raw = pcall(fs.read, STORE)
			if not ok or type(raw) ~= "string" or raw == "" then return end
			local json = require("json")
			local ok2, t = pcall(json.decode, raw)
			if ok2 and type(t) == "table" and type(t.servers) == "table" then
				st.servers = t.servers
			end
		end

		local function default_servers()
			if #st.servers == 0 then
				st.servers = {
					{ name = "public", password = "", channels = { "general", "help" } },
				}
				save_state()
			end
		end

		local function cache_key()
			local srv = st.servers[st.sel_srv]
			if not srv then return nil end
			local ch = srv.channels[st.sel_ch]
			if not ch then return nil end
			return chatnet.channel_name(srv.name, srv.password, ch)
		end

		local function close_net()
			if st.net_open and net and net.closeChannel then
				pcall(net.closeChannel, st.net_open.full)
			end
			st.net_open = nil
		end

		local function open_net_current()
			close_net()
			if not net or not net.openChannel then
				st.status = "No net API."
				return
			end
			local srv = st.servers[st.sel_srv]
			if not srv then return end
			if type(srv.channels) ~= "table" then srv.channels = { "general" } end
			local ch = srv.channels[st.sel_ch]
			if not ch then return end
			local full = chatnet.channel_name(srv.name, srv.password, ch)
			local pass = srv.password or ""
			local ok = pcall(net.openChannel, full, pass)
			st.net_open = { full = full, pass = pass }
			st.status = (ok and "Joined: " or "Open failed: ") .. full:sub(1, math.min(40, #full))
		end

		local function stash_lines()
			local k = cache_key()
			if k then st.line_cache[k] = st.lines end
		end

		local function apply_selection()
			stash_lines()
			local k = cache_key()
			st.lines = (k and st.line_cache[k]) or {}
			open_net_current()
		end

		local function ensure_selection()
			st.sel_srv = math.max(1, math.min(st.sel_srv, #st.servers))
			local srv = st.servers[st.sel_srv]
			if not srv then return end
			if type(srv.channels) ~= "table" or #srv.channels == 0 then
				srv.channels = { "general" }
			end
			st.sel_ch = math.max(1, math.min(st.sel_ch, #srv.channels))
		end

		local function display_nick()
			local ok, ap = pcall(dofile, "/home/lib/atlasprofile.lua")
			if ok and ap and ap.display_name then
				local n = ap.display_name()
				if type(n) == "string" and n ~= "" then return n:sub(1, 28) end
			end
			if net and net.getHostname then
				local ok2, h = pcall(net.getHostname)
				if ok2 and type(h) == "string" and h ~= "" then return h:sub(1, 28) end
			end
			return "guest"
		end

		local function drain_net()
			if not (net and st.net_open and net.hasChannelMessage and net.receiveChannel) then return end
			local full = st.net_open.full
			while true do
				local has = false
				local okh, hh = pcall(net.hasChannelMessage, full)
				if okh and hh == true then has = true end
				if not has then break end
				local ok, m = pcall(net.receiveChannel, full)
				if not ok or not m then break end
				local raw = chatnet.msg_content(m)
				local dec = chatnet.decode_chat(raw)
				local from = dec and dec.nick or chatnet.msg_sender(m)
				local txt = dec and dec.text or tostring(raw or ""):sub(1, 240)
				st.lines[#st.lines + 1] = "[" .. from .. "] " .. txt
				while #st.lines > 400 do
					table.remove(st.lines, 1)
				end
			end
		end

		local function send_compose()
			if not st.compose or st.compose:gsub("%s", "") == "" then return end
			if not (net and st.net_open and net.sendChannel) then
				st.status = "Not connected."
				return
			end
			local payload = chatnet.encode_chat(display_nick(), st.compose)
			pcall(net.sendChannel, st.net_open.full, st.net_open.pass or "", payload)
			st.compose = ""
		end

		local function handle_prompt_enter()
			local p = st.prompt
			if not p then return false end
			local line = st.compose
			st.compose = ""
			if p.step == "name" then
				line = line:gsub("^%s+", ""):gsub("%s+$", "")
				if line == "" then
					st.prompt = nil
					st.status = "Join cancelled."
					return true
				end
				p.name = line
				p.step = "pass"
				st.status = "Password (empty = public); Enter to continue:"
				return true
			end
			if p.step == "pass" then
				st.servers[#st.servers + 1] = {
					name = p.name,
					password = line,
					channels = { "general" },
				}
				st.sel_srv = #st.servers
				st.sel_ch = 1
				st.prompt = nil
				save_state()
				ensure_selection()
				apply_selection()
				st.status = "Joined server " .. st.servers[st.sel_srv].name
				return true
			end
			if p.step == "chname" then
				line = line:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 24)
				if line ~= "" then
					local srv = st.servers[st.sel_srv]
					if srv then
						srv.channels[#srv.channels + 1] = line
						st.sel_ch = #srv.channels
						save_state()
						apply_selection()
						st.status = "Channel #" .. line
					end
				end
				st.prompt = nil
				return true
			end
			st.prompt = nil
			return true
		end

		load_state()
		default_servers()
		ensure_selection()

		local shell = appkit.shell({
			on_command = function(id)
				if id == "chat:join_srv" then
					st.prompt = { step = "name" }
					st.status = "New server name, then Enter:"
				elseif id == "chat:add_ch" then
					if #st.servers == 0 then return end
					st.prompt = { step = "chname" }
					st.status = "New channel name, Enter:"
				elseif id == "chat:rm_srv" then
					if #st.servers < 2 then
						st.status = "Cannot remove last server."
					else
						table.remove(st.servers, st.sel_srv)
						st.sel_srv = math.min(st.sel_srv, #st.servers)
						st.sel_ch = 1
						save_state()
						ensure_selection()
						apply_selection()
					end
				elseif id == "chat:rm_ch" then
					local srv = st.servers[st.sel_srv]
					if not srv or not srv.channels or #srv.channels < 2 then
						st.status = "Cannot remove last channel."
					else
						table.remove(srv.channels, st.sel_ch)
						st.sel_ch = math.min(st.sel_ch, #srv.channels)
						save_state()
						ensure_selection()
						apply_selection()
					end
				elseif id == "chat:clear_local" then
					st.lines = {}
					local k = cache_key()
					if k then st.line_cache[k] = {} end
				end
				UI.redraw()
			end,
		})
		shell:set_menubar({
			{
				label = "Server",
				items = {
					{ label = "Join server…", id = "chat:join_srv" },
					{ label = "Remove server", id = "chat:rm_srv" },
				},
			},
			{
				label = "Channel",
				items = {
					{ label = "Add channel…", id = "chat:add_ch" },
					{ label = "Remove channel", id = "chat:rm_ch" },
				},
			},
			{ label = "View", items = { { label = "Clear local log", id = "chat:clear_local" } } },
		})

		return function(win)
			shell:attach(win)
			win._atlas_input_text_active = function()
				return true
			end

			win._atlas_on_key = function(e)
				if not e or e.down ~= true then return false end
				local key = tonumber(e.key) or 0
				if key == 1 and st.prompt then
					st.prompt = nil
					st.compose = ""
					st.status = "Cancelled."
					return true
				end
				if key == 28 or key == 257 then
					if st.prompt then
						return handle_prompt_enter()
					end
					send_compose()
					return true
				end
				if key == 259 or key == 14 then
					st.compose = st.compose:sub(1, math.max(0, #st.compose - 1))
					return true
				end
				if e.ctrl or e.alt then return false end
				local ch = e.char
				if type(ch) == "string" and ch ~= "" then
					local b = ch:byte(1)
					if b and b >= 32 and b < 127 and #st.compose < 480 then
						st.compose = st.compose .. ch
					end
					return true
				end
				return false
			end

			win._atlas_client_click = function(rcx, rcy)
				local zones = win._chat_hit or {}
				for _, z in ipairs(zones) do
					if rcx >= z.x0 and rcx <= z.x1 and rcy >= z.y0 and rcy <= z.y1 then
						if z.kind == "srv" and z.idx then
							st.sel_srv = z.idx
							st.sel_ch = 1
							ensure_selection()
							apply_selection()
							return true
						end
						if z.kind == "ch" and z.idx then
							st.sel_ch = z.idx
							ensure_selection()
							apply_selection()
							return true
						end
					end
				end
				return false
			end

			st.sel_srv = st.sel_srv or 1
			ensure_selection()
			if not win._chat_inited then
				win._chat_inited = true
				apply_selection()
			end

			drain_net()

			shell:paint_decorations(win)
			local cr = shell:content_row()
			local cw, ch = win:client_w(), win:client_h()
			local status_row = ch - 2
			local input_row = ch - 1
			local hdr = 2
			local row0 = cr + hdr
			local list_bottom = ch - 3
			local max_rows = math.max(0, list_bottom - row0 + 1)
			if max_rows < 1 then
				shell:paint_dropdown(win)
				return
			end

			local w_srv = (cw >= 44) and 14 or math.max(8, math.floor(cw * 0.28))
			local w_ch = (cw >= 44) and 14 or math.max(8, math.floor(cw * 0.28))
			if w_srv + w_ch + 12 > cw then
				w_srv = math.min(w_srv, 10)
				w_ch = math.min(w_ch, 10)
			end
			local msg_x = w_srv + w_ch

			win._chat_hit = {}
			local function add_hit(z)
				win._chat_hit[#win._chat_hit + 1] = z
			end

			atlasgfx.setColor(win.client_fg, win.client_bg)
			local cx0, cy0 = win:client_x(), win:client_y()

			-- column headers (rows cr, cr+1)
			widgets.label_block(win, 0, cr, { "Servers", string.rep("-", math.min(12, w_srv)) })
			widgets.label_block(win, w_srv, cr, { "Channels", string.rep("-", math.min(12, w_ch)) })

			for i = 1, max_rows do
				local srv = st.servers[i]
				if not srv then break end
				local row = row0 + i - 1
				if row > list_bottom then break end
				local lab = srv.name:sub(1, w_srv - 1)
				if st.sel_srv == i then
					atlasgfx.setColor(win.client_bg, win.client_fg)
					atlasgfx.fillRect(cx0, cy0 + row, w_srv, 1, " ")
					atlasgfx.text(cx0, cy0 + row, lab .. string.rep(" ", math.max(0, w_srv - #lab)))
					atlasgfx.setColor(win.client_fg, win.client_bg)
				else
					atlasgfx.setColor(win.client_fg, win.client_bg)
					atlasgfx.text(cx0, cy0 + row, lab .. string.rep(" ", math.max(0, w_srv - #lab)))
				end
				add_hit({ x0 = 0, x1 = w_srv - 1, y0 = row, y1 = row, kind = "srv", idx = i })
			end

			local srv = st.servers[st.sel_srv]
			if srv and type(srv.channels) == "table" then
				for j = 1, max_rows do
					local cn = srv.channels[j]
					if not cn then break end
					local row = row0 + j - 1
					if row > list_bottom then break end
					local lab = ("#" .. cn):sub(1, w_ch - 1)
					if st.sel_ch == j then
						atlasgfx.setColor(win.client_bg, win.client_fg)
						atlasgfx.fillRect(cx0 + w_srv, cy0 + row, w_ch, 1, " ")
						atlasgfx.text(cx0 + w_srv, cy0 + row, lab .. string.rep(" ", math.max(0, w_ch - #lab)))
						atlasgfx.setColor(win.client_fg, win.client_bg)
					else
						atlasgfx.text(cx0 + w_srv, cy0 + row, lab .. string.rep(" ", math.max(0, w_ch - #lab)))
					end
					add_hit({
						x0 = w_srv,
						x1 = w_srv + w_ch - 1,
						y0 = row,
						y1 = row,
						kind = "ch",
						idx = j,
					})
				end
			end

			local msg_w = math.max(8, cw - msg_x)
			local max_msg_rows = max_rows
			local start = widgets.log_tail_index(st.lines, max_msg_rows)
			for r = 0, max_msg_rows - 1 do
				local line = st.lines[start + r]
				local row = row0 + r
				if row > list_bottom then break end
				if line then
					line = tostring(line)
					if #line > msg_w then line = line:sub(1, msg_w) end
					atlasgfx.setColor(win.client_fg, win.client_bg)
					atlasgfx.text(cx0 + msg_x, cy0 + row, line)
				end
			end

			local hint = st.status
			if #hint > cw - 2 then hint = hint:sub(1, cw - 5) .. "…" end
			atlasgfx.setColor("bright_black", win.client_bg)
			atlasgfx.text(cx0, cy0 + status_row, hint .. string.rep(" ", math.max(0, cw - #hint)))

			local prompt = st.prompt and ("?" .. (st.prompt.step or "") .. ") ") or ""
			local buf = prompt .. st.compose
			if #buf > cw - 3 then buf = "…" .. buf:sub(-(cw - 4)) end
			atlasgfx.setColor("bright_white", win.client_bg)
			atlasgfx.text(cx0, cy0 + input_row, "> " .. buf .. string.rep(" ", math.max(0, cw - #buf - 2)))

			shell:paint_dropdown(win)
		end
	end
	_G[CACHE] = factory
end
return factory
