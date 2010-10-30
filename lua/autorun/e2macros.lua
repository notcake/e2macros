if SERVER then
	AddCSLuaFile ("autorun/e2macros.lua")
	
	AddCSLuaFile ("e2macros/e2macros.lua")
	AddCSLuaFile ("e2macros/context.lua")
	AddCSLuaFile ("e2macros/process.lua")
else
	include ("e2macros/e2macros.lua")
	
	concommand.Add ("e2macros_reload", function ()
		include ("autorun/e2macros.lua")
	end)
end