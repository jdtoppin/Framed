local addonName, Framed = ...
local F = Framed

local Widgets = F.Widgets
local C = F.Constants

-- ============================================================
-- About panel
-- Version info, credits, and license notices.
-- ============================================================

-- Read version from TOC metadata if available
local function getVersion()
	local v = C_AddOns and C_AddOns.GetAddOnMetadata and
		C_AddOns.GetAddOnMetadata('Framed', 'Version')
	return v or (F.VERSION or '1.0.0')
end

local function getAuthor()
	local a = C_AddOns and C_AddOns.GetAddOnMetadata and
		C_AddOns.GetAddOnMetadata('Framed', 'Author')
	return a or 'jdtoppin'
end

-- ============================================================
-- Panel registration
-- ============================================================

F.Settings.RegisterPanel({
	id      = 'about',
	label   = 'About',
	section = 'BOTTOM',
	order   = 100,
	create  = function(parent)
		local parentW = parent._explicitWidth  or parent:GetWidth()  or 530
		local parentH = parent._explicitHeight or parent:GetHeight() or 400
		local scroll = Widgets.CreateScrollFrame(
			parent, nil,
			parentW,
			parentH)
		scroll:SetAllPoints(parent)

		local content = scroll:GetContentFrame()
		content:SetWidth(parentW)
		local width   = parentW - C.Spacing.normal * 2
		local yOffset = -C.Spacing.normal

		-- ── Version info ───────────────────────────────────────
		local versionHeading, versionHeadingH = Widgets.CreateHeading(content, 'Version', 2)
		versionHeading:ClearAllPoints()
		Widgets.SetPoint(versionHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - versionHeadingH

		local versionFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textNormal)
		versionFS:ClearAllPoints()
		Widgets.SetPoint(versionFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		versionFS:SetText('Framed  v' .. getVersion() .. '  by ' .. getAuthor())
		yOffset = yOffset - C.Font.sizeNormal - C.Spacing.loose

		-- ── Credits ────────────────────────────────────────────
		local creditsHeading, creditsHeadingH = Widgets.CreateHeading(content, 'Credits', 2)
		creditsHeading:ClearAllPoints()
		Widgets.SetPoint(creditsHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - creditsHeadingH

		local creditLines = {
			{ label = 'oUF',                 detail = 'Embedded unit frame framework (MIT). Authored by Haste & contributors.' },
			{ label = 'AbstractFramework',   detail = 'UI library design inspiration (GPL v3). Pixel-perfect sizing approach.' },
			{ label = 'LibSharedMedia-3.0',  detail = 'Font and statusbar texture registry.' },
		}

		for _, entry in next, creditLines do
			local nameFS = Widgets.CreateFontString(content, C.Font.sizeNormal, C.Colors.textActive)
			nameFS:ClearAllPoints()
			Widgets.SetPoint(nameFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
			nameFS:SetText(entry.label)
			yOffset = yOffset - C.Font.sizeNormal - C.Spacing.base

			local detailFS = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.textSecondary)
			detailFS:ClearAllPoints()
			Widgets.SetPoint(detailFS, 'TOPLEFT', content, 'TOPLEFT', C.Spacing.tight, yOffset)
			detailFS:SetWidth(width - C.Spacing.tight)
			detailFS:SetWordWrap(true)
			detailFS:SetText(entry.detail)
			yOffset = yOffset - detailFS:GetStringHeight() - C.Spacing.normal
		end

		-- ── License ────────────────────────────────────────────
		local licenseHeading, licenseHeadingH = Widgets.CreateHeading(content, 'License', 2)
		licenseHeading:ClearAllPoints()
		Widgets.SetPoint(licenseHeading, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		yOffset = yOffset - licenseHeadingH

		local licenseFS = Widgets.CreateFontString(content, C.Font.sizeSmall, C.Colors.textSecondary)
		licenseFS:ClearAllPoints()
		Widgets.SetPoint(licenseFS, 'TOPLEFT', content, 'TOPLEFT', 0, yOffset)
		licenseFS:SetWidth(width)
		licenseFS:SetWordWrap(true)
		licenseFS:SetText(
			'Framed is released under the GNU General Public License v3 (GPL v3). ' ..
			'The embedded oUF library is released under the MIT License. ' ..
			'See each respective LICENSE file for full terms.')
		yOffset = yOffset - licenseFS:GetStringHeight() - C.Spacing.normal

		-- ── Final content height ───────────────────────────────
		content:SetHeight(math.abs(yOffset) + C.Spacing.normal)
		scroll:UpdateScrollRange()

		return scroll
	end,
})
