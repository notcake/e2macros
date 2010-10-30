local Context = {}
Context.__index = Context

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
	self.Errors = {}
	
	self.OriginalLines = {}
	self.Lines = {}
	self.LineMap = {}
	self.LineTrace = {}
	
	self.Imports = {}
	self.ImportTable = nil
	self.ImportTableValid = false
	self.Expansions = {}
end

-- Expands a macro recursively
function Context:AppendExpansion (lineNumber, spacing, expansionName, alreadyExpanded)
	if not expansionName then
		return "Expansion name is missing"
	end
	alreadyExpanded = alreadyExpanded or {}
	if alreadyExpanded [expansionName] then
		return "Detected infinite macro expansion loop in expansion \"" .. expansionName .. "\""
	end
	alreadyExpanded [#alreadyExpanded + 1] = expansionName
	alreadyExpanded [expansionName] = true
	local expansion = self:LookupExpansionRecursive (expansionName)
	if expansion then
		self.Lines [#self.Lines + 1] = spacing .. "# mexpanded " .. expansionName
		self.LineMap [#self.Lines] = lineNumber
		for i = 1, #expansion do
			local isDirective, directiveType, directiveArguments = E2Macros.ProcessLine (expansion [i])
			if isDirective then
				if directiveType == "expand" then
					local expansionError = self:AppendExpansion (lineNumber, spacing .. "    ", directiveArguments, alreadyExpanded)
					if expansionError then
						alreadyExpanded [#alreadyExpanded] = nil
						return expansionError .. " in expansion \"" .. expansionName .. "\""
					end
				end
			else
				if expansion [i]:sub (1, 1) == "@" then
					self.Lines [#self.Lines + 1] = expansion [i]
				else
					self.Lines [#self.Lines + 1] = spacing .. "    " .. expansion [i]
				end
				local expansionList = alreadyExpanded [1] .. "\""
				for i = 2, #alreadyExpanded do
					expansionList = alreadyExpanded [i] .. "\" in expansion \"" .. expansionList
				end
				self.LineMap [#self.Lines] = lineNumber
				self.LineTrace [#self.Lines] = "in expansion \"" .. expansionList
			end
		end
		self.Lines [#self.Lines + 1] = spacing .. "# mendexp"
		self.LineMap [#self.Lines] = lineNumber
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
	local lines = string.Explode ("\n", code)
	local expansionLevel = 0
	local defineLevel = 0
	
	for _, line in ipairs (lines) do
		local isDirective, directiveType, directiveArguments = E2Macros.ProcessLine (line)
		local hideLine = expansionLevel > 0
		local uncomment = defineLevel > 0
		if isDirective then
			if directiveType == "define" then
				defineLevel = defineLevel + 1
			elseif directiveType == "end" then
				defineLevel = defineLevel - 1
				uncomment = false
			elseif directiveType == "mexpanded" then
				if directiveArguments then
					if expansionLevel == 0 then
						local spacing = line:sub (1, line:find ("#") - 1)
						self.Lines [#self.Lines + 1] = spacing .. "# expand ".. directiveArguments
					end
					expansionLevel = expansionLevel + 1
					hideLine = true
				end
			elseif directiveType == "mendexp" then
				expansionLevel = expansionLevel - 1
				if expansionLevel < 0 then
					expansionLevel = 0
				end
				hideLine = true
			end
		end
		if not hideLine then
			if uncomment then
				if line:sub (1, 1) == "#" then
					line = line:sub (2)
				end
			end
			self.Lines [#self.Lines + 1] = line
		end
	end
end

-- Expands macros for validation and sending to the server
function Context:ExpandCode (code)
	self.Code = code
	local lines = string.Explode ("\n", code)
	self.OriginalLines = lines
	local expansionDefinitions = {}
	
	for lineNumber, line in ipairs (lines) do
		local isDirective, directiveType, directiveArguments = E2Macros.ProcessLine (line)
		local hideLine = false
		local addToExpansions = true
		local comment = #expansionDefinitions > 0
		if isDirective then
			addToExpansions = false
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
					self.Expansions [directiveArguments] = {}
					expansionDefinitions [#expansionDefinitions + 1] = self.Expansions [directiveArguments]
				end
			elseif directiveType == "end" then
				expansionDefinitions [#expansionDefinitions] = nil
				comment = #expansionDefinitions > 0
			elseif directiveType == "expand" then
				addToExpansions = true
				if #expansionDefinitions == 0 then
					local spacing = line:sub (1, line:find ("#") - 1)
					local expansionError = self:AppendExpansion (lineNumber, spacing, directiveArguments)
					if expansionError then
						self.Errors [#self.Errors + 1] = expansionError .. " at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
					end
					hideLine = true
				end
			end
		end
		if addToExpansions then
			for i = 1, #expansionDefinitions do
				expansionDefinitions [i] [#expansionDefinitions [i] + 1] = line
			end
		end
		if not hideLine then
			if comment then
				line = "#" .. line
			end
			self.Lines [#self.Lines + 1] = line
			self.LineMap [#self.Lines] = lineNumber
		end
	end
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
	local context = E2Macros.ProcessFile (fileName)
	if not context.Code then
		return false
	end
	return true
end

function Context:LookupExpansion (name)
	return self.Expansions [name]
end

function Context:LookupExpansionRecursive (name)
	local importTable = self:GetImportTable ()
	for _, context in pairs (importTable) do
		local expansion = context:LookupExpansion (name)
		if expansion then
			return expansion
		end
	end
	return nil
end

-- Reads macros from an #import ed file.
function Context:ProcessCode (code)
	self.LastProcessTime = SysTime ()
	
	self.Code = code
	local lines = string.Explode ("\n", code)
	local expansionDefinitions = {}
	for _, line in ipairs (lines) do
		local isDirective, directiveType, directiveArguments = E2Macros.ProcessLine (line)
		local addToExpansions = true
		if isDirective then
			addToExpansions = false
			if directiveType == "import" then
				if not directiveArguments then
					self.Errors [#self.Errors + 1] = "Expected file name at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
				else
					self:ImportFile (directiveArguments)
				end
			elseif directiveType == "define" then
				if not directiveArguments then
					self.Errors [#self.Errors + 1] = "Expected definition name at line " .. tostring (lineNumber) .. ", char " .. tostring (line:len () + 1)
				else
					self.Expansions [directiveArguments] = {}
					expansionDefinitions [#expansionDefinitions + 1] = self.Expansions [directiveArguments]
				end
			elseif directiveType == "expand" then
				addToExpansions = true
			elseif directiveType == "end" then
				expansionDefinitions [#expansionDefinitions] = nil
			end
		else
			if line:sub (1, 1) ~= "@" then
				line = line:gsub (" +%(", "(")
				line = line:gsub (" +%[", "[")
			end
		end
		if addToExpansions then
			for i = 1, #expansionDefinitions do
				expansionDefinitions [i] [#expansionDefinitions [i] + 1] = line
			end
		end
		self.Lines [#self.Lines + 1] = line
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

	self.Lines = {}
	self.LineMap = {}
	self.LineTrace = {}
	
	self.Imports = {}
	self.ImportTable = nil
	self.ImportTableValid = false
	self.Expansions = {}
	self.Errors = {}
	
	self:ProcessCode (self.Code)
end