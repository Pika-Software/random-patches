local SetDrawColor, SetMaterial, DrawTexturedRectUV
do
	local _obj_0 = surface
	SetDrawColor, SetMaterial, DrawTexturedRectUV = _obj_0.SetDrawColor, _obj_0.SetMaterial, _obj_0.DrawTexturedRectUV
end
local PANEL = FindMetaTable("Panel")
GWEN = { }
do
	local min, max, ceil, floor
	do
		local _obj_0 = math
		min, max, ceil, floor = _obj_0.min, _obj_0.max, _obj_0.ceil, _obj_0.floor
	end
	GWEN.CreateTextureBorder = function(_xo, _yo, _wo, _ho, l, t, r, b, material_override)
		local material = SKIN and SKIN.GwenTexture or material_override
		if material_override and not material_override:IsError() then
			material = material_override
		end
		local texture = material:GetTexture("$basetexture")
		local width, height = texture:Width(), texture:Height()
		local _x, _y, _w, _h = _xo / width, _yo / height, _wo / width, _ho / height
		local left, right, top, bottom = 0, 0, 0, 0
		local _l, _t, _r, _b = 0, 0, 0, 0
		return function(x, y, w, h, color)
			if color ~= nil then
				SetDrawColor(color)
			else
				SetDrawColor(255, 255, 255, 255)
			end
			SetMaterial(material)
			left, right, top, bottom = min(l, ceil(w / 2)), min(r, floor(w / 2)), min(t, ceil(h / 2)), min(b, floor(h / 2))
			_l, _t, _r, _b = left / width, top / height, right / width, bottom / height
			DrawTexturedRectUV(x, y, left, top, _x, _y, _x + _l, _y + _t)
			DrawTexturedRectUV(x + left, y, w - left - right, top, _x + _l, _y, _x + _w - _r, _y + _t)
			DrawTexturedRectUV(x + w - right, y, right, top, _x + _w - _r, _y, _x + _w, _y + _t)
			DrawTexturedRectUV(x, y + top, left, h - top - bottom, _x, _y + _t, _x + _l, _y + _h - _b)
			DrawTexturedRectUV(x + left, y + top, w - left - right, h - top - bottom, _x + _l, _y + _t, _x + _w - _r, _y + _h - _b)
			DrawTexturedRectUV(x + w - right, y + top, right, h - top - bottom, _x + _w - _r, _y + _t, _x + _w, _y + _h - _b)
			DrawTexturedRectUV(x, y + h - bottom, left, bottom, _x, _y + _h - _b, _x + _l, _y + _h)
			DrawTexturedRectUV(x + left, y + h - bottom, w - left - right, bottom, _x + _l, _y + _h - _b, _x + _w - _r, _y + _h)
			return DrawTexturedRectUV(x + w - right, y + h - bottom, right, bottom, _x + _w - _r, _y + _h - _b, _x + _w, _y + _h)
		end
	end
end
GWEN.CreateTextureNormal = function(_xo, _yo, _wo, _ho, material_override)
	local material = SKIN and SKIN.GwenTexture or material_override
	if material_override and not material_override:IsError() then
		material = material_override
	end
	local texture = material:GetTexture("$basetexture")
	local width, height = texture:Width(), texture:Height()
	local _x, _y, _w, _h = _xo / width, _yo / height, _wo / width, _ho / height
	return function(x, y, w, h, color)
		if color ~= nil then
			SetDrawColor(color)
		else
			SetDrawColor(255, 255, 255, 255)
		end
		SetMaterial(material)
		return DrawTexturedRectUV(x, y, w, h, _x, _y, _x + _w, _y + _h)
	end
end
GWEN.CreateTextureCentered = function(_xo, _yo, _wo, _ho, material_override)
	local material = SKIN and SKIN.GwenTexture or material_override
	if material_override and not material_override:IsError() then
		material = material_override
	end
	local texture = material:GetTexture("$basetexture")
	local width, height = texture:Width(), texture:Height()
	local _x, _y, _w, _h = _xo / width, _yo / height, _wo / width, _ho / height
	return function(x, y, w, h, color)
		if color ~= nil then
			SetDrawColor(color)
		else
			SetDrawColor(255, 255, 255, 255)
		end
		SetMaterial(material)
		x = x + ((w - _wo) * 0.5)
		y = y + ((h - _ho) * 0.5)
		return DrawTexturedRectUV(x, y, _wo, _ho, _x, _y, _x + _w, _y + _h)
	end
