if not E2Macros then
	E2Macros = {}
	E2Macros.Backup = {}
	E2Macros.Files = {}
	E2Macros.Tokenizer = nil
else
	E2Macros.Files = {}
end

include ("context.lua")
include ("process.lua")

function E2Macros.findupvalue (func, varname)
	local name, value
	local i = 1
	while true do
		name, value = debug.getupvalue (func, i)
		if name == varname then
			return value, i
		end
		i = i + 1
	end
	return nil, i
end

-- Client to server
function E2Macros.transfer (code)
	local context = E2Macros.Context ()
	context:SetProcessMode (E2Macros.ProcessMode.Expand)
	context:ProcessCode (code)
	code = table.concat (context:GetLines (), "\n")
	
	E2Macros.Backup.transfer (code)
end

-- Client code validation
function E2Macros.wire_expression2_validate (code)
	local context = E2Macros.Context ()
	context:SetProcessMode (E2Macros.ProcessMode.Expand)
	context:ProcessCode (code)
	code = table.concat (context:GetLines (), "\n")
	local error = context:GetFirstError ()
	if error then
		return error
	end
	error = E2Macros.Backup.wire_expression2_validate (code)
	if error then
		local originalLine = nil
		local lineOffset = error:find ("line ")
		if lineOffset then
			local message = error:sub (1, lineOffset - 1)
			if message:sub (-4) == " at " then
				message = message:sub (1, -4)
			end
			local position = ""
			local realLineNumber, lineTrace = nil, nil
			error:gsub ("line ([0-9]+)", function (match)
				realLineNumber, lineTrace = context:RemapLine (tonumber (match))
				originalLine = context:GetOriginalLine (realLineNumber)
				position = "at line " .. tostring (realLineNumber) .. ", char " .. tostring (originalLine:len () + 1)
				return "line " .. tostring (realLineNumber)
			end)
			if realLineNumber and lineTrace then
				message = message .. lineTrace .. " "
			end
			error = message .. position
		end
	end
	return error
end

-- Server to client
function E2Macros.wire_expression2_download (um)
	local name, download = debug.getupvalue (E2Macros.Backup.wire_expression2_download, 1)
	if name == "download" then
		if download.downloading and
			download.current + 1 == download.chunks then
			local chunkIndex = um:ReadShort ()
			local codePart = um:ReadString ()
			download.code = download.code .. codePart
			
			local context = E2Macros.Context ()
			context:SetProcessMode (E2Macros.ProcessMode.Contract)
			context:ContractCode (download.code)
			download.code = table.concat (context:GetLines (), "\n")
			um = {
				ReadShort = function ()
					return chunkIndex
				end,
				ReadString = function ()
					return ""
				end
			}
		end
	end
	E2Macros.Backup.wire_expression2_download (um)
end

