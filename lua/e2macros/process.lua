function E2Macros.ExplodeQuotedLine (line)
	local exploded = {}
	local index = 1
	local maxIndex = line:len ()
	
	local part = ""
	local quotationMark = nil
	local escaped = false
	while index <= maxIndex do
		local char = line:sub (index, index)
		if escaped then
			part = part .. char
			escaped = false
		else
			if char == quotationMark then
				-- end of string
				exploded [#exploded + 1] = part .. char
				part = ""
				quotationMark = nil
			elseif (char == "'" or
					char == "\"") and
					not quotationMark then
				-- beginning of quotation
				exploded [#exploded + 1] = part ~= "" and part or nil
				part = char
				quotationMark = char
			elseif (char == " " or
					char == "\t") and
					not quotationMark then
				exploded [#exploded + 1] = part ~= "" and part or nil
				part = ""
			elseif char == "\\" and
				   quotationMark then
				part = part .. char
				escaped = true
			else
				part = part .. char
			end
		end
		index = index + 1
	end
	exploded [#exploded + 1] = part ~= "" and part or nil
	local error = nil
	if escaped then
		error = "Expected <char>, got <end of line>"
	elseif quotationMark then
		error = "Expected " .. quotationMark .. ", got <end of line>"
	end
	return exploded, error
end

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
	local directiveType = nil
	local directiveArguments = nil
	local explodedArguments = nil
	local error = nil
	if trimmedLine:sub (1, 1) == "@" then
		trimmedLine = trimmedLine:sub (2):Trim ()
		local spacePosition = trimmedLine:find (" ")
		if not spacePosition then
			directiveType = trimmedLine
		else
			directiveType = trimmedLine:sub (1, spacePosition - 1)
			directiveArguments = trimmedLine:sub (spacePosition + 1):Trim ()
			explodedArguments, error = E2Macros.ExplodeQuotedLine (directiveArguments)
		end
		isDirective = true
	end
	return directiveType, directiveArguments, explodedArguments, error
end

function E2Macros.ProcessExpandedLine (line)
	local trimmedLine = line:Trim ()
	local directiveType = nil
	local directiveArguments = nil
	if trimmedLine:sub (1, 3) == "#@@" then
		trimmedLine = trimmedLine:sub (4):Trim ()
		local spacePosition = trimmedLine:find (" ")
		if not spacePosition then
			directiveType = trimmedLine
		else
			directiveType = trimmedLine:sub (1, spacePosition - 1)
			directiveArguments = trimmedLine:sub (spacePosition + 1):Trim ()
		end
		isDirective = true
	end
	return directiveType, directiveArguments
end