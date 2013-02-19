local pac = pac

pac.drawn_entities = pac.drawn_entities or {}
local pairs = pairs

pac.LocalPlayer = NULL
pac.RealTime = 0
pac.FrameNumber = 0

local sort = function(a, b)
	if a and b and a.DrawOrder and b.DrawOrder then
		return a.DrawOrder < b.DrawOrder
	end
end
	
local function sortparts(parts)
	table.sort(parts, sort)
end

local function think(part)
	if part.ThinkTime == 0 then
		if part.last_think ~= pac.FrameNumber then 
			part:Think()
			part.last_think = pac.FrameNumber
		end
	elseif not part.last_think or part.last_think < pac.RealTime then
		part:Think()
		part.last_think = pac.RealTime + (part.ThinkTime or 0.1)
	end
	
	for _, part in pairs(part.Children) do
		think(part)
	end
end

local function buildbones(part)
	part:BuildBonePositions()
	
	for _, part in pairs(part.Children) do
		buildbones(part)
	end
end

local render_SetColorModulation = render.SetColorModulation
local render_SetBlend = render.SetBlend
local render_MaterialOverride = render.MaterialOverride or SetMaterialOverride

function pac.RenderOverride(ent, type, draw_only)
	if not ent.pac_parts then
		pac.UnhookEntityRender(ent)
	else
		if not draw_only then
		
			pac.ResetBones(ent)
			
			-- bones MUST be setup before drawing or else unexpected/random results might happen
			for key, part in pairs(ent.pac_parts) do
				if part:IsValid() then
					if not part:HasParent() then
						buildbones(part)
					end
				else
					ent.pac_parts[key] = nil
					sortparts(ent.pac_parts)
				end
			end
		end
		
		for key, part in pairs(ent.pac_parts) do
			if part:IsValid() then
				if not part:HasParent() then
					if not draw_only then think(part) end
					part:Draw("OnDraw", nil, nil, type)
				end
			else
				ent.pac_parts[key] = nil
				sortparts(ent.pac_parts)
			end
		end
	end
	
	render_SetColorModulation(1,1,1)
	render_SetBlend(1)
	
	render_MaterialOverride()
end

function pac.HookEntityRender(ent, part)
	if ent:IsValid() and part:IsValid() and not part:HasParent() then	
		pac.dprint("hooking render on %s to draw part %s", tostring(ent), tostring(part))
		
		if not ent.pac_parts then
			ent.pac_parts = {}
		end
		
		-- umm
		-- it sometimes say ent.pac_parts is nil
		-- why?
		if ent.pac_parts then
			table.insert(ent.pac_parts, part)
		
			pac.drawn_entities[ent:EntIndex()] = ent
			sortparts(ent.pac_parts)
		end
	end
end

function pac.UnhookEntityRender(ent)	
	pac.drawn_entities[ent:EntIndex()] = nil

	ent.pac_parts = nil
end


local util_PixelVisible = util.PixelVisible
local cvar_enable = CreateClientConVar("pac_enable", "1")
local cvar_distance = CreateClientConVar("pac_draw_distance", "500")

pac.EyePos = vector_origin
function pac.RenderScene(pos, ang)
	pac.EyePos = pos
	pac.EyeAng = ang
end
pac.AddHook("RenderScene")


-- don't allow drawing in the skybox
local SKIP_DRAW

function pac.PreDrawSkyBox()
	SKIP_DRAW = true
end
pac.AddHook("PreDrawSkyBox")

function pac.PostDrawSkyBox()
	SKIP_DRAW = false
end
pac.AddHook("PostDrawSkyBox")

local draw_dist
local radius

local dst

function pac.PostDrawOpaqueRenderables(bool1, bool2)
	if bool2 then return end
	if SKIP_DRAW then return end
	
	if not cvar_enable:GetBool() then
		for key, ent in pairs(pac.drawn_entities) do
			if ent:IsValid() then
				if ent.pac_parts and ent.pac_drawing == true then
					for key, part in pairs(ent.pac_parts) do
						part:CallRecursive("OnHide")
					end
					pac.ResetBones(ent)
				end
				ent.pac_drawing = false
			else
				pac.drawn_entities[key] = nil
			end
		end
	return end
		
	-- commonly used variables		
	pac.RealTime = RealTime()
	pac.FrameNumber = FrameNumber()
	pac.LocalPlayer = LocalPlayer() 

	draw_dist = cvar_distance:GetInt()
	radius = 0
	
	for key, ent in pairs(pac.drawn_entities) do
		if ent:IsValid() then
			ent.pac_pixvis = ent.pac_pixvis or util.GetPixelVisibleHandle()
			dst = ent:EyePos():Distance(pac.EyePos)
			radius = ent:BoundingRadius() * 3 * (ent:GetModelScale() or 1)
			
			if ent:IsPlayer() and radius < 32 then
				radius = 128
			end
			
			if not ent:IsPlayer() and not ent:IsNPC() then
				radius = radius * 4
			end
			
			if 				
				(ent == pac.LocalPlayer and ent:ShouldDrawLocalPlayer()) or
				
				ent ~= pac.LocalPlayer and 
				(					
					util_PixelVisible(ent:EyePos(), radius, ent.pac_pixvis) ~= 0 and 
					(draw_dist <= 0 or dst < draw_dist) or
					(dst < radius or dst < 200)
				)
			then
				if ent.pac_parts and ent.pac_drawing == false then
					for key, part in pairs(ent.pac_parts) do
						part:CallRecursive("OnShow")
					end
				end
			
				pac.RenderOverride(ent, "opaque")
				ent.pac_drawing = true
			else
				if ent.pac_parts and ent.pac_drawing == true then
					for key, part in pairs(ent.pac_parts) do
						part:CallRecursive("OnHide")
					end
					pac.ResetBones(ent)
				end
			
				ent.pac_drawing = false
			end
		else	
			pac.drawn_entities[key] = nil
		end
	end
	
	pac.CheckParts()
end
pac.AddHook("PostDrawOpaqueRenderables")

function pac.PostDrawTranslucentRenderables(bool1, bool2)
	if bool2 then return end
	if SKIP_DRAW then return end

	for key, ent in pairs(pac.drawn_entities) do
		if ent:IsValid() then
			if ent.pac_drawing and ent.pac_parts then
				pac.RenderOverride(ent, "translucent", true)
			end
		else
			pac.drawn_entities[key] = nil
		end
	end
end
pac.AddHook("PostDrawTranslucentRenderables")

function pac.RenderScreenspaceEffects()
	for key, ent in pairs(pac.drawn_entities) do
		if ent:IsValid() then
			if ent.pac_drawing and ent.pac_parts then
				for key, part in pairs(ent.pac_parts) do
					part:Draw("OnRenderScreenspaceEffects")
				end
			end
		else
			pac.drawn_entities[key] = nil
		end
	end
end
pac.AddHook("RenderScreenspaceEffects")

function pac.Think()
	for key, ent in pairs(pac.drawn_entities) do
		if ent:IsValid() then
			if ent.pac_drawing and ent:IsPlayer() then
			
				ent.pac_traceres = ent:GetEyeTraceNoCursor()
				ent.pac_hitpos = ent.pac_traceres.HitPos
				
			end
		else
			pac.drawn_entities[key] = nil
		end
	end
end
pac.AddHook("Think")