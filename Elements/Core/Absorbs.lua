local addonName, Framed = ...
local F = Framed

F.Elements = F.Elements or {}
F.Elements.Absorbs = {}

-- ============================================================
-- Absorbs Element Setup
-- ============================================================
-- Configures the absorb bar portion of oUF's HealthPrediction element.
-- Health.lua is authoritative for HealthPrediction initialization.
-- If HealthPrediction already exists (heal prediction enabled by Health.lua),
-- only the absorb bar color is updated here.
-- If HealthPrediction does not exist (heal prediction disabled), a minimal
-- structure is created so absorb display still works.

--- Configure the absorb overlay bar on a unit frame.
--- @param self Frame  The oUF unit frame
--- @param healthBar StatusBar  The health bar created by Health.lua
--- @param config? table  Optional config; defaults applied if nil
function F.Elements.Absorbs.Setup(self, healthBar, config)

	-- --------------------------------------------------------
	-- Config defaults
	-- --------------------------------------------------------

	config = config or {}
	config.color = config.color or { 1, 0.8, 0, 0.4 }  -- gold, semi-transparent

	-- --------------------------------------------------------
	-- HealthPrediction: update or create minimal structure
	-- Health.lua owns full initialization when healPrediction is enabled.
	-- Absorbs.lua only creates the minimal absorb-only structure when needed.
	-- --------------------------------------------------------

	if(not self.HealthPrediction) then
		local absorbBar = self:CreateTexture(nil, 'OVERLAY')
		absorbBar:SetTexture([[Interface\BUTTONS\WHITE8x8]])
		self.HealthPrediction = {
			absorbBar   = absorbBar,
			maxOverflow = 1.05,
		}
	end

	local absorbBar = self.HealthPrediction.absorbBar
	absorbBar:SetVertexColor(unpack(config.color))
end
