function E2Macros.ProcessFile (fileName)
	if E2Macros.Files [fileName:lower ()] then
		E2Macros.Files [fileName:lower ()]:CheckForChanges ()
		return E2Macros.Files [fileName:lower ()]
	end
	local context = E2Macros.Context (fileName:lower ())
	E2Macros.Files [fileName:lower ()] = context
	context:CheckForChanges ()
	
	return context
end

-- Extracts command and argument from a directive
function E2Macros.ProcessLine (line)
	local trimmedLine = line:Trim ()
	local isDirective = false
	local directiveType = nil
	local directiveArguments = nil
	if trimmedLine:sub (1, 1) == "@" then
		trimmedLine = trimmedLine:sub (2):Trim ()
		local space = trimmedLine:find (" ")
		if not space then
			directiveType = trimmedLine
		else
			directiveType = trimmedLine:sub (1, trimmedLine:find (" ") - 1)
			directiveArguments = trimmedLine:sub (trimmedLine:find (" ") + 1):Trim ()
		end
		isDirective = true
	end
	return isDirective, directiveType, directiveArguments
end

function E2Macros.ProcessExpandedLine (line)
	local trimmedLine = line:Trim ()
	local isDirective = false
	local directiveType = nil
	local directiveArguments = nil
	if trimmedLine:sub (1, 3) == "#@@" then
		trimmedLine = trimmedLine:sub (4):Trim ()
		local space = trimmedLine:find (" ")
		if not space then
			directiveType = trimmedLine
		else
			directiveType = trimmedLine:sub (1, trimmedLine:find (" ") - 1)
			directiveArguments = trimmedLine:sub (trimmedLine:find (" ") + 1):Trim ()
		end
		isDirective = true
	end
	return isDirective, directiveType, directiveArguments
end