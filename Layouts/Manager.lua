local addonName, Framed = ...
local F = Framed

F.LayoutManager = {}

-- ============================================================
-- DeepCopy — delegates to F.DeepCopy in Core/Utilities.lua
-- ============================================================

function F.LayoutManager.DeepCopy(src)
	return F.DeepCopy(src)
end

-- ============================================================
-- Create
-- Creates a new layout as a deep copy of 'Default Solo'.
-- ============================================================

function F.LayoutManager.Create(name)
	if(not name or name == '') then return false, 'Name is required' end
	if(not FramedDB or not FramedDB.layouts) then return false, 'SavedVariables not ready' end
	if(FramedDB.layouts[name]) then return false, 'Layout already exists: ' .. name end

	local source = FramedDB.layouts['Default Solo']
	if(not source) then return false, 'Default Solo layout not found' end

	local newLayout = F.LayoutManager.DeepCopy(source)
	newLayout.isDefault = false
	newLayout.positions = {}

	FramedDB.layouts[name] = newLayout
	F.EventBus:Fire('LAYOUT_CREATED', name)
	return true
end

-- ============================================================
-- Duplicate
-- Creates a new layout as a deep copy of the named source.
-- ============================================================

function F.LayoutManager.Duplicate(sourceName, newName)
	if(not sourceName or sourceName == '') then return false, 'Source name is required' end
	if(not newName or newName == '') then return false, 'New name is required' end
	if(not FramedDB or not FramedDB.layouts) then return false, 'SavedVariables not ready' end
	if(not FramedDB.layouts[sourceName]) then return false, 'Source layout not found: ' .. sourceName end
	if(FramedDB.layouts[newName]) then return false, 'Layout already exists: ' .. newName end

	local newLayout = F.LayoutManager.DeepCopy(FramedDB.layouts[sourceName])
	newLayout.isDefault = false
	newLayout.positions = {}

	FramedDB.layouts[newName] = newLayout
	F.EventBus:Fire('LAYOUT_CREATED', newName)
	return true
end

-- ============================================================
-- Rename
-- Moves a layout to a new key and updates all references.
-- ============================================================

function F.LayoutManager.Rename(oldName, newName)
	if(not oldName or oldName == '') then return false, 'Old name is required' end
	if(not newName or newName == '') then return false, 'New name is required' end
	if(not FramedDB or not FramedDB.layouts) then return false, 'SavedVariables not ready' end
	if(not FramedDB.layouts[oldName]) then return false, 'Layout not found: ' .. oldName end
	if(FramedDB.layouts[newName]) then return false, 'Layout already exists: ' .. newName end

	if(F.LayoutManager.IsDefault(oldName)) then
		return false, 'Cannot rename a default layout'
	end

	-- Move the layout entry
	FramedDB.layouts[newName] = FramedDB.layouts[oldName]
	FramedDB.layouts[oldName] = nil

	-- Update all references
	F.LayoutManager.UpdateReferences(oldName, newName)

	-- If the active layout was renamed, update AutoSwitch state
	if(F.AutoSwitch and F.AutoSwitch.GetCurrentLayout() == oldName) then
		F.EventBus:Fire('LAYOUT_CHANGED', newName)
	end

	F.EventBus:Fire('LAYOUT_RENAMED', oldName, newName)
	return true
end

-- ============================================================
-- Delete
-- Removes a non-default layout. If it was active, triggers
-- AutoSwitch to re-evaluate.
-- ============================================================

function F.LayoutManager.Delete(name)
	if(not name or name == '') then return false, 'Name is required' end
	if(not FramedDB or not FramedDB.layouts) then return false, 'SavedVariables not ready' end
	if(not FramedDB.layouts[name]) then return false, 'Layout not found: ' .. name end

	if(F.LayoutManager.IsDefault(name)) then
		return false, 'Cannot delete a default layout'
	end

	local wasActive = F.AutoSwitch and F.AutoSwitch.GetCurrentLayout() == name

	FramedDB.layouts[name] = nil

	-- Fix any autoSwitch or specOverride references that pointed to the deleted layout
	F.LayoutManager.UpdateReferences(name, 'Default Solo')

	F.EventBus:Fire('LAYOUT_DELETED', name)

	-- Re-check if the deleted layout was active
	if(wasActive and F.AutoSwitch) then
		F.AutoSwitch.Check()
	end

	return true
end

-- ============================================================
-- GetNames
-- Returns a sorted list of all layout names.
-- ============================================================

function F.LayoutManager.GetNames()
	if(not FramedDB or not FramedDB.layouts) then return {} end

	local names = {}
	for name in next, FramedDB.layouts do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

-- ============================================================
-- IsDefault
-- Returns true if the named layout has isDefault == true.
-- ============================================================

function F.LayoutManager.IsDefault(name)
	if(not FramedDB or not FramedDB.layouts) then return false end
	local layout = FramedDB.layouts[name]
	return layout and layout.isDefault == true
end

-- ============================================================
-- UpdateReferences
-- Replaces all occurrences of oldName with newName in:
--   FramedCharDB.autoSwitch  (account-wide per-content mapping)
--   FramedCharDB.specOverrides (per-spec overrides)
-- Called on Rename and Delete.
-- ============================================================

function F.LayoutManager.UpdateReferences(oldName, newName)
	if(not FramedCharDB) then return end

	-- autoSwitch content-type mappings
	if(FramedCharDB.autoSwitch) then
		for contentType, layoutName in next, FramedCharDB.autoSwitch do
			if(layoutName == oldName) then
				FramedCharDB.autoSwitch[contentType] = newName
			end
		end
	end

	-- spec overrides
	if(FramedCharDB.specOverrides) then
		for key, layoutName in next, FramedCharDB.specOverrides do
			if(layoutName == oldName) then
				FramedCharDB.specOverrides[key] = newName
			end
		end
	end
end
