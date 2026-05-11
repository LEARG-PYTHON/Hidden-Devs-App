local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local PetData = require(ReplicatedStorage:WaitForChild("PetData"))
local EquipEvent = ReplicatedStorage:WaitForChild("EquipPetEvent")
local NotifyEvent = ReplicatedStorage:WaitForChild("AbilityNotifyEvent")

local activePetsFolder = workspace:FindFirstChild("ActivePets") or Instance.new("Folder", workspace)
activePetsFolder.Name = "ActivePets"

pcall(function()
	PhysicsService:RegisterCollisionGroup("GhostPlayers")
	PhysicsService:RegisterCollisionGroup("PassableWalls")
	PhysicsService:CollisionGroupSetCollidable("GhostPlayers", "PassableWalls", false)
end)

local function applyWallCollision(part)
	if part:IsA("BasePart") and part.Name == "Wall" then
		part.CollisionGroup = "PassableWalls"
	end
end

for _, obj in ipairs(workspace:GetDescendants()) do
	applyWallCollision(obj)
end

workspace.DescendantAdded:Connect(applyWallCollision)

local function getPetRarityColor(petName)
	local petInfo = PetData.Pets[petName]
	if petInfo and PetData.Rarities[petInfo.Rarity] then
		return PetData.Rarities[petInfo.Rarity].Color
	end
	return Color3.new(1, 1, 1)
end

local function setGhostCollision(character, isGhost)
	local group = isGhost and "GhostPlayers" or "Default"
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function clearCurrentVisuals(player)
	for _, model in ipairs(activePetsFolder:GetChildren()) do
		if model:GetAttribute("Owner") == player.UserId then
			model:Destroy()
		end
	end

	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local hrp = char.HumanoidRootPart
		for _, child in ipairs(hrp:GetChildren()) do
			if child.Name:find("Pet") or child:IsA("Trail") or child:IsA("Attachment") then
				child:Destroy()
			end
		end
		setGhostCollision(char, false)
	end
end

local function createPetTrail(player, petName)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local stats = PetData.Pets[petName]
	if stats and stats.TrailColor then
		local hrp = char.HumanoidRootPart
		
		local att0 = Instance.new("Attachment", hrp)
		att0.Name = "PetTrailAtt0"
		att0.Position = Vector3.new(0, 1.2, 0)

		local att1 = Instance.new("Attachment", hrp)
		att1.Name = "PetTrailAtt1"
		att1.Position = Vector3.new(0, -1.2, 0)

		local trail = Instance.new("Trail", hrp)
		trail.Name = "PetTrail"
		trail.Attachment0 = att0
		trail.Attachment1 = att1
		trail.Color = ColorSequence.new(stats.TrailColor)
		trail.Lifetime = 0.5
		trail.WidthScale = NumberSequence.new(1.5, 0.5)
		trail.LightEmission = 1
	end
end

local function refreshPlayerPet(player)
	clearCurrentVisuals(player)

	local equipped = player:FindFirstChild("EquippedPets")
	if not equipped or #equipped:GetChildren() == 0 then return end

	for _, val in ipairs(equipped:GetChildren()) do
		local petName = val.Name
		
		if petName == "Ghost" then
			setGhostCollision(player.Character, true)
		end

		local source = ReplicatedStorage.ChosenPets:FindFirstChild(petName)
		if source then
			local clone = source:Clone()
			clone:SetAttribute("Owner", player.UserId)
			
			local root = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			if root then
				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						if p ~= root then
							local weld = Instance.new("WeldConstraint", root)
							weld.Part0 = root
							weld.Part1 = p
						end
						p.Anchored = true
						p.CanCollide = false
					end
				end
				clone.Parent = activePetsFolder
			end
		end
		createPetTrail(player, petName)
	end
end

