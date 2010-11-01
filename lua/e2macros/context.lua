local Context = {}
Context.__index = Context

local ProcessMode = {}
E2Macros.ProcessMode = ProcessMode
ProcessMode.Import = 1
ProcessMode.Expand = 2
ProcessMode.Contract = 3

local ExpansionMode = {}
E2Macros.ExpansionMode = ExpansionMode
ExpansionMode.Reversible = 1
ExpansionMode.Compact = 2

local directives = {
	["define"] = true,
	["end"] = true,
	["expand"] = true,
	["import"] = true
}

local hiddenExpansionDirectives = {
	["define"] = true,
	["end"] = true,
	["import"] = true
}

function E2Macros.Context (...)
	local Object = {}
	setmetatable (Object, Context)
	Object:ctor (...)
	return Object
end

function Context:ctor (fileName)
	self.File = fileName and fileName:lower ()
	self.FullPath = nil
	
	self.LastProcessTime = 0
	self.Code = nil
	
	self.ExpansionCount = 0
	
	self.ProcessMode = ProcessMode.Import
	self.ExpansionMode = ExpansionMode.Reversible
	self:Reset ()
end

function Context:AddExpansionDefinitionLine (line, directiveType, directiveArguments)
	for i = 1, #self.CurrentExpansions do
		self.CurrentExpansions [i].Lines [#self.CurrentExpansions [i].Lines + 1] = line
	end
	if self.CurrentExpansions.ArgumentCount > 0 then
		local success, tokens = E2Macros.Tokenizer:Execute (line, directiveType, directiveArguments)
		if success then
			for i = 1, #tokens do
				local tokenString = tokens [i] [2]
				local argumentEntry = self.CurrentExpansions.Arguments [tokenString]
				if argumentEntry then
					for j = 1, #argumentEntry do
						local expansion = argumentEntry [j]
						local argumentIndex = expansion.Arguments [tokenString]
						expansion.ArgumentLines [#expansion.Lines] = expansion.ArgumentLines [#expansion.Lines] or {}
						local lineEntry = expansion.ArgumentLines [#expansion.Lines]
						lineEntry [#lineEntry + 1] = {
							Argument = argumentIndex,
							Start = tokens [i] [5],
							End = tokens [i] [5] + tokenString:len () - 1
						}
					end
				end
			end
		end
	end
end

-- Expands a macro recursively
function Context:AppendExpansion (lineNumber, spacing, expansionArguments, alreadyExpanded)
	local indent = self.ExpansionMode ~= ExpansionMode.Compact and "    " or ""
	
	self.ExpansionCount = self.ExpansionCount + 1
	local expansionName = expansionArguments [1]
	if not expansionName then
		return "Expansion name is missing"
	end
	alreadyExpanded = alreadyExpanded or {}
	if alreadyExpanded [expansionName] then
		return "Detected infinite macro expansion loop in expansion \"" .. expansionName .. "\""
	end
	alreadyExpanded [#alreadyExpanded + 1] = expansionName
	alreadyExpanded [expansionName] = true
	local expansionEntry = self:LookupExpansionRecursive (expansionName)
	if expansionEntry then
		if #alreadyExpanded == 1 and self.ExpansionMode ~= ExpansionMode.Compact then
			local originalLine = self.OriginalLines [lineNumber]
			self.Lines [#self.Lines + 1] = spacing .. "#@@mexpanded" .. originalLine:sub (originalLine:find ("expand") + string.len ("expand"))
			self.LineMap [#self.Lines] = lineNumber
		end
		
		-- Generate expansion trace
		local expansionTrace = alreadyExpanded [1] .. "\""
		for i = 2, #alreadyExpanded do
			expansionTrace = alreadyExpanded [i] .. "\" in expansion \"" .. expansionTrace
		end
		expansionTrace = "in expansion \"" .. expansionTrace
		
		-- Expand
		if #expansionArguments - 1 < #expansionEntry.Arguments then
			return "Not enough arguments for expansion of \"" .. expansionName .. "\""
		elseif #expansionArguments - 1 > #expansionEntry.Arguments then
			return "Too many arguments for expansion of \"" .. expansionName .. "\""
		end
		for i = 1, #expansionEntry.Lines do
			local line = expansionEntry.Lines [i]
			if expansionEntry.ArgumentLines [i] then
				line = ""
				for j = 1, #expansionEntry.ArgumentLines [i] do
					local part = expansionEntry.ArgumentLines [i] [j]
					if part.Argument then
						line = line .. expansionArguments [part.Argument + 1]
					else
						line = line .. expansionEntry.Lines [i]:sub (part.Start, part.End)
					end
				end
			end
			local directiveType, directiveArguments, explodedArguments = E2Macros.ProcessLine (line)
			if directiveType then
				if directiveType == "expand" then
					local expansionError = self:AppendExpansion (lineNumber, spacing .. line:sub (1, line:find ("@") - 1) .. indent, explodedArguments, alreadyExpanded)
					if expansionError then
						alreadyExpanded [#alreadyExpanded] = nil
						return expansionError .. " in expansion \"" .. expansionName .. "\""
					end
				else
					self.Lines [#self.Lines + 1] = line
					self.LineMap [#self.Lines] = lineNumber
					self.LineTrace [#self.Lines] = expansionTrace
				end
			else
				self.Lines [#self.Lines + 1] = spacing .. indent .. line
				self.LineMap [#self.Lines] = lineNumber
				self.LineTrace [#self.Lines] = expansionTrace
			end
		end
		if #alreadyExpanded == 1 and self.ExpansionMode ~= ExpansionMode.Compact then
			self.Lines [#self.Lines + 1] = spacing .. "#@@mendexp"
			self.LineMap [#self.Lines] = lineNumber
		end
	else
		alreadyExpanded [#alreadyExpanded] = nil
		return "Failed to find macro expansion for \"" ..expansionName .. "\""
	end
	alreadyExpanded [#alreadyExpanded] = nil
	alreadyExpanded [expansionName] = false
end

function Context:CheckForChanges ()
	if SysTime () - self.LastProcessTime < 1 then
		return
	end
	self.LastProcessTime = SysTime ()
	if self.File then
		if self.File:sub (-4):lower () ~= ".txt" then
			self.File = self.File .. ".txt"
		end
		if file.Exists ("Expression2/macros/" .. self.File) then
			self.FullPath = "Expression2/macros/" .. self.File
		elseif file.Exists ("Expression2/" .. self.File) then
			self.FullPath = "Expression2/" .. self.File
		else
			self.FullPath = nil
		end
	end
	local code = self.FullPath and file.Read (self.FullPath)
	if code == self.Code then
		return
	end
	self.Code = code
	self:ReprocessCode ()
end

-- Collapses expanded macros
function Context:ContractCode (code)
	self.Code = code
	self.OriginalLines = string.Explode ("\n", code)
	local expansionLevel = 0
	local defineLevel = 0
	
	for _, line in ipairs (self.OriginalLines) do
		local directiveType, directiveArguments = E2Macros.ProcessExpandedLine (line)
		local hideLine = expansionLevel > 0
		local uncomment = defineLevel > 0 or (directiveType and true)
		if directiveType then
			if directiveType == "define" then
				defineLevel = defineLevel + 1
			elseif directiveType == "end" then
				defineLevel = defineLevel - 1
			elseif directiveType == "mexpanded" then
				if directiveArguments then
					if expansionLevel == 0 then
						local spacing = line:sub (1, line:find ("#") - 1)
						self.Lines [#self.Lines + 1] = spacing .. "@expand ".. directiveArguments
					end
					expansionLevel = expansionLevel + 1
					hideLine = true
				end
			elseif directiveType == "mendexp" then
				expansionLevel = expansionLevel - 1
				expansionLevel = expansionLevel < 0 and 0 or expansionLevel
				hideLine = true
			elseif not directives [directiveType] then
				uncomment = false
			end
		end
		if not hideLine then
			if uncomment then
				if directiveType then
					local directiveStart = line:find ("#@")
					line = line:sub (1, directiveStart - 1) .. line:sub (directiveStart + 2)
				elseif line:sub (1, 2) == "#@" then
					line = line:sub (3)
				end
			end
			self.Lines [#self.Lines + 1] = line
		end
	end
end

function Context:GetErrors ()
	return self.Errors
end

function Context:GetFirstError ()
	return self.Errors [1]
end

function Context:GetFullPath ()
	return self.FullPath
end

function Context:GetImportTable (importTable)
	local cacheTable = false
	if self.ImportTableValid then
		return self.ImportTable
	end
	if not importTable then
		cacheTable = true
		importTable = {}
		importTable [self.File or "<anonymous>"] = self
	end
	for import, _ in pairs (self.Imports) do
		if not importTable [import] then
			importTable [import] = E2Macros.Files [import]
			E2Macros.Files [import]:GetImportTable (importTable)
		end
	end
	if cacheTable then
		self.ImportTable = importTable
		self.ImportTableValid = true
	end
	return importTable
end

function Context:GetLines ()
	return self.Lines
end

function Context:GetOriginalLine (lineNumber)
	return self.OriginalLines [lineNumber]
end

function Context:ImportFile (fileName)
	fileName = fileName:lower ()
	if self.Imports [fileName] then
		self.Imports [fileName]:CheckForChanges ()
		return E2Macros.Files [fileName].Code and true or false
	end
	self.Imports [fileName] = true
	self.ImportTableValid = false
	if not E2Macros.ProcessFile (fileName).Code then
		return false
	end
	return true
end

function Context:LookupExpansion (name)
	return self.Expansions [name]
end

function Context:LookupExpansionRecursive (name)
	for _, context in pairs (self:GetImportTable ()) do
		local expansion = context:LookupExpansion (name)
		if expansion then
			return expansion
		end
	end
	return nil
end

function Context:PopExpansionDefinition ()
	local expansion = self.CurrentExpansions [#self.CurrentExpansions]
	if not expansion then
		return
	end
	for i = 1, #expansion.Arguments do
		local argumentName = expansion.Arguments [i]
		self.CurrentExpansions.Arguments [argumentName] [#self.CurrentExpansions.Arguments [argumentName]] = nil
		if #self.CurrentExpansions.Arguments [argumentName] == 0 then
			self.CurrentExpansions.Arguments [argumentName] = nil
		end
	end
	for lineNumber, lineEntry in pairs (expansion.ArgumentLines) do
		local offset = 1
		local lineParts = {}
		for i = 1, #lineEntry do
			if lineEntry [i].Start > i then
				lineParts [#lineParts + 1] = {
					Start = offset,
					End = lineEntry [i].Start - 1
				}
			end
			lineParts [#lineParts + 1] = {
				Argument = lineEntry [i].Argument
			}
			offset = lineEntry [i].End + 1
		end
		if offset <= expansion.Lines [lineNumber]:len () then
			lineParts [#lineParts + 1] = {
				Start = offset,
				End = expansion.Lines [lineNumber]:len ()
			}
		end
		expansion.ArgumentLines [lineNumber] = lineParts
	end
	self.CurrentExpansions.ArgumentCount = self.CurrentExpansions.ArgumentCount - expansion.ArgumentCount
	self.CurrentExpansions [#self.CurrentExpansions] = nil
end

-- Reads / expands macros.
function Context:ProcessCode (code)
	self.LastProcessTime = SysTime ()
	
	self.Code = code
	self.OriginalLines = string.Explode ("\n", code)
	for lineNumber, line in ipairs (self.OriginalLines) do
		local directiveType, directiveArguments, explodedArguments = E2Macros.ProcessLine (line)
		local hideLine = false
		local addToExpansions = not hiddenExpansionDirectives [directiveType]
		local comment = #self.CurrentExpansions > 0 or directiveType
		if directiveType then
			if directiveType == "import" then
				if not directiveArguments then
					self.Errors [#self.Errors + 1] = "Expected file name at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
				else
					if not self:ImportFile (directiveArguments) then
						self.Errors [#self.Errors + 1] = "Cannot import \"" .. directiveArguments .. "\" at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
					end
				end
			elseif directiveType == "define" then
				if not directiveArguments then
					self.Errors [#self.Errors + 1] = "Expected definition name at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
				else
					self:PushExpansionDefinition (explodedArguments)
				end
			elseif directiveType == "end" then
				self:PopExpansionDefinition ()
			elseif directiveType == "expand" then
				if self.ProcessMode == ProcessMode.Expand and
					#self.CurrentExpansions == 0 then
					local spacing = line:sub (1, line:find ("@") - 1)
					local expansionError = self:AppendExpansion (lineNumber, spacing, explodedArguments)
					if expansionError then
						self.Errors [#self.Errors + 1] = expansionError .. " at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
					end
					hideLine = true
				end
			else
				comment = false
			end
		end
		if addToExpansions and
			not string.find (line, "^[ \t]*#") and
			#self.CurrentExpansions > 0 then
			line = line:gsub (" +%(", "(")
			line = line:gsub (" +%[", "[")
			self:AddExpansionDefinitionLine (line, directiveType, explodedArguments)
		end
		hideLine = hideLine or self.ProcessMode == ProcessMode.Import or (self.ExpansionMode == ExpansionMode.Compact and comment)
		if not hideLine then
			if comment then
				if directiveType then
					local directiveStart = line:find ("@")
					line = line:sub (1, directiveStart - 1) .. "#@" .. line:sub (directiveStart)
				else
					line = "#@" .. line
				end
			end
			self.Lines [#self.Lines + 1] = line
			self.LineMap [#self.Lines] = lineNumber
		end
	end
end

function Context:PushExpansionDefinition (directiveArguments)
	local expansionName = directiveArguments [1]
	local expansion = {
		ArgumentCount = #directiveArguments - 1,
		Arguments = {},
		ArgumentLines = {},
		Lines = {}
	}
	self.Expansions [expansionName] = expansion
	self.CurrentExpansions [#self.CurrentExpansions + 1] = expansion
	self.CurrentExpansions.ArgumentCount = self.CurrentExpansions.ArgumentCount + expansion.ArgumentCount
	for i = 2, #directiveArguments do
		expansion.Arguments [#expansion.Arguments + 1] = directiveArguments [i]
		expansion.Arguments [directiveArguments [i]] = #expansion.Arguments
		if not self.CurrentExpansions.Arguments [directiveArguments [i]] then
			self.CurrentExpansions.Arguments [directiveArguments [i]] = {}
		end
		self.CurrentExpansions.Arguments [directiveArguments [i]] [#self.CurrentExpansions.Arguments [directiveArguments [i]] + 1] = expansion
	end
end

function Context:RemapLine (lineNumber)
	return self.LineMap [lineNumber], self.LineTrace [lineNumber]
end

function Context:ReprocessCode ()
	self.LastProcessTime = SysTime ()
	
	local importTable = self:GetImportTable ()
	for _, context in pairs (importTable) do
		context:CheckForChanges ()
	end

	self:Reset ()
	self:ProcessCode (self.Code)
end

function Context:Reset ()
	self.Errors = {}
	
	self.OriginalLines = {}
	self.Lines = {}
	self.LineMap = {}
	self.LineTrace = {}
	
	self.Imports = {}
	self.ImportTable = nil
	self.ImportTableValid = false
	self.Expansions = {}
	
	self.CurrentExpansions = {
		ArgumentCount = 0,
		Arguments = {}
	}
end

function Context:SetExpansionMode (expansionMode)
	self.ExpansionMode = expansionMode
end

function Context:SetProcessMode (processMode)
	self.ProcessMode = processMode
end