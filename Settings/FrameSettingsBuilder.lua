local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- FrameSettingsBuilder
-- Shared factory that builds a scrollable settings panel for a
-- given unit type. Called by each thin panel registration file.
-- Group types (party/raid/battleground/worldraid) show extra
-- group-specific fields (spacing, orientation, growth direction).
-- ============================================================

F.FrameSettingsBuilder = {}

-- ============================================================
-- Constants
-- ============================================================

local GROUP_TYPES = {
	party        = true,
	raid         = true,
	battleground = true,
	worldraid    = true,
	pinned       = true,
}

-- Unit types whose health bar uses oUF's full UpdateColor chain.
-- These frames do NOT show the Health Bar Color section in settings.
local NPC_FRAME_TYPES = {
	target       = true,
	targettarget = true,
	focus        = true,
	pet          = true,
	boss         = true,
}

-- Expose for card builders
F.FrameSettingsBuilder.GROUP_TYPES     = GROUP_TYPES
F.FrameSettingsBuilder.NPC_FRAME_TYPES = NPC_FRAME_TYPES

local sessionActiveCard = {}

-- Widget heights (used for vertical layout accounting)
local SLIDER_H       = 26   -- labelH(14) + TRACK_THICKNESS(6) + 6
local SWITCH_H       = 22
local DROPDOWN_H     = 22
local CHECK_H        = 14
local PANE_TITLE_H   = 20   -- approx title font + separator + gap

-- Width for sliders and dropdowns inside the panel
local WIDGET_W       = 220

-- Shared layout constants for card builders
F.FrameSettingsBuilder.SLIDER_H     = SLIDER_H
F.FrameSettingsBuilder.SWITCH_H     = SWITCH_H
F.FrameSettingsBuilder.DROPDOWN_H   = DROPDOWN_H
F.FrameSettingsBuilder.CHECK_H      = CHECK_H
F.FrameSettingsBuilder.PANE_TITLE_H = PANE_TITLE_H
F.FrameSettingsBuilder.WIDGET_W     = WIDGET_W

-- ============================================================
-- Layout helpers
-- ============================================================

