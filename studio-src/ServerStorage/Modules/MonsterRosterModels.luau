-- Модели монстров ростера вне спавна Акта 1 (шаги 4.6–4.7 ДД, веха 5): 4 обычных, 2 элитных и гнездо Матери Роя.
-- Подключается из CombatModels, который передаёт свои помощники. Пивот на земле Y = 0, лицо смотрит в −Z.
return function(H)
	local part, ball, cylinder, newModel, makeRoot, addEyes, rgb = H.part, H.ball, H.cylinder, H.newModel, H.makeRoot, H.addEyes, H.rgb
	local Mat = Enum.Material
	local M = {}

	local function finish(m, root)
		m.PrimaryPart = root
		m.WorldPivot = CFrame.new()
		return m
	end

	-- Туманный Двойник: силуэт из тумана. Когда он копирует игрока, тело MistBody прячется, клубы Wisp остаются
	M.Monster_MistDouble = function()
		local m = newModel("Monster_MistDouble")
		local root = makeRoot(m, 5.2, 2.4)
		local body = Instance.new("Model")
		body.Name = "MistBody"
		body.Parent = m
		local fog = rgb(196, 208, 222)
		ball(body, "Torso", Vector3.new(1.9, 2.3, 1.2), CFrame.new(0, 3.0, 0), fog, Mat.SmoothPlastic, {Transparency = 0.35})
		ball(body, "Head", Vector3.new(1.25, 1.25, 1.25), CFrame.new(0, 4.6, 0), fog, Mat.SmoothPlastic, {Transparency = 0.3})
		for _, sx in ipairs({-1, 1}) do
			ball(body, "Arm", Vector3.new(0.6, 2.0, 0.6), CFrame.new(sx * 1.25, 3.05, 0), fog, Mat.SmoothPlastic, {Transparency = 0.45})
			ball(body, "Leg", Vector3.new(0.7, 2.1, 0.7), CFrame.new(sx * 0.5, 1.05, 0), fog, Mat.SmoothPlastic, {Transparency = 0.5})
		end
		addEyes(body, 4.68, -0.55, 0.25, rgb(170, 235, 255), 0.22)
		for i = 1, 5 do
			local a = math.rad(i * 72)
			ball(m, "Wisp", Vector3.new(1.5, 0.7, 1.5), CFrame.new(math.cos(a) * 1.3, 0.35 + (i % 2) * 0.3, math.sin(a) * 1.3),
				rgb(214, 224, 236), Mat.SmoothPlastic, {Transparency = 0.6})
		end
		return finish(m, root)
	end

	-- Кристальный Клещ: маленький, с кристаллами на спине и цепкими лапами
	M.Monster_CrystalTick = function()
		local m = newModel("Monster_CrystalTick")
		local root = makeRoot(m, 1.6, 1.8)
		ball(m, "Body", Vector3.new(1.3, 0.8, 1.6), CFrame.new(0, 0.6, 0), rgb(70, 86, 110), Mat.SmoothPlastic)
		for i = 1, 3 do
			part(m, "Crystal", Vector3.new(0.3, 0.9 - i * 0.12, 0.3),
				CFrame.new((i - 2) * 0.32, 1.15, 0.1 + (i % 2) * 0.25) * CFrame.Angles(math.rad(12 * (i - 2)), 0, math.rad(18 * (i - 2))),
				rgb(140, 225, 255), Mat.Glass, {Transparency = 0.15})
		end
		for _, sx in ipairs({-1, 1}) do
			for j = 1, 3 do
				part(m, "Leg", Vector3.new(0.75, 0.12, 0.12), CFrame.new(sx * 0.85, 0.35, (j - 2) * 0.45) * CFrame.Angles(0, 0, sx * math.rad(-28)),
					rgb(48, 58, 76), Mat.Metal)
			end
		end
		part(m, "Jaw", Vector3.new(0.5, 0.14, 0.4), CFrame.new(0, 0.45, -0.9), rgb(48, 58, 76), Mat.Metal)
		addEyes(m, 0.78, -0.72, 0.2, rgb(120, 240, 255), 0.16)
		return finish(m, root)
	end

	-- Пепельный Пёс: поджарый, с тлеющей гривой
	M.Monster_AshHound = function()
		local m = newModel("Monster_AshHound")
		local root = makeRoot(m, 3.0, 2.2)
		local ash, soot = rgb(72, 66, 64), rgb(52, 48, 46)
		part(m, "Body", Vector3.new(1.3, 1.25, 3.0), CFrame.new(0, 1.9, 0.2), ash, Mat.Slate)
		part(m, "Head", Vector3.new(1.0, 0.95, 1.3), CFrame.new(0, 2.45, -1.75), ash, Mat.Slate)
		part(m, "Snout", Vector3.new(0.6, 0.5, 0.8), CFrame.new(0, 2.25, -2.6), soot, Mat.Slate)
		for _, sx in ipairs({-1, 1}) do
			part(m, "Ear", Vector3.new(0.22, 0.6, 0.3), CFrame.new(sx * 0.36, 3.1, -1.5) * CFrame.Angles(0, 0, sx * math.rad(-12)), soot, Mat.Slate)
			for _, sz in ipairs({-0.85, 1.25}) do
				part(m, "Leg", Vector3.new(0.38, 1.35, 0.38), CFrame.new(sx * 0.48, 0.68, sz), soot, Mat.Slate)
			end
		end
		for i = 1, 4 do
			part(m, "Ember", Vector3.new(0.3, 0.55 - i * 0.06, 0.4), CFrame.new(0, 2.75 - i * 0.03, -1.0 + i * 0.6), rgb(255, 140, 50), Mat.Neon)
		end
		part(m, "Tail", Vector3.new(0.22, 0.22, 1.2), CFrame.new(0, 2.2, 2.2) * CFrame.Angles(math.rad(25), 0, 0), rgb(255, 120, 40), Mat.Neon)
		addEyes(m, 2.6, -2.42, 0.28, rgb(255, 170, 60), 0.2)
		return finish(m, root)
	end

	-- Пустотный Плащ: парящий плащ с пустым капюшоном (полупрозрачность задаёт сервер)
	M.Monster_VoidCloak = function()
		local m = newModel("Monster_VoidCloak")
		local root = makeRoot(m, 5.4, 2.4)
		local void = rgb(52, 36, 86)
		part(m, "Cloak", Vector3.new(2.3, 3.2, 1.2), CFrame.new(0, 2.7, 0.1) * CFrame.Angles(math.rad(4), 0, 0), void, Mat.Fabric)
		part(m, "CloakHem", Vector3.new(2.7, 0.9, 1.5), CFrame.new(0, 1.0, 0.2), rgb(38, 26, 64), Mat.Fabric)
		ball(m, "Hood", Vector3.new(1.6, 1.6, 1.7), CFrame.new(0, 4.6, 0), void, Mat.Fabric)
		ball(m, "HoodVoid", Vector3.new(1.05, 1.1, 0.5), CFrame.new(0, 4.55, -0.66), rgb(10, 6, 18), Mat.SmoothPlastic)
		for _, sx in ipairs({-1, 1}) do
			part(m, "Sleeve", Vector3.new(0.6, 2.0, 0.7), CFrame.new(sx * 1.4, 3.0, -0.2) * CFrame.Angles(math.rad(-22), 0, sx * math.rad(14)), void, Mat.Fabric)
			part(m, "Claw", Vector3.new(0.14, 0.14, 0.9), CFrame.new(sx * 1.55, 2.15, -0.95), rgb(190, 130, 255), Mat.Neon)
		end
		addEyes(m, 4.62, -0.86, 0.26, rgb(200, 140, 255), 0.2)
		return finish(m, root)
	end

	-- Мать Роя: раздутое брюхо-улей, крылья и корона жал
	M.Monster_SwarmMother = function()
		local m = newModel("Monster_SwarmMother")
		local root = makeRoot(m, 7.0, 4.0)
		ball(m, "Abdomen", Vector3.new(4.2, 3.8, 5.2), CFrame.new(0, 3.0, 1.4), rgb(150, 190, 84), Mat.Slate)
		ball(m, "Thorax", Vector3.new(2.6, 2.4, 2.8), CFrame.new(0, 3.9, -1.5), rgb(84, 76, 92), Mat.SmoothPlastic)
		ball(m, "Head", Vector3.new(1.7, 1.6, 1.7), CFrame.new(0, 4.5, -3.1), rgb(68, 60, 76), Mat.SmoothPlastic)
		for i = 1, 6 do
			local a = math.rad(i * 60)
			ball(m, "HiveCell", Vector3.new(0.9, 0.9, 0.9), CFrame.new(math.cos(a) * 1.5, 3.0 + math.sin(a) * 1.2, 3.7), rgb(196, 236, 110), Mat.Neon)
		end
		for _, sx in ipairs({-1, 1}) do
			part(m, "Wing", Vector3.new(4.2, 0.1, 1.7), CFrame.new(sx * 2.6, 5.4, -0.6) * CFrame.Angles(0, sx * 0.3, sx * 0.35),
				rgb(214, 236, 245), Mat.Glass, {Transparency = 0.45})
			for j = 1, 3 do
				part(m, "Leg", Vector3.new(0.3, 2.9, 0.3), CFrame.new(sx * 1.5, 1.45, -2.2 + j * 0.9) * CFrame.Angles(0, 0, sx * math.rad(-16)),
					rgb(54, 48, 60), Mat.Metal)
			end
		end
		for i = 1, 5 do
			part(m, "CrownSting", Vector3.new(0.16, 0.8, 0.16), CFrame.new((i - 3) * 0.3, 5.55, -3.1) * CFrame.Angles(0, 0, math.rad((3 - i) * 12)),
				rgb(236, 206, 96), Mat.Metal)
		end
		addEyes(m, 4.65, -3.85, 0.42, rgb(255, 92, 92), 0.34)
		return finish(m, root)
	end

	-- Садовник Плесени: сгорбленная фигура во мху с лейкой заразы
	M.Monster_MoldGardener = function()
		local m = newModel("Monster_MoldGardener")
		local root = makeRoot(m, 7.2, 3.4)
		local moss, tin = rgb(88, 110, 78), rgb(96, 104, 100)
		part(m, "Robe", Vector3.new(3.0, 4.2, 2.3), CFrame.new(0, 2.5, 0.2) * CFrame.Angles(math.rad(8), 0, 0), moss, Mat.Grass)
		ball(m, "Hump", Vector3.new(3.2, 2.2, 2.6), CFrame.new(0, 5.0, 0.6), rgb(70, 92, 64), Mat.Grass)
		ball(m, "Head", Vector3.new(1.6, 1.5, 1.6), CFrame.new(0, 5.6, -1.0), rgb(120, 126, 108), Mat.Slate)
		cylinder(m, "Hat", 0.3, 3.4, CFrame.new(0, 6.45, -0.9), rgb(96, 78, 56), Mat.Wood)
		for i = 1, 5 do
			local a = math.rad(i * 72)
			ball(m, "MoldCap", Vector3.new(0.8, 0.5, 0.8), CFrame.new(math.cos(a) * 1.1, 6.0 + (i % 2) * 0.3, 0.6 + math.sin(a) * 0.9),
				rgb(170, 200, 150), Mat.Slate)
		end
		for _, sx in ipairs({-1, 1}) do
			part(m, "Arm", Vector3.new(0.6, 2.6, 0.6), CFrame.new(sx * 1.75, 3.6, -0.5) * CFrame.Angles(math.rad(-35), 0, sx * math.rad(10)), moss, Mat.Grass)
		end
		part(m, "WateringCan", Vector3.new(1.0, 1.0, 1.4), CFrame.new(1.75, 2.6, -1.9), tin, Mat.Metal)
		part(m, "Spout", Vector3.new(0.2, 0.2, 1.1), CFrame.new(1.75, 2.9, -3.0) * CFrame.Angles(math.rad(20), 0, 0), tin, Mat.Metal)
		ball(m, "BlightDrip", Vector3.new(0.4, 0.5, 0.4), CFrame.new(1.75, 2.75, -3.65), rgb(150, 215, 120), Mat.Neon)
		addEyes(m, 5.68, -1.76, 0.34, rgb(190, 255, 120), 0.28)
		return finish(m, root)
	end

	-- Гнездо Матери Роя: неподвижный кокон, из которого вылетают комары
	M.Monster_SwarmNest = function()
		local m = newModel("Monster_SwarmNest")
		local root = makeRoot(m, 3.0, 3.0)
		ball(m, "Cocoon", Vector3.new(2.8, 2.6, 2.8), CFrame.new(0, 1.3, 0), rgb(128, 150, 84), Mat.Slate)
		ball(m, "Opening", Vector3.new(1.2, 1.2, 0.5), CFrame.new(0, 1.7, -1.25), rgb(24, 30, 16), Mat.SmoothPlastic)
		for i = 1, 5 do
			local a = math.rad(i * 72)
			ball(m, "Egg", Vector3.new(0.6, 0.6, 0.6), CFrame.new(math.cos(a) * 1.25, 0.35, math.sin(a) * 1.25), rgb(196, 236, 110), Mat.Neon)
		end
		return finish(m, root)
	end

	return M
end
