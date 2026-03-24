local addonName, Framed = ...
local F = Framed
local oUF = F.oUF
local C = F.Constants
local Widgets = F.Widgets

F.Elements = F.Elements or {}
F.Elements.Portrait = {}

-- ============================================================
-- Portrait Element Setup
-- ============================================================

--- Configure oUF's built-in Portrait element on a unit frame.
--- Supports '2D' (texture) and '3D' (PlayerModel) portrait types.
--- @param self Frame  The oUF unit frame
--- @param width number  Portrait width in UI units
--- @param height number  Portrait height in UI units
--- @param config? table  Optional config table; defaults applied if nil
function F.Elements.Portrait.Setup(self, width, height, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.type = config.type or '2D'   -- '2D' or '3D'

	-- --------------------------------------------------------
	-- 2D portrait: flat texture with inner crop
	-- --------------------------------------------------------

	if(config.type == '2D') then
		local portrait = self:CreateTexture(nil, 'ARTWORK')
		Widgets.SetSize(portrait, width, height)

		-- Crop 10% from each edge to remove the circular mask bleed
		-- and tighten framing on the face/torso region
		portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)

		self.Portrait = portrait

	-- --------------------------------------------------------
	-- 3D portrait: PlayerModel frame
	-- oUF calls :SetUnit() and :SetCamera() automatically
	-- --------------------------------------------------------

	elseif(config.type == '3D') then
		local portrait = CreateFrame('PlayerModel', nil, self)
		Widgets.SetSize(portrait, width, height)

		self.Portrait = portrait

	else
		-- Unsupported type: fall back to 2D silently
		local portrait = self:CreateTexture(nil, 'ARTWORK')
		Widgets.SetSize(portrait, width, height)
		portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)

		self.Portrait = portrait
	end
end