--- Place a widget at the running yOffset, anchored to the scroll content frame.
--- Returns the next yOffset after accounting for the widget's height.
--- @param widget  Frame   Widget to position
--- @param content Frame   Scroll content frame
--- @param yOffset number  Running yOffset (negative, relative to content)
--- @param height  number  Widget height
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceWidget(widget, content, yOffset, height)
	widget:ClearAllPoints()
	Widgets.SetPoint(widget, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height - C.Spacing.normal
end

--- Place a heading at the given level and return the updated yOffset.
--- @param content Frame   Scroll content frame
--- @param text    string  Heading text
--- @param level   number  1, 2, or 3
--- @param yOffset number  Running yOffset
--- @param width?  number  Available width (needed for level 1 separator)
--- @return number nextYOffset
function F.FrameSettingsBuilder.PlaceHeading(content, text, level, yOffset, width)
	local heading, height = Widgets.CreateHeading(content, text, level, width)
	heading:ClearAllPoints()
	Widgets.SetPoint(heading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
	return yOffset - height
end

-- ============================================================
-- Pinned row width split
-- ============================================================

local SOLO_TYPES = { player = true, target = true, targettarget = true, focus = true, pet = true }
local GROUP_COUNTS = { party = 5, arena = 3, boss = 4, pinned = 9 }

function F.FrameSettingsBuilder.ComputePinnedSplit(totalW, gap, unitType, previewPad)
	local config = F.Config:Get('presets.' .. (F.Settings.GetEditingPreset() or 'Solo') .. '.unitConfigs.' .. unitType)
	if(not config) then
		local pw = math.floor(totalW * 0.5)
		return pw, totalW - pw - gap
	end

	-- PREVIEW_INSET_2 mirrors FramePreview.PREVIEW_INSET * 2 (4 * 2). naturalH
	-- here must match RebuildPreview's naturalH *exactly* — otherwise the
	-- previewScale we compute diverges from the scale the viewport actually
	-- applies, and the card ends up sized for one scale while rendering at
	-- another. The visible symptom is a right-side gap between the last frame
	-- and the card edge.
	local PREVIEW_INSET_2 = 8

	local naturalW, naturalH
	local MAX_PREVIEW_H = 120
	local cbExtra = 0
	if(config.showCastBar ~= false and config.castbar) then
		cbExtra = config.castbar.height + (C.Spacing.base or 4)
	end

	if(SOLO_TYPES[unitType]) then
		naturalW = config.width
		naturalH = (config.height or 60) + cbExtra + PREVIEW_INSET_2
	else
		local count = unitType == 'raid' and (F.Config:GetChar('settings.raidPreviewCount') or 8)
			or GROUP_COUNTS[unitType] or 5
		local upc = config.unitsPerColumn or count
		local cols = math.ceil(count / upc)
		local isVertical = config.orientation == 'vertical'
		local rows = math.min(count, upc)
		if(isVertical) then
			naturalW = cols * config.width + (cols - 1) * (config.spacing or 2)
		else
			naturalW = rows * config.width + (rows - 1) * (config.spacing or 2)
		end
		-- Match RebuildPreview: each row includes its own castbar, plus spacing
		-- between rows and the outer viewport insets. cbExtra applies per row
		-- because the castbar anchors below each frame (TOP → frame BOTTOM).
		naturalH = rows * ((config.height or 60) + cbExtra) + (rows - 1) * (config.spacing or 2) + PREVIEW_INSET_2
	end

	if(config.portrait) then
		naturalW = naturalW + (config.height or 60) + (C.Spacing.base or 4)
	end

	-- Scale to fit both the vertical cap (MAX_PREVIEW_H) and the horizontal
	-- cap (0.6 * totalW minus the card's inner padding). Without the
	-- horizontal cap, naturally-wide content (e.g. raid count 40) either
	-- pushed the card past its share of the row and spilled the summary
	-- past the settings window's right edge, or — once previewW was clamped
	-- to the 0.6 ceiling — the frames rendered wider than innerW and
	-- visibly clipped on the right.
	local ceil6 = math.max(1, math.floor(totalW * 0.6))
	local maxInnerW = math.max(1, ceil6 - previewPad * 2)
	local vScale = (naturalH > MAX_PREVIEW_H) and (MAX_PREVIEW_H / naturalH) or 1
	local hScale = (naturalW > 0) and (maxInnerW / naturalW) or 1
	local previewScale = math.min(vScale, hScale)
	local scaledW = math.ceil(naturalW * previewScale)

	local previewW = scaledW + previewPad * 2
	-- Raid auto-sizes with count (via the raidPreviewCount stepper), so keep its
	-- old small floor — a larger floor would pin the card at a fixed width and
	-- defeat the auto-size on count changes below ~30.
	-- Other units have fixed counts and narrow content (boss/party width ~120–160),
	-- so their card would otherwise collapse to a width too small for the title +
	-- Focus Mode toggle on the header row. Floor them at 40% of totalW (capped at
	-- the 60% ceiling) so titles fit without stretching content.
	local widthFloor
	if(unitType == 'raid') then
		widthFloor = math.min(112, ceil6)
	else
		widthFloor = math.min(math.floor(totalW * 0.4), ceil6)
	end
	previewW = math.max(previewW, widthFloor)
	local summaryW = totalW - previewW - gap

	-- Force the summary to stay 2-col-capable on narrow totals. The summary's
	-- column count is discrete (innerW >= SUMMARY_2COL_MIN_INNER → 2 cols, else
	-- 1 col), and a 1-col summary hides most rows below the fold. The preview,
	-- by contrast, scales continuously via SetScale(innerW / naturalW), so
	-- stealing width from it just shrinks the preview frames — exactly the
	-- trade-off we want. PREVIEW_HARD_MIN keeps the preview card's border /
	-- title legible; below it, we'd rather the summary fall back to 1 col than
	-- render a preview too small to read.
	local SUMMARY_2COL_MIN = F.FrameSettingsBuilder.SUMMARY_2COL_MIN_INNER
		+ F.FrameSettingsBuilder.SUMMARY_CARD_PAD * 2
	local PREVIEW_HARD_MIN = 80
	if(summaryW < SUMMARY_2COL_MIN) then
		local targetSummary = math.min(SUMMARY_2COL_MIN, totalW - PREVIEW_HARD_MIN - gap)
		if(targetSummary > summaryW) then
			summaryW = targetSummary
			previewW = totalW - summaryW - gap
		end
	end

	return previewW, summaryW
end

-- ============================================================
-- Summary Card
-- ============================================================

local SUMMARY_ROW_H = 16
local ICON_SIZE = 12
local SUMMARY_CARD_PAD = 10
-- innerW threshold for 2-col layout in BuildSummaryCard's layoutRows.
-- Exported so ComputePinnedSplit can guarantee the summary always gets
-- enough width to render at least 2 columns.
local SUMMARY_2COL_MIN_INNER = 180

F.FrameSettingsBuilder.SUMMARY_CARD_PAD        = SUMMARY_CARD_PAD
F.FrameSettingsBuilder.SUMMARY_2COL_MIN_INNER  = SUMMARY_2COL_MIN_INNER

local GROUP_ICON_TYPES = { party = true, raid = true, arena = true, pinned = true }

-- Icon-row definitions mirror Settings/Cards/StatusIcons.lua so the summary
-- surfaces the same individual toggles (filtered per unit via IconRelevance).
local GROUP_ICON_ROWS = {
	{ key = 'role',       label = 'Role Icon',      defaultOn = true  },
	{ key = 'leader',     label = 'Leader Icon',    defaultOn = true  },
	{ key = 'raidRole',   label = 'Raid Role Icon', defaultOn = false },
}
local STATUS_ICON_ROWS = {
	{ key = 'readyCheck', label = 'Ready Check',    defaultOn = true  },
	{ key = 'combat',     label = 'Combat Icon',    defaultOn = false },
	{ key = 'resting',    label = 'Resting Icon',   defaultOn = false },
	{ key = 'phase',      label = 'Phase Icon',     defaultOn = false },
	{ key = 'resurrect',  label = 'Resurrect Icon', defaultOn = false },
	{ key = 'summon',     label = 'Summon Icon',    defaultOn = false },
}
local MARKER_ICON_ROWS = {
	{ key = 'raidIcon',   label = 'Raid Icon',      defaultOn = true  },
	{ key = 'pvp',        label = 'PvP Icon',       defaultOn = false },
}

local function appendIconRows(items, unitType, cardId, defs)
	local relevance = F.Settings and F.Settings.IconRelevance and F.Settings.IconRelevance[unitType]
	for _, def in next, defs do
		if(not relevance or relevance[def.key]) then
			items[#items + 1] = {
				id        = cardId .. ':' .. def.key,
				cardId    = cardId,
				label     = def.label,
				key       = 'statusIcons.' .. def.key,
				defaultOn = def.defaultOn,
			}
		end
	end
end

local function getSummaryItems(unitType)
	local items = {
		{ id = 'position',    label = 'Position & Layout' },
		{ id = 'healthColor', label = 'Portrait & Color' },
	}

	-- Shields & Absorbs (unbundled into 4 individual toggles, all default-on)
	items[#items + 1] = { id = 'shields:healPrediction', cardId = 'shields', label = 'Heal Prediction', key = 'health.healPrediction', defaultOn = true }
	items[#items + 1] = { id = 'shields:damageAbsorb',   cardId = 'shields', label = 'Shields',         key = 'health.damageAbsorb',   defaultOn = true }
	items[#items + 1] = { id = 'shields:healAbsorb',     cardId = 'shields', label = 'Heal Absorbs',    key = 'health.healAbsorb',     defaultOn = true }
	items[#items + 1] = { id = 'shields:overAbsorb',     cardId = 'shields', label = 'Overshield',      key = 'health.overAbsorb',     defaultOn = true }

	items[#items + 1] = { id = 'power',      label = 'Power Bar',   key = 'showPower'       }
	items[#items + 1] = { id = 'castbar',    label = 'Cast Bar',    key = 'showCastBar'     }
	items[#items + 1] = { id = 'name',       label = 'Name Text',   key = 'showName'        }
	items[#items + 1] = { id = 'healthText', label = 'Health Text', key = 'health.showText' }
	items[#items + 1] = { id = 'powerText',  label = 'Power Text',  key = 'power.showText'  }

	if(GROUP_ICON_TYPES[unitType]) then
		appendIconRows(items, unitType, 'groupIcons', GROUP_ICON_ROWS)
		items[#items + 1] = { id = 'statusText', label = 'Status Text', key = 'statusText.enabled' }
	end

	appendIconRows(items, unitType, 'statusIcons', STATUS_ICON_ROWS)
	appendIconRows(items, unitType, 'markers',     MARKER_ICON_ROWS)

	if(unitType == 'party' or unitType == 'raid') then
		items[#items + 1] = { id = 'sorting', label = 'Sorting' }
	end

	if(unitType == 'party') then
		-- Party Pets lives at preset scope (not unitConfigs), so use a custom accessor.
		items[#items + 1] = {
			id        = 'partyPets',
			label     = 'Party Pets',
			defaultOn = true,
			customGet = function()
				local preset = F.Settings.GetEditingPreset()
				return F.Config:Get('presets.' .. preset .. '.partyPets.enabled') ~= false
			end,
			customSet = function(value)
				local preset = F.Settings.GetEditingPreset()
				F.Config:Set('presets.' .. preset .. '.partyPets.enabled', value)
				F.PresetManager.MarkCustomized(preset)
			end,
		}
	end

	return items
end

local function isKeyed(item)
	return item.key ~= nil or item.keys ~= nil or item.customGet ~= nil
end

local function isFeatureEnabled(getConfig, item)
	if(item.customGet) then
		return item.customGet() and true or false
	end
	if(item.key) then
		if(item.defaultOn) then
			return getConfig(item.key) ~= false
		end
		return getConfig(item.key) and true or false
	end
	if(item.keys) then
		for _, k in next, item.keys do
			if(getConfig(k)) then return true end
		end
		return false
	end
	return nil
end

function F.FrameSettingsBuilder.BuildSummaryCard(parent, width, unitType, getConfig, setConfig)
	local card = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
	card:SetBackdrop({
		bgFile   = [[Interface\BUTTONS\WHITE8x8]],
		edgeFile = [[Interface\BUTTONS\WHITE8x8]],
		edgeSize = 1,
		insets   = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local bg = C.Colors.card
	local border = C.Colors.cardBorder
	card:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	card:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
	card:SetWidth(width)
	Widgets.CreateAccentBar(card, 'top')

	local pad = SUMMARY_CARD_PAD
	local badgeText = Widgets.CreateFontString(card, C.Font.sizeSmall, C.Colors.textSecondary)
	badgeText:SetPoint('TOPRIGHT', card, 'TOPRIGHT', -pad, -pad - 1)

	-- Title shares the header row with the badge. Bound its right edge to
	-- the badge's left so the title ellipsis-truncates when the card is
	-- narrow instead of overlapping the "N of M enabled" count.
	local titleText = Widgets.CreateFontString(card, C.Font.sizeNormal, C.Colors.textActive)
	titleText:SetPoint('TOPLEFT', card, 'TOPLEFT', pad, -pad)
	titleText:SetPoint('RIGHT', badgeText, 'LEFT', -C.Spacing.base, 0)
	titleText:SetJustifyH('LEFT')
	titleText:SetWordWrap(false)
	titleText:SetText('Quick Navigation')

	local titleH = C.Font.sizeNormal + 6

	local items = getSummaryItems(unitType)

	local rowByID = {}

	local function toggleItem(item)
		local cur = isFeatureEnabled(getConfig, item)
		local newVal = not cur
		if(item.customSet) then
			item.customSet(newVal)
		elseif(item.key and setConfig) then
			setConfig(item.key, newVal)
		end
		card:Refresh()
	end

	for _, item in next, items do
		local rowFrame = CreateFrame('Button', nil, card)
		rowFrame:SetSize(width - pad * 2, SUMMARY_ROW_H)

		local enabled = isFeatureEnabled(getConfig, item)
		local keyed = isKeyed(item)

		-- Icon: clickable Button for keyed rows, decorative Texture otherwise.
		-- The icon Button sits above the row Button, so clicks on it don't
		-- bubble into the row's scroll handler — users get one gesture per zone.
		local iconTex
		local iconBtn
		if(keyed) then
			iconBtn = CreateFrame('Button', nil, rowFrame)
			iconBtn:SetSize(ICON_SIZE + 4, SUMMARY_ROW_H)
			iconBtn:SetPoint('LEFT', rowFrame, 'LEFT', -2, 0)

			iconTex = iconBtn:CreateTexture(nil, 'ARTWORK')
			iconTex:SetSize(ICON_SIZE, ICON_SIZE)
			iconTex:SetPoint('CENTER', iconBtn, 'CENTER', 0, 0)

			iconBtn:SetHighlightTexture([[Interface\BUTTONS\WHITE8x8]], 'ADD')
			local hl = iconBtn:GetHighlightTexture()
			hl:SetVertexColor(1, 1, 1, 0.12)
			hl:SetAllPoints(iconBtn)

			iconBtn:SetScript('OnEnter', function(self)
				GameTooltip:SetOwner(self, 'ANCHOR_TOPLEFT')
				GameTooltip:SetText('Click to toggle', 1, 1, 1)
				GameTooltip:Show()
			end)
			iconBtn:SetScript('OnLeave', function() GameTooltip:Hide() end)
			iconBtn:SetScript('OnClick', function() toggleItem(item) end)
		else
			iconTex = rowFrame:CreateTexture(nil, 'ARTWORK')
			iconTex:SetSize(ICON_SIZE, ICON_SIZE)
			iconTex:SetPoint('LEFT', rowFrame, 'LEFT', 0, 0)
		end

		if(enabled == false) then
			iconTex:SetTexture(F.Media.GetIcon('Fluent_Color_No'))
			iconTex:SetAlpha(0.6)
		elseif(enabled == nil) then
			iconTex:SetTexture(F.Media.GetIcon('Settings'))
			iconTex:SetAlpha(0.5)
		else
			iconTex:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
			iconTex:SetAlpha(1)
		end

		local label = Widgets.CreateFontString(rowFrame, C.Font.sizeSmall,
			enabled == false and C.Colors.textDisabled or C.Colors.textNormal)
		-- Bound to both edges so long labels truncate within the row
		-- instead of spilling past the card/panel on narrow widths.
		-- SUMMARY_ROW_H is fixed at 16, so wrap must stay off — we
		-- truncate with "..." rather than growing a second line.
		label:SetPoint('LEFT', rowFrame, 'LEFT', ICON_SIZE + 6, 0)
		label:SetPoint('RIGHT', rowFrame, 'RIGHT', -2, 0)
		label:SetJustifyH('LEFT')
		label:SetWordWrap(false)
		label:SetText(item.label)

		rowFrame:SetScript('OnClick', function()
			if(card._onItemClicked) then
				card._onItemClicked(item.cardId or item.id)
			end
		end)

		rowFrame:SetScript('OnEnter', function(self)
			label:SetTextColor(1, 1, 1, 1)
		end)
		rowFrame:SetScript('OnLeave', function(self)
			local tc = rowFrame._enabled == false and C.Colors.textDisabled or C.Colors.textNormal
			label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end)

		rowFrame._icon = iconTex
		rowFrame._label = label
		rowFrame._item = item
		rowFrame._enabled = enabled
		rowByID[item.id] = rowFrame
	end

	-- Group rows by their cardId so Reorder (which receives card-level ids from
	-- the grid) can fan each id out to all of its unbundled summary rows.
	local rowsByCardId = {}
	local cardIdOrder = {}
	local seenCardId = {}
	for _, item in next, items do
		local cid = item.cardId or item.id
		if(not rowsByCardId[cid]) then
			rowsByCardId[cid] = {}
		end
		rowsByCardId[cid][#rowsByCardId[cid] + 1] = rowByID[item.id]
		if(not seenCardId[cid]) then
			seenCardId[cid] = true
			cardIdOrder[#cardIdOrder + 1] = cid
		end
	end

	local function updateBadge()
		local enabledCount, total = 0, 0
		for _, rf in next, rowByID do
			if(isKeyed(rf._item)) then
				total = total + 1
				if(rf._enabled) then enabledCount = enabledCount + 1 end
			end
		end
		badgeText:SetText(enabledCount .. ' of ' .. total .. ' enabled')
	end
	updateBadge()

	card._rowByID = rowByID

	local COL_GAP = C.Spacing.base
	local function layoutRows(orderedIds, animate)
		local curW = card:GetWidth()
		local innerW = curW - pad * 2
		local cols
		if(innerW >= 340) then
			cols = 3
		elseif(innerW >= SUMMARY_2COL_MIN_INNER) then
			cols = 2
		else
			cols = 1
		end
		local colW = math.floor((innerW - (cols - 1) * COL_GAP) / cols)

		local idx = 0
		local function placeRow(rf)
			rf:SetWidth(colW)
			local col = idx % cols
			local row = math.floor(idx / cols)
			local newX = pad + col * (colW + COL_GAP)
			local newY = -pad - titleH + (-row * (SUMMARY_ROW_H + 2))

			if(animate and rf._posX and (math.abs(rf._posX - newX) > 1 or math.abs(rf._posY - newY) > 1)) then
				local oldX, oldY = rf._posX, rf._posY
				Widgets.StartAnimation(rf, 'reorder', 0, 1, C.Animation.durationNormal, function(self, t)
					self:ClearAllPoints()
					self:SetPoint('TOPLEFT', card, 'TOPLEFT',
						oldX + (newX - oldX) * t,
						oldY + (newY - oldY) * t)
				end, function(self)
					self:ClearAllPoints()
					self:SetPoint('TOPLEFT', card, 'TOPLEFT', newX, newY)
				end)
			else
				rf:ClearAllPoints()
				rf:SetPoint('TOPLEFT', card, 'TOPLEFT', newX, newY)
			end

			rf._posX = newX
			rf._posY = newY
			rf:Show()
			idx = idx + 1
		end

		for _, id in next, orderedIds do
			local rowsForCard = rowsByCardId[id]
			if(rowsForCard) then
				for _, rf in next, rowsForCard do
					placeRow(rf)
				end
			end
		end
		local visibleRows = math.ceil(idx / cols)
		local h = pad * 2 + titleH + visibleRows * SUMMARY_ROW_H + math.max(0, visibleRows - 1) * 2
		card._naturalH = h
		card:SetHeight(h)
	end

	local lastOrderedIds = cardIdOrder
	layoutRows(cardIdOrder, false)

	function card:Reorder(orderedIds)
		lastOrderedIds = orderedIds
		layoutRows(orderedIds, true)
	end

	-- Re-place rows against the card's *current* width without triggering
	-- the reorder animation. Used as the per-frame callback while the
	-- pinned split tweens the summary card narrower — otherwise
	-- rf:SetWidth() stays pinned at the pre-tween colW and row contents
	-- (the labels are LEFT/RIGHT-anchored, so truncation depends on the
	-- row width tracking the card).
	function card:ResizeRowsToWidth()
		layoutRows(lastOrderedIds, false)
	end

	function card:Refresh()
		for _, rf in next, rowByID do
			local en = isFeatureEnabled(getConfig, rf._item)
			rf._enabled = en
			if(en == false) then
				rf._icon:SetTexture(F.Media.GetIcon('Fluent_Color_No'))
				rf._icon:SetAlpha(0.6)
			elseif(en == nil) then
				rf._icon:SetTexture(F.Media.GetIcon('Settings'))
				rf._icon:SetAlpha(0.5)
			else
				rf._icon:SetTexture(F.Media.GetIcon('Fluent_Color_Yes'))
				rf._icon:SetAlpha(1)
			end
			local tc = en == false and C.Colors.textDisabled or C.Colors.textNormal
			rf._label:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
		end
		updateBadge()
	end

	-- Party Pets lives at preset scope and is toggleable from both the summary
	-- (via customSet) and its own card (via F.Config:Set). Card-side writes
	-- don't route through the panel's setConfig, so we listen to CONFIG_CHANGED
	-- to keep the summary in sync when the toggle is flipped on the card.
	-- Owner string dedupes across panel rebuilds (see EventBus:Register).
	F.EventBus:Register('CONFIG_CHANGED', function(path)
		if(path and path:find('%.partyPets%.enabled$') and card:IsShown()) then
			card:Refresh()
		end
	end, 'summaryCard:' .. unitType)

	return card
end

-- ============================================================
-- FrameSettingsBuilder.Create
-- ============================================================

--- Build and return a scrollable settings panel for unitType.
--- @param parent   Frame   Content parent provided by Settings.RegisterPanel
--- @param unitType string  Unit identifier (e.g. 'player', 'party', 'raid')
--- @return Frame
function F.FrameSettingsBuilder.Create(parent, unitType)
	-- ── Scroll frame wrapping the whole panel ─────────────────
	local parentW = parent._explicitWidth or parent:GetWidth() or 530
	local parentH = parent._explicitHeight or parent:GetHeight() or 400
	local scroll = Widgets.CreateScrollFrame(parent, nil, parentW, parentH)
	scroll:SetAllPoints(parent)

	local content = scroll:GetContentFrame()
	local width = parentW - C.Spacing.normal * 2

	-- Tag scroll frame with the preset it was built for (used by callers for invalidation)
	scroll._builtForPreset = F.Settings.GetEditingPreset()

	-- ── Config accessor helpers ────────────────────────────────
	local function getPresetName()
		return F.Settings.GetEditingPreset()
	end

	local function getConfig(key)
		if(F.EditCache and F.EditCache.IsActive()) then
			return F.EditCache.Get(unitType, key)
		end
		return F.Config:Get('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key)
	end
	local summaryCard
	local function setConfig(key, value)
		if(F.EditCache and F.EditCache.IsActive()) then
			F.EditCache.Set(unitType, key, value)
		else
			F.Config:Set('presets.' .. getPresetName() .. '.unitConfigs.' .. unitType .. '.' .. key, value)
			F.PresetManager.MarkCustomized(getPresetName())
		end
		if(summaryCard) then summaryCard:Refresh() end
	end

	-- ── Pinned row: preview card (left) + summary card (right) ──
	local pinnedGap = C.Spacing.tight
	-- Matches Widgets.CARD_PADDING * 2 so the preview card's outer width
	-- equals its content width plus the symmetric inner insets — no
	-- wasted blank space on the right of the frames.
	local PREVIEW_PAD = 12
	local previewW, summaryW = F.FrameSettingsBuilder.ComputePinnedSplit(width, pinnedGap, unitType, PREVIEW_PAD)

	local previewCard = F.Settings.FramePreview.BuildPreviewCard(scroll, previewW, unitType)
	previewCard:ClearAllPoints()
	Widgets.SetPoint(previewCard, 'TOPLEFT', scroll, 'TOPLEFT', 0, -C.Spacing.normal)

	-- Expose a predictor so the raid stepper can resolve the Focus Mode flip
	-- upfront (before RebuildPreview) and have the height + width tweens run
	-- concurrently. Without this, the width tween happens first and then the
	-- Focus Mode flip triggers a follow-up height tween in the opposite
	-- direction — the user perceives this as "grow then shrink" (or vice
	-- versa) instead of one smooth transform.
	previewCard._predictWidth = function()
		local pw = F.FrameSettingsBuilder.ComputePinnedSplit(width, pinnedGap, unitType, PREVIEW_PAD)
		return pw
	end

	summaryCard = F.FrameSettingsBuilder.BuildSummaryCard(
		scroll, summaryW, unitType, getConfig, setConfig
	)
	summaryCard:ClearAllPoints()
	Widgets.SetPoint(summaryCard, 'TOPLEFT', previewCard, 'TOPRIGHT', pinnedGap, 0)

	-- Pair the cards so the preview can match its height to the summary when
	-- the summary is taller (e.g. player-solo, where the preview is only ~54px
	-- but the summary lists 8–10 rows). FramePreview reads _pairedSummaryCard
	-- in its resize path to pin card height to the max of both cards' natural
	-- heights — natural so either card can shrink back when the other shrinks.
	previewCard._pairedSummaryCard = summaryCard
	local function equalizePinnedHeights()
		local pNat = previewCard._naturalH or previewCard:GetHeight()
		local sNat = summaryCard._naturalH or summaryCard:GetHeight()
		local h = math.max(pNat, sNat)
		if(math.abs(previewCard:GetHeight() - h) > 0.5) then previewCard:SetHeight(h) end
		if(math.abs(summaryCard:GetHeight() - h) > 0.5) then summaryCard:SetHeight(h) end
	end
	equalizePinnedHeights()

	local lastPinnedH
	local function anchorScrollBelowPinned()
		equalizePinnedHeights()
		local pinnedH = math.max(previewCard:GetHeight(), summaryCard:GetHeight()) + C.Spacing.normal
		if(lastPinnedH and math.abs(lastPinnedH - pinnedH) < 0.5) then
			return
		end
		lastPinnedH = pinnedH
		scroll._scrollFrame:ClearAllPoints()
		scroll._scrollFrame:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, -(pinnedH + C.Spacing.normal))
		scroll._scrollFrame:SetPoint('BOTTOMRIGHT', scroll, 'BOTTOMRIGHT', -7, 0)
		scroll._viewportOffset = pinnedH + C.Spacing.normal
	end
	anchorScrollBelowPinned()

	-- ── CardGrid orchestrator ──
	local grid = Widgets.CreateCardGrid(content, width)

	local function syncContentHeight()
		content:SetHeight(grid:GetTotalHeight())
	end

	-- Forward mouse wheel from pinned area to vertical scroll
	local function forwardMouseWheel(_, delta)
		local sf = scroll._scrollFrame
		local maxScroll = math.max(0, content:GetHeight() - sf:GetHeight())
		local cur = sf:GetVerticalScroll()
		local newOffset = math.max(0, math.min(maxScroll, cur - delta * 40))
		sf:SetVerticalScroll(newOffset)
		scroll:_UpdateThumb()
		C_Timer.After(0, function()
			local viewH = sf:GetHeight()
			grid:Layout(newOffset, viewH)
			syncContentHeight()
		end)
	end
	previewCard:EnableMouseWheel(true)
	previewCard:SetScript('OnMouseWheel', forwardMouseWheel)
	summaryCard:EnableMouseWheel(true)
	summaryCard:SetScript('OnMouseWheel', forwardMouseWheel)

	-- Forward-declare; defined below.
	local reorderSummary
	-- Forward-declare activeCardId so relayout() (defined below) closes over it.
	-- Without this, relayout reads _G.activeCardId (nil) and the pinning logic
	-- silently falls through to the delta-shift fallback, causing scroll bumps.
	local activeCardId = nil

	-- Refresh the pinned row after preview resizes (portrait, castbar, etc.).
	-- Widths animate over RESIZE_DUR so the cards grow/shrink smoothly instead
	-- of snapping when the pinned split changes.
	previewCard._onResize = function()
		local newPreviewW, newSummaryW = F.FrameSettingsBuilder.ComputePinnedSplit(width, pinnedGap, unitType, PREVIEW_PAD)
		local widthChanged = math.abs(previewCard:GetWidth() - newPreviewW) > 0.5
		if(widthChanged) then
			F.Settings.FramePreview.AnimatePinnedWidths(previewCard, summaryCard,
				newPreviewW, newSummaryW,
				function()
					anchorScrollBelowPinned()
				end)
			if(reorderSummary) then reorderSummary() end
			-- No second RebuildPreview: the preview frames are sized from
			-- config.width (not card width), so the viewport can safely
			-- tween without re-rendering its contents.
		else
			anchorScrollBelowPinned()
		end
	end

	local function relayout()
		local oldContentH = content:GetHeight()
		local oldScroll   = scroll._scrollFrame:GetVerticalScroll()

		local anchorEntry = activeCardId and grid._cardIndex and grid._cardIndex[activeCardId]
		local oldAnchorY = anchorEntry and anchorEntry._layoutY

		grid:AnimatedReflow()
		syncContentHeight()
		scroll:UpdateScrollRange()

		local viewH     = scroll._scrollFrame:GetHeight()
		local maxScroll = math.max(0, content:GetHeight() - viewH)
		local delta     = content:GetHeight() - oldContentH

		local newScroll
		if(oldAnchorY and anchorEntry._layoutY) then
			-- Pin the active card: shift scroll by the same amount the card moved.
			newScroll = oldScroll + (anchorEntry._layoutY - oldAnchorY)
		elseif(delta ~= 0) then
			-- Fallback: keep bottom-anchored content in place.
			newScroll = oldScroll + delta
		else
			newScroll = oldScroll
		end

		newScroll = math.max(0, math.min(newScroll, maxScroll))
		-- Always restore — UpdateScrollRange may have already clamped on shrinkage,
		-- and skipping the Set would leave the view bumped up.
		scroll._scrollFrame:SetVerticalScroll(newScroll)
		scroll:_UpdateThumb()
	end

	-- ── Active card tracking ──────────────────────────────────
	local activeAccentBar = nil
	local FADE_DUR = C.Animation.durationFast

	local defaultBg = C.Colors.card
	local activeBg  = { 0.16, 0.16, 0.16, 1 }
	local hoverBg   = { 0.14, 0.14, 0.14, 1 }

	-- Track each card's current visual RGBA so animations always start from truth
	local cardBgState = {}

	local function getCardBg(card)
		return cardBgState[card] or defaultBg
	end

	local function animateCardBg(card, toBg)
		local from = getCardBg(card)
		local to = toBg
		cardBgState[card] = to
		Widgets.StartAnimation(card, 'cardBg', 0, 1, FADE_DUR, function(self, t)
			self:SetBackdropColor(
				from[1] + (to[1] - from[1]) * t,
				from[2] + (to[2] - from[2]) * t,
				from[3] + (to[3] - from[3]) * t,
				(from[4] or 1) + ((to[4] or 1) - (from[4] or 1)) * t
			)
		end)
	end

	local function animateTextColor(card, fs, fromC, toC)
		Widgets.StartAnimation(card, 'textColor', 0, 1, FADE_DUR, function(self, t)
			fs:SetTextColor(
				fromC[1] + (toC[1] - fromC[1]) * t,
				fromC[2] + (toC[2] - fromC[2]) * t,
				fromC[3] + (toC[3] - fromC[3]) * t,
				(fromC[4] or 1) + ((toC[4] or 1) - (fromC[4] or 1)) * t
			)
		end)
	end

	local function setActiveCard(cardId)
		if(activeCardId == cardId) then return end

		local hadPrev = activeCardId ~= nil

		-- Deactivate previous card
		if(activeCardId) then
			local prev = grid._cardIndex[activeCardId]
			if(prev and prev.built and prev.card) then
				animateCardBg(prev.card, defaultBg)
				if(prev._titleFS) then
					animateTextColor(prev.card, prev._titleFS, C.Colors.textActive, C.Colors.textNormal)
				end
			end
		end

		activeCardId = cardId
		if(cardId) then sessionActiveCard[unitType] = cardId end

		-- Activate new card
		if(cardId) then
			local entry = grid._cardIndex[cardId]
			if(entry and entry.built and entry.card) then
				animateCardBg(entry.card, activeBg)
				if(entry._titleFS) then
					animateTextColor(entry.card, entry._titleFS, C.Colors.textNormal, C.Colors.textActive)
				end

				if(not activeAccentBar) then
					activeAccentBar = CreateFrame('Frame', nil, scroll)
					activeAccentBar:SetWidth(3)
					local tex = activeAccentBar:CreateTexture(nil, 'OVERLAY')
					tex:SetAllPoints(activeAccentBar)
					local ac = C.Colors.accent
					tex:SetColorTexture(ac[1], ac[2], ac[3], 1)
					activeAccentBar._tex = tex
				end
				activeAccentBar:SetParent(entry.card)
				activeAccentBar:ClearAllPoints()
				activeAccentBar:SetPoint('TOPLEFT', entry.card, 'TOPLEFT', 0, 0)
				activeAccentBar:SetPoint('BOTTOMLEFT', entry.card, 'BOTTOMLEFT', 0, 0)
				activeAccentBar:SetFrameLevel(entry.card:GetFrameLevel() + 5)

				if(hadPrev) then
					activeAccentBar:SetAlpha(1)
					activeAccentBar:Show()
				else
					activeAccentBar:SetAlpha(0)
					activeAccentBar:Show()
					Widgets.StartAnimation(activeAccentBar, 'fade', 0, 1, FADE_DUR,
						function(self, v) self:SetAlpha(v) end)
				end
			end
		elseif(activeAccentBar) then
			Widgets.StartAnimation(activeAccentBar, 'fade', activeAccentBar:GetAlpha(), 0, FADE_DUR,
				function(self, v) self:SetAlpha(v) end,
				function(self) self:Hide() end)
		end

		-- Spotlight preview elements when focus mode is on
		F.Settings.FramePreview.OnCardFocused(cardId)
	end

	-- Per-card setConfig wrapper that triggers active state on interaction
	local function makeCardSetConfig(cardId)
		return function(key, value)
			setConfig(key, value)
			setActiveCard(cardId)
		end
	end

	-- Register cards in display order
	grid:AddCard('position', 'Position & Layout', F.SettingsCards.PositionAndLayout, { unitType, getConfig, makeCardSetConfig('position'), relayout })
	if(unitType == 'party' or unitType == 'raid') then
		grid:AddCard('sorting', 'Sorting', F.SettingsCards.Sorting, { unitType, getConfig, makeCardSetConfig('sorting') })
	end

	grid:AddCard('healthColor', 'Portrait & Health Color', F.SettingsCards.HealthColor, { unitType, getConfig, makeCardSetConfig('healthColor'), relayout })

	grid:AddCard('shields', 'Shields & Absorbs', F.SettingsCards.ShieldsAndAbsorbs, { unitType, getConfig, makeCardSetConfig('shields') })
	grid:AddCard('power', 'Power Bar', F.SettingsCards.PowerBar, { unitType, getConfig, makeCardSetConfig('power') })
	grid:AddCard('castbar', 'Cast Bar', F.SettingsCards.CastBar, { unitType, getConfig, makeCardSetConfig('castbar'), relayout })
	grid:AddCard('name', 'Name Text', F.SettingsCards.Name, { unitType, getConfig, makeCardSetConfig('name'), relayout })
	grid:AddCard('healthText', 'Health Text', F.SettingsCards.HealthText, { unitType, getConfig, makeCardSetConfig('healthText'), relayout })
	grid:AddCard('powerText', 'Power Text', F.SettingsCards.PowerText, { unitType, getConfig, makeCardSetConfig('powerText'), relayout })
	-- Icon cards — split by category, filtered by unit type relevance
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('groupIcons', 'Group Icons', F.SettingsCards.GroupIcons, { unitType, getConfig, makeCardSetConfig('groupIcons'), relayout })
	end
	if(GROUP_ICON_TYPES[unitType]) then
		grid:AddCard('statusText', 'Status Text', F.SettingsCards.StatusText, { unitType, getConfig, makeCardSetConfig('statusText'), relayout })
	end
	grid:AddCard('statusIcons', 'Status Icons', F.SettingsCards.StatusIcons, { unitType, getConfig, makeCardSetConfig('statusIcons'), relayout })
	grid:AddCard('markers', 'Markers', F.SettingsCards.Markers, { unitType, getConfig, makeCardSetConfig('markers'), relayout })
	if(unitType == 'party') then
		grid:AddCard('partyPets', 'Party Pets', F.SettingsCards.PartyPets, {})
	end
	if(unitType == 'pinned') then
		grid:AddCard('slotAssignments', 'Slot Assignments', F.SettingsCards.Pinned, {})
	end

	-- ── Persist pin state ─────────────────────────────────────
	reorderSummary = function()
		local sorted = grid:GetSortedCards()
		local ids = {}
		for _, entry in next, sorted do
			ids[#ids + 1] = entry.id
		end
		summaryCard:Reorder(ids)
	end

	grid._onPinChanged = function(cardId, pinned)
		local path = 'general.pinnedCards.' .. unitType .. '.' .. cardId
		F.Config:Set(path, pinned or nil)
		reorderSummary()
	end

	-- ── Pin state ──────────────────────────────────────────────
	local pinnedCards = F.Config:Get('general.pinnedCards.' .. unitType) or {}
	for cardId, isPinned in next, pinnedCards do
		if(isPinned) then
			grid:SetPinned(cardId, true)
		end
	end

	-- ── Initial layout ─────────────────────────────────────────
	grid:Layout(0, parentH)
	syncContentHeight()
	reorderSummary()

	-- ── Card click-to-activate (hooks attached per card on build) ──
	local hookedCards = {}

	local function hookCardInteraction(cid, entry)
		if(hookedCards[cid]) then return end
		hookedCards[cid] = true
		local card = entry.card

		card:HookScript('OnMouseDown', function()
			setActiveCard(cid)
		end)
		card:HookScript('OnEnter', function(self)
			if(activeCardId ~= cid) then
				animateCardBg(self, hoverBg)
			end
		end)
		card:HookScript('OnLeave', function(self)
			if(activeCardId ~= cid) then
				animateCardBg(self, defaultBg)
			end
		end)

		if(card.content) then
			card.content:EnableMouse(true)
			card.content:HookScript('OnMouseDown', function()
				setActiveCard(cid)
			end)
			card.content:HookScript('OnEnter', function()
				if(activeCardId ~= cid) then
					animateCardBg(card, hoverBg)
				end
			end)
			card.content:HookScript('OnLeave', function()
				if(activeCardId ~= cid) then
					animateCardBg(card, defaultBg)
				end
			end)
		end
	end

	grid._onCardBuilt = function(cardId, entry)
		hookCardInteraction(cardId, entry)
	end

	-- Hook any cards already built in the initial layout
	for cardId, entry in next, grid._cardIndex do
		if(entry.built and entry.card) then
			hookCardInteraction(cardId, entry)
		end
	end

	-- ── Auto-select card on first build ──────────────────────
	-- Default to healthColor so the preview shows a visible focus (the health
	-- bar + portrait dim and highlight). Position & Layout has no preview effect,
	-- so selecting it first leaves the preview looking inert.
	local initialCardId = sessionActiveCard[unitType]
	if(not initialCardId and grid._cardIndex.healthColor) then
		initialCardId = 'healthColor'
	end
	if(not initialCardId) then
		local sorted = grid:GetSortedCards()
		if(sorted[1]) then initialCardId = sorted[1].id end
	end
	if(initialCardId) then
		setActiveCard(initialCardId)
	end

	-- ── Wire summary card click-to-jump ──────────────────────
	local function scrollToCard(cardId)
		local entry = grid._cardIndex[cardId]
		if(not entry) then return end

		local targetY = entry._layoutY or 0
		local sf = scroll._scrollFrame
		local viewH = sf:GetHeight()
		local maxScroll = math.max(0, content:GetHeight() - viewH)
		local newScroll = math.min(math.abs(targetY), maxScroll)
		local fromScroll = sf:GetVerticalScroll()

		if(math.abs(newScroll - fromScroll) < 1) then
			sf:SetVerticalScroll(newScroll)
			scroll:_UpdateThumb()
			grid:Layout(newScroll, viewH)
			syncContentHeight()
		else
			Widgets.StartAnimation(scroll, 'scrollJump', 0, 1, C.Animation.durationNormal, function(_, t)
				local cur = fromScroll + (newScroll - fromScroll) * t
				sf:SetVerticalScroll(cur)
				scroll:_UpdateThumb()
				grid:Layout(cur, viewH)
				syncContentHeight()
			end)
		end

		setActiveCard(cardId)
	end

	summaryCard._onItemClicked = scrollToCard

	-- ── Cancel animations on hide, re-layout on show ──────────
	scroll:HookScript('OnHide', function()
		grid:CancelAnimations()
	end)
	scroll:HookScript('OnShow', function()
		F.Settings.FramePreview.RestorePreview(previewCard, unitType)
		grid:Layout(0, parentH, false)
		syncContentHeight()

		local restoreId = sessionActiveCard[unitType]
		if(not restoreId and grid._cardIndex.healthColor) then
			restoreId = 'healthColor'
		end
		if(not restoreId) then
			local sorted = grid:GetSortedCards()
			if(sorted[1]) then restoreId = sorted[1].id end
		end
		if(restoreId and activeCardId ~= restoreId) then
			setActiveCard(restoreId)
		end
	end)

	-- ── Lazy loading on scroll ─────────────────────────────────
	local function onScroll()
		local offset = scroll._scrollFrame:GetVerticalScroll()
		local viewH  = scroll._scrollFrame:GetHeight()
		grid:Layout(offset, viewH)
		syncContentHeight()
	end

	-- OnVerticalScroll fires for *every* scroll change, including the thumb
	-- drag path (which calls SetVerticalScroll directly, not OnMouseWheel).
	-- Hooking here instead of OnMouseWheel makes lazy-loading work for both
	-- input paths.
	scroll._scrollFrame:HookScript('OnVerticalScroll', function()
		C_Timer.After(0, onScroll)
	end)

	-- ── Re-layout on settings window resize ───────────────────
	F.EventBus:Register('SETTINGS_RESIZED', function(newW, newH)
		local totalW = newW - C.Spacing.normal * 2
		-- Rebind the upvalue so _predictWidth / _onResize (which close over
		-- `width`) see the current panel width on subsequent count changes.
		-- Without this, a raid count change after a window resize computes
		-- the pinned split against the stale pre-resize total.
		width = totalW
		grid:SetWidth(totalW)

		local sf = scroll._scrollFrame
		local viewH = sf:GetHeight()
		grid:Layout(0, viewH)
		syncContentHeight()

		local maxScroll = math.max(0, content:GetHeight() - viewH)
		local clamped = math.min(sf:GetVerticalScroll(), maxScroll)
		sf:SetVerticalScroll(clamped)
		grid:Layout(clamped, viewH)
		scroll:_UpdateThumb()

		local newPreviewW, newSummaryW = F.FrameSettingsBuilder.ComputePinnedSplit(totalW, pinnedGap, unitType, PREVIEW_PAD)
		-- Reflow summary first so previewCard's OnSizeChanged (fired
		-- synchronously from its SetWidth below) reads the fresh
		-- summary._naturalH, and re-anchor the scroll frame below the new
		-- pinned height so cards below don't overlap the grown summary.
		summaryCard:SetWidth(newSummaryW)
		reorderSummary()
		previewCard:SetWidth(newPreviewW)
		anchorScrollBelowPinned()
	end, 'FrameSettingsBuilder.resize.' .. unitType)

	F.EventBus:Register('SETTINGS_RESIZE_COMPLETE', function()
		grid:RebuildCards()
		onScroll()
	end, 'FrameSettingsBuilder.resizeComplete.' .. unitType)

	-- ── Invalidate on preset change ────────────────────────────
	-- When the editing preset changes, mark this scroll frame stale so
	-- the Settings framework knows to rebuild on next panel activation.
	F.EventBus:Register('EDITING_PRESET_CHANGED', function(newPreset)
		scroll._builtForPreset = nil
		if(F.Settings and F.Settings._panelFrames) then
			-- Invalidate cache so panel rebuilds with new preset data.
			-- TearDownPanel handles the full release (Hide + SetParent(nil)
			-- + tracking-table cleanup) so we don't leak the orphaned frame.
			for panelId, frame in next, F.Settings._panelFrames do
				if(frame == scroll) then
					if(F.Settings.TearDownPanel) then
						F.Settings.TearDownPanel(panelId)
					else
						F.Settings._panelFrames[panelId] = nil
					end
					break
				end
			end
		end
	end, 'FrameSettingsBuilder.' .. unitType)

	return scroll
end
