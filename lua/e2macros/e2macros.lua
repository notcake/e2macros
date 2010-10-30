if not E2Macros then
	E2Macros = {}
	E2Macros.Backup = {}
	E2Macros.Files = {}
else
	E2Macros.Files = {}
end

include ("context.lua")
include ("process.lua")

-- Client to server
function E2Macros.transfer (code)
	local context = E2Macros.Context ()
	context:ExpandCode (code)
	code = table.concat (context:GetLines (), "\n")
	
	E2Macros.Backup.transfer (code)
end

-- Client code validation
function E2Macros.wire_expression2_validate (code)
	local context = E2Macros.Context ()
	context:ExpandCode (code)
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
	if not transfer or
		not wire_expression2_validate then
		return
	end
	if not E2Macros.Backup.transfer then
		E2Macros.Backup.transfer = transfer
	end
	transfer = E2Macros.transfer
	if not E2Macros.Backup.wire_expression2_validate then
		E2Macros.Backup.wire_expression2_validate = wire_expression2_validate
	end
	wire_expression2_validate = E2Macros.wire_expression2_validate
	
	local name, hookTable = debug.getupvalue (usermessage.Hook, 2)
	if name == "Hooks" then
		local hook = hookTable ["wire_expression2_download"]
		if not E2Macros.Backup.wire_expression2_download then
			E2Macros.Backup.wire_expression2_download = hook.Function
		end
		hook.Function = E2Macros.wire_expression2_download
	end
	hook.Remove ("Think", "E2MacrosInit")
end)