end
do
	local GetColor = FindMetaTable("IMaterial").GetColor
	GWEN.TextureColor = function(x, y, material_override)
		local material = SKIN and SKIN.GwenTexture or material_override
		if material_override and not material_override:IsError() then
			material = material_override
		end
		return GetColor(material, x, y)
	end
end
do
	local types = {
		["Base"] = "Panel",
		["Button"] = "DButton",
		["Label"] = "DLabel",
		["TextBox"] = "DTextEntry",
		["TextBoxMultiline"] = "DTextEntry",
		["ComboBox"] = "DComboBox",
		["HorizontalSlider"] = "Slider",
		["ImagePanel"] = "DImage",
		["CheckBoxWithLabel"] = "DCheckBoxLabel"
	}
	local SetMultiline, Add = PANEL.SetMultiline, PANEL.Add
	local pairs = pairs
	local applyGWEN
	applyGWEN = function(self, tbl)
		if tbl.Type == "TextBoxMultiline" then
			SetMultiline(self, true)
		end
		for key, value in pairs(tbl.Properties) do
			if self["GWEN_Set" .. key] ~= nil then
				self["GWEN_Set" .. key](self, value)
			end
		end
		if not tbl.Children then
			return
		end
		for _, value in pairs(tbl.Children) do
			if types[value.Type] ~= nil then
				applyGWEN(Add(self, types[value.Type]), value)
			else
				MsgN("Warning: No GWEN Panel Type ", value.Type)
			end
		end
	end
	PANEL.ApplyGWEN = applyGWEN
	local loadGWENString
	loadGWENString = function(self, json)
		local tbl = util.JSONToTable(json)
		if tbl ~= nil and tbl.Controls ~= nil then
			return applyGWEN(self, tbl.Controls)
		end
	end
	PANEL.LoadGWENString = loadGWENString
	PANEL.LoadGWENFile = function(self, filePath, gamePath)
		local json = file.Read(filePath, gamePath or "GAME")
		if json ~= nil then
			return loadGWENString(self, json)
		end
	end
end
do
	local SetPos = PANEL.SetPos
	PANEL.GWEN_SetPosition = function(self, tbl)
		return SetPos(self, tbl.x, tbl.y)
	end
end
do
	local SetSize = PANEL.SetSize
	PANEL.GWEN_SetSize = function(self, tbl)
		return SetSize(self, tbl.w, tbl.h)
	end
end
do
	local SetText = PANEL.SetText
	PANEL.GWEN_SetText = function(self, text)
		return SetText(self, text)
	end
end
do
	local SetName = PANEL.SetName
	PANEL.GWEN_SetControlName = function(self, name)
		return SetName(self, name)
	end
end
do
	local DockMargin = PANEL.DockMargin
	PANEL.GWEN_SetMargin = function(self, tbl)
		return DockMargin(self, tbl.left, tbl.top, tbl.right, tbl.bottom)
	end
end
do
	local tonumber = tonumber
	do
		local SetMin = PANEL.SetMin
		PANEL.GWEN_SetMin = function(self, min)
			return SetMin(self, tonumber(min))
		end
	end
	do
		local SetMax = PANEL.SetMax
		PANEL.GWEN_SetMax = function(self, max)
			return SetMax(self, tonumber(max))
		end
	end
end
do
	local align = {
		["Top-Right"] = 9,
		["Top"] = 8,
		["Top-Left"] = 7,
		["Right"] = 6,
		["Center"] = 5,
		["Left"] = 4,
		["Bottom-Right"] = 3,
		["Bottom"] = 2,
		["Bottom-Left"] = 1,
		["None"] = 0
	}
	local SetContentAlignment = PANEL.SetContentAlignment
	PANEL.GWEN_SetHorizontalAlign = function(self, key)
		if align[key] then
			return SetContentAlignment(self, align[key])
		end
	end
end
do
	local dock = {
		["Right"] = RIGHT,
		["Left"] = LEFT,
		["Bottom"] = BOTTOM,
		["Top"] = TOP,
		["Fill"] = FILL
	}
	local Dock = PANEL.Dock
	PANEL.GWEN_SetDock = function(self, key)
		if dock[key] then
			return Dock(self, dock[key])
		end
	end
end
do
	local SetText = PANEL.SetText
	PANEL.GWEN_SetCheckboxText = function(self, tbl)
		return SetText(self, tbl)
	end
end
