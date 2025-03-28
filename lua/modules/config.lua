config = {}

defaultOptions = {
	acceptTypes = {}, -- { fieldName : { "Number3", "Object" }}
}

config.merge = function(self, defaults, overrides, options)
	if self ~= config then
		error("config:merge should be called with `:`", 2)
	end

	if type(defaults) ~= "table" then
		error("config:merge(defaults, overrides, option) - defaults should be a table", 2)
	end

	if overrides ~= nil and type(overrides) ~= "table" then
		error(
			"config:merge(defaults, overrides, option) - overrides should be nil or a table (overrides: "
				.. type(overrides)
				.. ")",
			2
		)
	end

	if options ~= nil and type(options) ~= "table" then
		error("config:merge(defaults, overrides, option) - options should be nil or a table", 2)
	end

	local opts
	if options ~= nil then
		opts = config:merge(defaultOptions, options)
	else
		opts = defaultOptions
	end

	local conf = {}
	for k, v in pairs(defaults) do
		if type(k) ~= "string" then
			error("config:merge(defaults, overrides, option) - all keys in defaults should be strings", 2)
		end
		conf[k] = v
	end

	local overriden
	local types
	local vType
	local confVType
	if overrides then
		for k, v in pairs(overrides) do
			vType = typeof(v)
			confVType = typeof(conf[k])
			overriden = false
			if vType == confVType then
				conf[k] = v
				overriden = true
			elseif opts.acceptTypes[k] ~= nil then
				types = opts.acceptTypes[k]
				for _, t in ipairs(types) do
					if vType == t or t == "*" then
						conf[k] = v
						overriden = true
						break
					end
				end
			end
			if overriden == false then
				print("⚠️ config:merge - overrides key ignored: " .. k)
			end
		end
	end

	return conf
end

return config