concommand.Add ("e2macros_expand", function (_, _, args)
	if #args == 0 or
		#args > 2 then
		print ("e2macros_expand <path>")
		print ("e2macros_expand [preserve directives 0/1] <path>")
		return
	end
	local path = args [#args]
	if path:sub (-4):lower () ~= ".txt" then
		path = path .. ".txt"
	end
	local compact = true
	if #args == 2 then
		compact = not util.tobool (args [1])
	end
	local code = file.Read ("Expression2/" .. path)
	if not code then
		print ("Unable to find " .. path .. ".")
		return
	end
	local context = E2Macros.Context ()
	context:SetProcessMode (E2Macros.ProcessMode.Expand)
	context:SetExpansionMode (compact and E2Macros.ExpansionMode.Compact or E2Macros.ExpansionMode.Reversible)
	context:ProcessCode (code)
	local errors = context:GetErrors ()
	if #errors > 0 then
		print (tostring (#errors) .. " errors:")
	end
	for _, error in ipairs (errors) do
		print (error)
	end
	code = table.concat (context:GetLines (), "\n")
	file.Write ("Expression2/macros/expanded/" .. path, code)
	print ("Wrote file to macros/expanded/" .. path .. " (" .. tostring (#context:GetLines ()) .. " lines).")
end, function (command, args)
	args = args:Trim ():gsub ("\\", "/")
	local args = E2Macros.ExplodeQuotedLine (args)
	args [1] = args [1] or ""
	if args [#args]:sub (1, 1) == "\"" then
		args [#args] = args [#args]:sub (2)
	end
	if args [#args]:sub (-1) == "\"" then
		args [#args] = args [#args]:sub (1, -2)
	end
	local path = args [#args]
	local compact = nil
	if #args > 1 then
		compact = not util.tobool (args [1])
	end
	local files = file.Find ("Expression2/" .. path .. "*")
	if path:find ("/") then
		path = path:sub (1, -path:reverse ():find ("/"))
	else
		path = ""
	end
	if compact ~= nil then
		compact = compact and "0 " or "1 "
	else
		compact = ""
	end
	local autocomplete = {}
	local pathHasSpaces = path:find (" ")
	for _, file in ipairs (files) do
		if pathHasSpaces or file:find (" ") then
			autocomplete [#autocomplete + 1] = command .. " " .. compact .. "\"" .. path .. file .. "\""
		else
			autocomplete [#autocomplete + 1] = command .. " " .. compact .. path .. file
		end
	end
	return autocomplete
end, "Expands the macros in an Expression 2 script and saves it in Expression2/macros/expanded.")

concommand.Add ("e2macros_rehook", function (_, _, args)
	if args [1] ~= "1" then
		print ("If you've reloaded the Expression 2 entity and the Wire library, run e2macros_rehook 1.")
		print ("Otherwise, leave this alone.")
		return
	end
	E2Macros.Backup.transfer = transfer
	E2Macros.Backup.wire_expression2_validate = wire_expression2_validate
	
	transfer = E2Macros.transfer
	wire_expression2_validate = E2Macros.wire_expression2_validate
	
	print ("E2 Macros: Rehooked transfer and wire_expression2_validate.")
end)

hook.Add ("Think", "E2MacrosInit", function ()
	E2Macros.Tokenizer = {}
	setmetatable (E2Macros.Tokenizer, Tokenizer)
	function E2Macros.Tokenizer:Execute (code, directiveType, directiveArguments)
		if directiveType then
			local offset = code:find (directiveType, 1, true)
			local tokens = {
				{
					"var",
					directiveType,
					1,
					offset
				}
			}
			offset = offset + directiveType:len ()
			for i = 1, #directiveArguments do
				offset = code:find (directiveArguments [i], 1, true)
				tokens [#tokens + 1] = {
					"var",
					directiveArguments [i],
					false,
					1,
					offset
				}
				offset = offset + directiveArguments [i]:len ()
			end
			return true, tokens
		end
		return pcall (self.Process, self, code)
	end

	if not wire_expression2_upload or
		not wire_expression2_validate then
		return
	end
	
	-- transfer
	local transfer, transfer_idx = E2Macros.findupvalue (wire_expression2_upload, "transfer")
	if transfer then
		if not E2Macros.Backup.transfer then
			E2Macros.Backup.transfer = transfer
		end
		debug.setupvalue (wire_expression2_upload, transfer_idx, E2Macros.transfer)
	end
	
	-- wire_expression2_validate
	if not E2Macros.Backup.wire_expression2_validate then
		E2Macros.Backup.wire_expression2_validate = wire_expression2_validate
	end
	wire_expression2_validate = E2Macros.wire_expression2_validate
	
	-- wire_expression2_download
	local name, hookTable = debug.getupvalue (usermessage.Hook, 2)
	if name == "Hooks" then
		local hook = hookTable ["wire_expression2_download"]
		if not E2Macros.Backup.wire_expression2_download then
			E2Macros.Backup.wire_expression2_download = hook.Function
		end
		hook.Function = E2Macros.wire_expression2_download
	end
	
	-- Syntax highlighting
	local name, vguiMetatables = debug.getupvalue (vgui.Register, 1)
	if name == "PanelFactory" then
		local editorMetatable = vguiMetatables ["Expression2Editor"]
		local directives = E2Macros.findupvalue (editorMetatable.SyntaxColorLine, "directives")
		if directives then
			directives ["@end"] = 0
			directives ["@define"] = 0
			directives ["@expand"] = 0
			directives ["@import"] = 0
		end
	end
	hook.Remove ("Think", "E2MacrosInit")
end)