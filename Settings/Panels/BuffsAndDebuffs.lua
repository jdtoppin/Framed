local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- Layout constants
-- ============================================================

local PANE_TITLE_H = 20
local SLIDER_H     = 26
local SWITCH_H     = 22
local DROPDOWN_H   = 22
local CHECK_H      = 14
local SPELL_LIST_H = 120
local SPELL_INPUT_H = 44   -- INPUT_ROW_HEIGHT(24) + tight(8) + PREVIEW_HEIGHT(20) - ~8
local WIDGET_W     = 220

-- ============================================================
-- Helpers
-- ============================================================

local function createSection(content, title, width, yOffset)
	local pane = Widgets.CreateTitledPane(content, title, width)
	pane:ClearAllPoints()
	Widgets.SetPoint(pane, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return pane, yOffset - PANE_TITLE_H - C.Spacing.normal
end

local function placeWidget(widget, pane, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', pane, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

local function rowLabel(content, text, pane, yOffset)
	local lbl = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textNormal)
	lbl:ClearAllPoints()
	Widgets.SetPoint(lbl, 'TOPLEFT', pane, 'TOPLEFT', 0, yOffset)
	lbl:SetText(text)
	return lbl
end

-- ============================================================
-- Config helpers
-- ============================================================

local function getAura(key)
	return F.Config and F.Config:Get('auras.' .. key)
end
local function setAura(key, value)
	if(F.Config) then
		F.Config:Set('auras.' .. key, value)
	end
	if(F.EventBus) then
		F.EventBus:Fire('CONFIG_CHANGED:auras')
	end
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'buffsanddebuffs',
	label   = 'Buffs and Debuffs',
	section = 'AURAS',
	order   = 10,
	create  = function(parent)
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parent:GetWidth(),
			parent:GetHeight())
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		local width   = parent:GetWidth() - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ============================================================
		-- Raid Debuffs
		-- ============================================================
		local rdPane
		rdPane, yOffset = createSection(content, 'Raid Debuffs', width, yOffset)

		-- Filter mode switch (Encounter Only / Raid)
		local filterSwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
			{ text = 'Encounter Only', value = C.DebuffFilterMode and C.DebuffFilterMode.ENCOUNTER_ONLY or 'EncounterOnly' },
			{ text = 'Raid',           value = C.DebuffFilterMode and C.DebuffFilterMode.RAID           or 'Raid' },
		})
		yOffset = placeWidget(filterSwitch, rdPane, yOffset, SWITCH_H)
		local savedFilter = getAura('raidDebuffs.filterMode')
		if(savedFilter) then filterSwitch:SetValue(savedFilter) end
		filterSwitch:SetOnSelect(function(value)
			setAura('raidDebuffs.filterMode', value)
		end)

		-- Min priority dropdown
		rowLabel(content, 'Min Priority', rdPane, yOffset - DROPDOWN_H / 2 + C.Spacing.base)
		local priorityDD = Widgets.CreateDropdown(content, WIDGET_W)
		priorityDD:SetItems({
			{ text = 'Trivial',   value = C.DebuffPriority and C.DebuffPriority.TRIVIAL   or 1 },
			{ text = 'Low',       value = C.DebuffPriority and C.DebuffPriority.LOW       or 2 },
			{ text = 'Normal',    value = C.DebuffPriority and C.DebuffPriority.NORMAL    or 3 },
			{ text = 'Important', value = C.DebuffPriority and C.DebuffPriority.IMPORTANT or 4 },
			{ text = 'Critical',  value = C.DebuffPriority and C.DebuffPriority.CRITICAL  or 5 },
			{ text = 'Survival',  value = C.DebuffPriority and C.DebuffPriority.SURVIVAL  or 6 },
		})
		yOffset = placeWidget(priorityDD, rdPane, yOffset, DROPDOWN_H)
		local savedPriority = getAura('raidDebuffs.minPriority')
		if(savedPriority) then priorityDD:SetValue(savedPriority) end
		priorityDD:SetOnSelect(function(value)
			setAura('raidDebuffs.minPriority', value)
		end)

		-- Custom spell additions
		local rdSpellList = Widgets.CreateSpellList(content, width, SPELL_LIST_H)
		yOffset = placeWidget(rdSpellList, rdPane, yOffset, SPELL_LIST_H)
		local savedRDSpells = getAura('raidDebuffs.custom')
		if(savedRDSpells) then rdSpellList:SetSpells(savedRDSpells) end
		rdSpellList:SetOnChanged(function(spells)
			setAura('raidDebuffs.custom', spells)
		end)

		local rdInput = Widgets.CreateSpellInput(content, width)
		rdInput:SetSpellList(rdSpellList)
		yOffset = placeWidget(rdInput, rdPane, yOffset, SPELL_INPUT_H)

		-- ============================================================
		-- Dispellable
		-- ============================================================
		local dispPane
		dispPane, yOffset = createSection(content, 'Dispellable', width, yOffset)

		local dispCheck = Widgets.CreateCheckButton(content, 'Enable dispellable glow', function(checked)
			setAura('dispellable.enabled', checked)
		end)
		yOffset = placeWidget(dispCheck, dispPane, yOffset, CHECK_H)
		local savedDispEnabled = getAura('dispellable.enabled')
		if(savedDispEnabled ~= nil) then dispCheck:SetChecked(savedDispEnabled) end

		local glowDD = Widgets.CreateDropdown(content, WIDGET_W)
		glowDD:SetItems({
			{ text = 'Proc',  value = C.GlowType and C.GlowType.PROC  or 'Proc' },
			{ text = 'Pixel', value = C.GlowType and C.GlowType.PIXEL or 'Pixel' },
			{ text = 'Soft',  value = C.GlowType and C.GlowType.SOFT  or 'Soft' },
		})
		yOffset = placeWidget(glowDD, dispPane, yOffset, DROPDOWN_H)
		local savedGlow = getAura('dispellable.glowType')
		if(savedGlow) then glowDD:SetValue(savedGlow) end
		glowDD:SetOnSelect(function(value)
			setAura('dispellable.glowType', value)
		end)

		-- ============================================================
		-- General Buffs
		-- ============================================================
		local buffPane
		buffPane, yOffset = createSection(content, 'General Buffs', width, yOffset)

		local buffMaxSlider = Widgets.CreateSlider(content, 'Max Icons', WIDGET_W, 1, 40, 1)
		yOffset = placeWidget(buffMaxSlider, buffPane, yOffset, SLIDER_H)
		local savedBuffMax = getAura('buffs.maxIcons')
		buffMaxSlider:SetValue(savedBuffMax or 16)
		buffMaxSlider:SetAfterValueChanged(function(value)
			setAura('buffs.maxIcons', value)
		end)

		local buffSizeSlider = Widgets.CreateSlider(content, 'Icon Size', WIDGET_W, 12, 48, 1)
		yOffset = placeWidget(buffSizeSlider, buffPane, yOffset, SLIDER_H)
		local savedBuffSize = getAura('buffs.iconSize')
		buffSizeSlider:SetValue(savedBuffSize or 20)
		buffSizeSlider:SetAfterValueChanged(function(value)
			setAura('buffs.iconSize', value)
		end)

		local buffDisplaySwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
			{ text = 'Spell Icon',     value = C.IconDisplay and C.IconDisplay.SPELL_ICON     or 'SpellIcon' },
			{ text = 'Colored Square', value = C.IconDisplay and C.IconDisplay.COLORED_SQUARE or 'ColoredSquare' },
		})
		yOffset = placeWidget(buffDisplaySwitch, buffPane, yOffset, SWITCH_H)
		local savedBuffDisplay = getAura('buffs.displayType')
		if(savedBuffDisplay) then buffDisplaySwitch:SetValue(savedBuffDisplay) end
		buffDisplaySwitch:SetOnSelect(function(value)
			setAura('buffs.displayType', value)
		end)

		local buffGrowDD = Widgets.CreateDropdown(content, WIDGET_W)
		buffGrowDD:SetItems({
			{ text = 'Right', value = 'RIGHT' },
			{ text = 'Left',  value = 'LEFT' },
			{ text = 'Up',    value = 'UP' },
			{ text = 'Down',  value = 'DOWN' },
		})
		yOffset = placeWidget(buffGrowDD, buffPane, yOffset, DROPDOWN_H)
		local savedBuffGrow = getAura('buffs.growDirection')
		if(savedBuffGrow) then buffGrowDD:SetValue(savedBuffGrow) end
		buffGrowDD:SetOnSelect(function(value)
			setAura('buffs.growDirection', value)
		end)

		-- ============================================================
		-- General Debuffs
		-- ============================================================
		local debuffPane
		debuffPane, yOffset = createSection(content, 'General Debuffs', width, yOffset)

		local debuffMaxSlider = Widgets.CreateSlider(content, 'Max Icons', WIDGET_W, 1, 40, 1)
		yOffset = placeWidget(debuffMaxSlider, debuffPane, yOffset, SLIDER_H)
		local savedDebuffMax = getAura('debuffs.maxIcons')
		debuffMaxSlider:SetValue(savedDebuffMax or 8)
		debuffMaxSlider:SetAfterValueChanged(function(value)
			setAura('debuffs.maxIcons', value)
		end)

		local debuffSizeSlider = Widgets.CreateSlider(content, 'Icon Size', WIDGET_W, 12, 48, 1)
		yOffset = placeWidget(debuffSizeSlider, debuffPane, yOffset, SLIDER_H)
		local savedDebuffSize = getAura('debuffs.iconSize')
		debuffSizeSlider:SetValue(savedDebuffSize or 20)
		debuffSizeSlider:SetAfterValueChanged(function(value)
			setAura('debuffs.iconSize', value)
		end)

		local debuffDisplaySwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
			{ text = 'Spell Icon',     value = C.IconDisplay and C.IconDisplay.SPELL_ICON     or 'SpellIcon' },
			{ text = 'Colored Square', value = C.IconDisplay and C.IconDisplay.COLORED_SQUARE or 'ColoredSquare' },
		})
		yOffset = placeWidget(debuffDisplaySwitch, debuffPane, yOffset, SWITCH_H)
		local savedDebuffDisplay = getAura('debuffs.displayType')
		if(savedDebuffDisplay) then debuffDisplaySwitch:SetValue(savedDebuffDisplay) end
		debuffDisplaySwitch:SetOnSelect(function(value)
			setAura('debuffs.displayType', value)
		end)

		local debuffGrowDD = Widgets.CreateDropdown(content, WIDGET_W)
		debuffGrowDD:SetItems({
			{ text = 'Right', value = 'RIGHT' },
			{ text = 'Left',  value = 'LEFT' },
			{ text = 'Up',    value = 'UP' },
			{ text = 'Down',  value = 'DOWN' },
		})
		yOffset = placeWidget(debuffGrowDD, debuffPane, yOffset, DROPDOWN_H)
		local savedDebuffGrow = getAura('debuffs.growDirection')
		if(savedDebuffGrow) then debuffGrowDD:SetValue(savedDebuffGrow) end
		debuffGrowDD:SetOnSelect(function(value)
			setAura('debuffs.growDirection', value)
		end)

		-- ============================================================
		-- Missing Buffs
		-- ============================================================
		local mbPane
		mbPane, yOffset = createSection(content, 'Missing Buffs', width, yOffset)

		local mbCheck = Widgets.CreateCheckButton(content, 'Track missing buffs', function(checked)
			setAura('missingBuffs.enabled', checked)
		end)
		yOffset = placeWidget(mbCheck, mbPane, yOffset, CHECK_H)
		local savedMBEnabled = getAura('missingBuffs.enabled')
		if(savedMBEnabled ~= nil) then mbCheck:SetChecked(savedMBEnabled) end

		local mbSpellList = Widgets.CreateSpellList(content, width, SPELL_LIST_H)
		yOffset = placeWidget(mbSpellList, mbPane, yOffset, SPELL_LIST_H)
		local savedMBSpells = getAura('missingBuffs.spells')
		if(savedMBSpells) then mbSpellList:SetSpells(savedMBSpells) end
		mbSpellList:SetOnChanged(function(spells)
			setAura('missingBuffs.spells', spells)
		end)

		local mbInput = Widgets.CreateSpellInput(content, width)
		mbInput:SetSpellList(mbSpellList)
		yOffset = placeWidget(mbInput, mbPane, yOffset, SPELL_INPUT_H)

		-- ============================================================
		-- Targeted Spells
		-- ============================================================
		local tsPane
		tsPane, yOffset = createSection(content, 'Targeted Spells', width, yOffset)

		local tsCheck = Widgets.CreateCheckButton(content, 'Enable targeted spell tracking', function(checked)
			setAura('targetedSpells.enabled', checked)
		end)
		yOffset = placeWidget(tsCheck, tsPane, yOffset, CHECK_H)
		local savedTSEnabled = getAura('targetedSpells.enabled')
		if(savedTSEnabled ~= nil) then tsCheck:SetChecked(savedTSEnabled) end

		local tsDisplaySwitch = Widgets.CreateSwitch(content, WIDGET_W, SWITCH_H, {
			{ text = 'Icon',   value = 'Icon' },
			{ text = 'Border', value = 'Border' },
			{ text = 'Both',   value = 'Both' },
		})
		yOffset = placeWidget(tsDisplaySwitch, tsPane, yOffset, SWITCH_H)
		local savedTSDisplay = getAura('targetedSpells.displayMode')
		if(savedTSDisplay) then tsDisplaySwitch:SetValue(savedTSDisplay) end
		tsDisplaySwitch:SetOnSelect(function(value)
			setAura('targetedSpells.displayMode', value)
		end)

		local tsSizeSlider = Widgets.CreateSlider(content, 'Icon Size', WIDGET_W, 12, 48, 1)
		yOffset = placeWidget(tsSizeSlider, tsPane, yOffset, SLIDER_H)
		local savedTSSize = getAura('targetedSpells.iconSize')
		tsSizeSlider:SetValue(savedTSSize or 20)
		tsSizeSlider:SetAfterValueChanged(function(value)
			setAura('targetedSpells.iconSize', value)
		end)

		-- ============================================================
		-- Private Auras
		-- ============================================================
		local paPane
		paPane, yOffset = createSection(content, 'Private Auras', width, yOffset)

		local paCheck = Widgets.CreateCheckButton(content, 'Enable private aura display', function(checked)
			setAura('privateAuras.enabled', checked)
		end)
		yOffset = placeWidget(paCheck, paPane, yOffset, CHECK_H)
		local savedPAEnabled = getAura('privateAuras.enabled')
		if(savedPAEnabled ~= nil) then paCheck:SetChecked(savedPAEnabled) end

		local paSizeSlider = Widgets.CreateSlider(content, 'Icon Size', WIDGET_W, 12, 64, 1)
		yOffset = placeWidget(paSizeSlider, paPane, yOffset, SLIDER_H)
		local savedPASize = getAura('privateAuras.iconSize')
		paSizeSlider:SetValue(savedPASize or 32)
		paSizeSlider:SetAfterValueChanged(function(value)
			setAura('privateAuras.iconSize', value)
		end)

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