EquipEvent.OnServerEvent:Connect(function(player, petName)
	local equipped = player:FindFirstChild("EquippedPets")
	local owned = player:FindFirstChild("OwnedPets")

	if not equipped or not owned:FindFirstChild(petName) then return end

	local color = getPetRarityColor(petName)

	if equipped:FindFirstChild(petName) then
		equipped:ClearAllChildren()
		NotifyEvent:FireClient(player, "Pet Unequipped", petName .. " unsummoned", Color3.new(1, 0.2, 0.2))
	else
		equipped:ClearAllChildren()
		local val = Instance.new("StringValue")
		val.Name = petName
		val.Parent = equipped
		NotifyEvent:FireClient(player, "Pet Equipped", petName .. " is now active!", color)
	end
	
	refreshPlayerPet(player)
end)

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local equipped = player:FindFirstChild("EquippedPets")
			if not equipped then continue end

			for _, pet in ipairs(equipped:GetChildren()) do
				local pName = pet.Name
				local color = getPetRarityColor(pName)
				local timerAttr = pName:gsub(" ", "") .. "Timer"

				if pName == "Robot Bear" or pName == "Demon" then
					local t = player:GetAttribute(timerAttr) or 0
					t = t + 1
					if t >= 15 then
						local reward = (pName == "Robot Bear") and 1 or 2
						player.leaderstats.Coins.Value = player.leaderstats.Coins.Value + reward
						NotifyEvent:FireClient(player, "Passive", "Gained " .. reward .. " coins from " .. pName, color)
						t = 0
					end
					player:SetAttribute(timerAttr, t)

				elseif pName == "Butterfly" then
					local bt = player:GetAttribute("ButterflyTimer") or 0
					bt = bt + 1
					if bt >= 120 then
						player.leaderstats.Coins.Value = player.leaderstats.Coins.Value + 5
						NotifyEvent:FireClient(player, "Pollination", "Shared coins with the server!", color)
						for _, other in ipairs(Players:GetPlayers()) do
							if other ~= player and other.Character and player.Character then
								local dist = (other.Character.PrimaryPart.Position - player.Character.PrimaryPart.Position).Magnitude
								if dist < 25 then
									other.leaderstats.Coins.Value = other.leaderstats.Coins.Value + 5
									NotifyEvent:FireClient(other, "Pollination", player.Name .. " shared 5 coins with you!", color)
								end
							end
						end
						bt = 0
					end
					player:SetAttribute("ButterflyTimer", bt)

				elseif pName == "Ice Golem" then
					local it = player:GetAttribute("IceTimer") or 0
					it = it + 1
					if it >= 180 then
						local targets = {}
						for _, p in ipairs(Players:GetPlayers()) do
							if p ~= player and p.Character then table.insert(targets, p) end
						end

						if #targets > 0 then
							local target = targets[math.random(1, #targets)]
							NotifyEvent:FireClient(player, "Frostbite", "You froze " .. target.Name .. "!", color)
							task.spawn(function()
								local targetHrp = target.Character.HumanoidRootPart
								targetHrp.Anchored = true
								target.Character.Humanoid.WalkSpeed = 0
								
								local ice = Instance.new("Part")
								ice.Size = Vector3.new(6, 8, 6)
								ice.CFrame = targetHrp.CFrame * CFrame.new(0, 1.5, 0)
								ice.Anchored = true
								ice.Material = Enum.Material.Glass
								ice.Color = Color3.fromRGB(180, 240, 255)
								ice.Transparency = 0.4
								ice.Parent = workspace
								
								task.wait(10)
								ice:Destroy()
								if target.Parent then
									targetHrp.Anchored = false
									target.Character.Humanoid.WalkSpeed = 16
								end
							end)
							it = 0
						end
					end
					player:SetAttribute("IceTimer", it)
				end
			end
		end
	end
end)

NotifyEvent.OnServerEvent:Connect(function(player, title, msg, color)
	NotifyEvent:FireClient(player, title, msg, color)
end)

Players.PlayerAdded:Connect(function(player)
	local eq = Instance.new("Folder", player)
	eq.Name = "EquippedPets"
	
	player.CharacterAdded:Connect(function()
		task.wait(1)
		refreshPlayerPet(player)
	end)
end)
