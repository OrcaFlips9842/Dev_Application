local TweenService = game:GetService("TweenService")
local CameraController = require(game.ReplicatedStorage.Modules.FightingCameraModule)
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local RE = game.ReplicatedStorage.RE.FightingRE

local plr = game.Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local humanoid = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")

local blockVignette = plr.PlayerGui.FightingUI:WaitForChild("Vignette")

local tool = script.Parent
local cam = workspace.CurrentCamera

local stance, moveset, types

local equipped = false

local blocking = false
local activeBlockingTrigger = false

local dodging = false
local dodgeDB = false

local currentTrack
local currentDodgeTrack
local takeAnims = {}

local queuedPunch
local queuedDodge
local queuedBlock

local blockAnim

local currentTarget

local MIN_COMMIT = 0.95

local takeAnimsSpeed = {
	["Forward"] = 1.06,
	["Back"] = 1.787,
	["Right"] = 1.787,
	["Left"] =  1.787,
}

--ForwardFunctions
local playPunch

--Other Functions
local function findIns(types, name)
	if not name then return end
	local folder = game.ReplicatedStorage.FightingAssets.Moves
	for i,typeL in types do
		local f2 = folder:FindFirstChild(typeL)
		if f2 then 
			local move = f2:FindFirstChild(name)
			if move then return move end
		end
	end
end

local function getStyle()
	local attr = plr:FindFirstChild("Attributes")
	local style = attr:FindFirstChild("FightingStyle")
	if not style.Value then task.wait(1) end

	local raw = style.Value -- Example: "Boxing;Punch1;Punch2;nil;nil;nil;nil"
	local parts = string.split(raw, ";")

	local stance = parts[1]
	local moveset = {}

	-- Collect moves, ignoring "nil"
	for i = 2, #parts do
		table.insert(moveset, parts[i])
	end

	local types = {}

	local stanceIns = game.ReplicatedStorage.FightingAssets.Stances:FindFirstChild(stance)
	if stanceIns then
		local classes = stanceIns.AttackClasses:GetChildren()
		for i,class in classes do
			table.insert(types, class.Name)
		end
	else
		stance = nil
	end

	return stance, moveset, types
end
local function compressMoveset(moveset2)
	local newMoveset = {}
	for i, move in pairs(moveset2) do
		if move ~= "nil" then
			table.insert(newMoveset, move)
		end
	end
	return newMoveset
end

local loadedTracks = {}

local function loadAnim(animID, hum, priority, looped)
	if not animID  or animID == "" then return end
	if not priority then priority = Enum.AnimationPriority.Movement end
	if not looped then looped = false end
	
	if loadedTracks[animID] then
		local track = loadedTracks[animID]
		track.Priority = priority
		track.Looped = looped
	
		return track
	end
	
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animID

	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	
	loadedTracks[animID] = track
	
	return track
end

--EFFECTS
local originalUIPositions = {}
local targetCframeInputs = UDim2.fromScale(.843,.75)

local tConn
local function tweenUI(cond)
	local tweenInfo = TweenInfo.new(
		0.5,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	local UI = plr.PlayerGui.UI_2.HUD

	local function tweenTo(ui, goalPosition)
		-- Save original position once
		if not originalUIPositions[ui] then
			originalUIPositions[ui] = ui.Position
		end

		local tween = TweenService:Create(ui, tweenInfo, {
			Position = goalPosition
		})
		tween:Play()
		return tween
	end

	for _, ui in ipairs({ UI.Right, UI.Left }) do
		if cond == true then
			-- Push fully offscreen
			local goalX

			if ui.Name == "Left" then
				-- Off to the LEFT
				goalX = -ui.Size.X.Scale
			else
				-- Off to the RIGHT
				goalX = 1.001
			end

			local goalPosition = UDim2.fromScale(
				goalX,
				ui.Position.Y.Scale
			)

			tweenTo(ui, goalPosition)
		else
			-- Tween BACK to original
			local original = originalUIPositions[ui]
			if original then
				tweenTo(ui, original)
			end
		end
	end
	
	local inputFrame = plr.PlayerGui.FightingUI.Inputs
	local mobile = plr.PlayerGui.FightingUI.ContextButtonFrame
	
	if cond == true then
		if tConn then tConn:Disconnect(); tConn = nil end
		tweenTo(inputFrame, targetCframeInputs)
		mobile.Visible = true
		inputFrame.Visible = true
	else
		local tween = tweenTo(inputFrame, UDim2.fromScale(1.2,.75))
		mobile.Visible = false
		
		tConn = tween.Completed:connect(function()
			inputFrame.Visible = false
			tConn:Disconnect()
			tConn = nil
		end)
	end
end

local att_health = root:FindFirstChild("HealthUIPosition")
local startPos = att_health.Position
local attTweenInfo = TweenInfo.new(.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
local targetPos = Vector3.new(-4.5, 2.15, 1)
local function tweenHealthUI(cond)
	if cond	== true then
		if att_health.Position == targetPos then return end
		local tween = TweenService:Create(att_health, attTweenInfo, {Position = targetPos})
		tween:Play()	

		local sTween = TweenService:Create(att_health.BillboardGui.Frame.Scale, attTweenInfo, {Scale = 0.9})
		sTween:Play()
	else
		if att_health.Position == startPos then return end
		local tween = TweenService:Create(att_health, attTweenInfo, {Position = startPos})
		tween:Play()

		local sTween = TweenService:Create(att_health.BillboardGui.Frame.Scale, attTweenInfo, {Scale = 1})
		sTween:Play()
	end
end

local lockStamina = false
local function innitStaminaUI()
	local att = char:FindFirstChild("HumanoidRootPart"):FindFirstChild("BarUIPosition")
	if not att then return end
	local UI = att:FindFirstChild("BillboardGui"):FindFirstChild("Frame")
	if not UI then UI = att:WaitForChild("BillboardGui"):WaitForChild("Frame") end
	
	local fightingAttr = char:FindFirstChild("FightingAttributes")
	local val = fightingAttr:FindFirstChild("CurrentEndurance")
	
	local grad = UI.full.UIGradient
	local scaleV = UI.UIScale
	
	local highLighterGrade = UI.HighLighter

	local filledTween
	local tweenAlpha
	local alphaConn
	
	val.Changed:Connect(function()
		if val.Value == 0  then
			return
		end
		
		if filledTween then
			filledTween:Cancel()
			filledTween = nil
		end
		if tweenAlpha then
			tweenAlpha:Destroy()
		end
		if alphaConn then
			alphaConn:Disconnect()
		end
		
		local v = val.Value/100
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(v, 0),
			NumberSequenceKeypoint.new(math.min(v + 0.001, 1), 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		
		local SV = 1 + v/10
		scaleV.Scale = SV
		
		
		if v >= 0.99 then
			tweenAlpha = Instance.new("IntValue")
			filledTween = TweenService:Create(tweenAlpha, 
				TweenInfo.new(.3, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
				{Value = 100}
			)
			filledTween:Play()			
			alphaConn = tweenAlpha.Changed:Connect(function()
				highLighterGrade.UIGradient.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, math.clamp((tweenAlpha.Value/100)-0.1, 0, .9)),
					NumberSequenceKeypoint.new(1, math.clamp((tweenAlpha.Value/100)-0.65, 0, .35)),
				})
			end)
		elseif v > 0.05 then
			highLighterGrade.UIGradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(v-0.037, 1),
				NumberSequenceKeypoint.new(v-0.035, 0),
				NumberSequenceKeypoint.new(v, 0),
				NumberSequenceKeypoint.new(math.min(v + 0.001, 1), 1),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end)
end
innitStaminaUI()

local function toggleStaminaUI(cond)
	local att = char:FindFirstChild("HumanoidRootPart"):FindFirstChild("BarUIPosition")
	if not att then return end
	local UI = att:FindFirstChild("BillboardGui"):FindFirstChild("Frame")
	if UI then
		UI.Visible = cond or false
	end
end

--DODGING
local DODGE_FORWARD = 3.5
local DODGE_SIDE = 3.7
local DODGE_BACK = 3.5

local MIN_DODGE_STAMINA = 8

local speeds = {
	["Forward"] = 1,
	["Back"] = 1.25,
	["Left"] = 2,
	["Right"] = 1.775,
}

--Blocking
local blockActivatedAt = 0
local BLOCK_MIN_HOLD = 0.05

local essentialFolder = game.ReplicatedStorage:FindFirstChild("FightingAssets", 2):FindFirstChild("EssentialAnimations")
local dodgeAnims 
local function loadEssentialAnimations(hum)
	dodgeAnims= {
		["Forward"] = loadAnim(essentialFolder.ForwardDodge.AnimationId, hum, Enum.AnimationPriority.Action3, false),
		["Back"] = loadAnim(essentialFolder.BackDodge.AnimationId, hum, Enum.AnimationPriority.Action3, false),
		["Right"] = loadAnim(essentialFolder.RightDodge.AnimationId, hum, Enum.AnimationPriority.Action3, false),
		["Left"] = loadAnim(essentialFolder.LeftDodge.AnimationId, hum, Enum.AnimationPriority.Action3, false),
	}
	takeAnims= {
		["Forward"] = loadAnim(essentialFolder.Hit.Forward.AnimationId, hum, Enum.AnimationPriority.Action2, false),
		["Back"] = loadAnim(essentialFolder.Hit.Back.AnimationId, hum, Enum.AnimationPriority.Action2, false),
		["Right"] = loadAnim(essentialFolder.Hit.Right.AnimationId, hum, Enum.AnimationPriority.Action2, false),
		["Left"] = loadAnim(essentialFolder.Hit.Left.AnimationId, hum, Enum.AnimationPriority.Action2, false),
	}	
	blockAnim = loadAnim(essentialFolder.Block.AnimationId, hum, Enum.AnimationPriority.Action3, true)	
end
loadEssentialAnimations(humanoid)

local function getValidDodgePosition(dodgeVector, distance)
	local rayOrigin = root.Position
	local rayDirection = dodgeVector * distance

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {char}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if result then
		local safePos = result.Position + result.Normal * 1
		return Vector3.new(safePos.X, root.Position.Y, safePos.Z)
	end

	return root.Position + dodgeVector * distance
end

local function adjustDodgeForEnemy(targetPos, direction)
	if not currentTarget then
		return targetPos
	end
	
	local enemyRoot = currentTarget:FindFirstChild("HumanoidRootPart") 
	if not enemyRoot then
		return targetPos
	end
	
	local dist = (targetPos - enemyRoot.Position).Magnitude 
	if dist < 4 then
		local pushDir = (targetPos - enemyRoot.Position).Unit
		targetPos = targetPos + pushDir * 3
	end
	return targetPos
end

local function getDodgeVector(direction)
	local camForward = cam.CFrame.LookVector
	local camRight = cam.CFrame.RightVector

	camForward = Vector3.new(camForward.X,0,camForward.Z).Unit
	camRight = Vector3.new(camRight.X,0,camRight.Z).Unit

	if direction == "Forward" then
		return camForward, DODGE_FORWARD

	elseif direction == "Back" then
		return -camForward, DODGE_BACK

	elseif direction == "Left" then
		return -camRight, DODGE_SIDE

	elseif direction == "Right" then
		return camRight, DODGE_SIDE
	end
end

local function getMoveDodgeDirection()
	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude < 0.1 then
		return "Back"
	end

	local camForward = cam.CFrame.LookVector
	local camRight = cam.CFrame.RightVector

	camForward = Vector3.new(camForward.X, 0, camForward.Z).Unit
	camRight = Vector3.new(camRight.X, 0, camRight.Z).Unit

	local forwardDot = moveDir:Dot(camForward)
	local rightDot = moveDir:Dot(camRight)

	if math.abs(forwardDot) >= math.abs(rightDot) then
		if forwardDot >= 0 then
			return "Forward"
		else
			return "Back"
		end
	else
		if rightDot >= 0 then
			return "Right"
		else
			return "Left"
		end
	end
end

local function performDodge(direction)
	dodging = true
	dodgeDB = true
	
	root.Anchored = true
	
	if blocking then
		blocking = false
		if blockAnim.IsPlaying then
			blockAnim:Stop(0.05)
		end
		
		blockVignette.Visible = false
		RE.BlockRE:FireServer(false) 
	end
	
	local dodgeVector, distance = getDodgeVector(direction)

	local targetPos = getValidDodgePosition(dodgeVector, distance)
	targetPos = adjustDodgeForEnemy(targetPos, direction)

	local tween = TweenService:Create(
		root,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			CFrame = CFrame.new(targetPos, targetPos + root.CFrame.LookVector)
		}
	)

	--play the animation
	local anim = dodgeAnims[direction]
	local speed = speeds[direction] or 1.5
	if anim then
		anim:Play(0.15,1, speed)
		currentDodgeTrack = anim	
	end

	tween:Play()

	RE.DodgeRE:FireServer()

	--startCameraShake(.12)
	
	task.delay(0.4,function()
		root.Anchored = false
		dodging = false

		local trackDone = not currentTrack or not currentTrack.IsPlaying
		
		if activeBlockingTrigger  then
			blocking = true
			blockAnim:Play(0.025)
			RE.BlockRE:FireServer(true)
			
			blockVignette.Visible = true
			
			if queuedPunch and trackDone then
				currentTrack = nil
				RE.PunchEndedRE:FireServer()
			end
		
			queuedPunch = nil
			queuedBlock = false
			return
		end
		queuedBlock = false
		
		if queuedPunch and trackDone then
			local next = queuedPunch
			queuedPunch = nil
			
			if currentDodgeTrack and currentDodgeTrack.IsPlaying then
				currentDodgeTrack:Stop(0.05)
			end
			currentDodgeTrack = nil
			
			task.defer(function()
				local punchIns = findIns(types, moveset[next.index])
				if punchIns and punchIns:FindFirstChild("Animation") then
					playPunch(punchIns.Animation.AnimationId, next.speed, next.lastEndur, next.ins)
				else
					-- safety: if punch can't be found, clean up so server isn't stuck
					currentTrack = nil
					RE.PunchEndedRE:FireServer()
				end
			end)
		end
	end)	
	task.delay(0.43,function()
		dodgeDB = false
	end)	
end

local function hitStop(hum, duration, perfect, speedPercent)
	duration = duration or 0.06
	
	if not speedPercent then speedPercent = 0.4 end
	
	local ws = hum.WalkSpeed
	local jp = hum.JumpPower
	
	hum.WalkSpeed = 3
	hum.JumpPower = 0
	
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local frozenTracks = {}

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local originalSpeed = track.Speed
		table.insert(frozenTracks, { track = track, speed = originalSpeed })
		if perfect then
			track:AdjustSpeed(0.1)
		else
			track:AdjustSpeed(track.PlaybackSpeed*speedPercent)
		end
		
	end

	task.delay(duration, function()
		hum.WalkSpeed = ws
		hum.JumpPower = jp
		
		for _, data in ipairs(frozenTracks) do
			pcall(function()
				data.track:AdjustSpeed(data.speed)
			end)
		end
	end)
end
--MAIN
tool.Equipped:Connect(function()
	equipped = true
	RE.EquipRE:FireServer(true)
	
	stance, moveset, types = getStyle()
	moveset = compressMoveset(moveset)
		
	tweenUI(true)
	toggleStaminaUI(true)
end)
tool.Unequipped:Connect(function()
	equipped = false
	
	blocking = false
	activeBlockingTrigger = false
	
	queuedBlock = false
	queuedDodge = false
	
	
	if blockAnim and blockAnim.IsPlaying then
		blockAnim:Stop(0.05)
	end
	
	RE.EquipRE:FireServer(false)
	CameraController.deactivate()
	
	blockVignette.Visible = false
	
	tweenHealthUI(false)
	tweenUI(false)	
	toggleStaminaUI(false)
end)

RE.EquipRE.OnClientEvent:Connect(function(cond, target)
	if cond == false then
		tool.Parent = plr.Backpack
		CameraController.deactivate()
		return
	end
	
	--VISUAL Management (UI, camera, keybind menus)
	CameraController.activate(target)
	if target then
		currentTarget = target
		tweenHealthUI(true)
	else
		currentTarget = nil
		tweenHealthUI(false)	
	end
end)

tool.Activated:Connect(function()
	if blocking then return end
	local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled and not UIS.MouseEnabled
	if isMobile then return end
	RE.PunchRE:FireServer(char)
end)

local function chainNext(track, onNearEnd, alertServer)
	local connection
	local fired = false
	local nearEndFired = false  -- guard against double fire

	connection = RunService.RenderStepped:Connect(function()
		if not equipped then
			if currentTrack then
				currentTrack:Stop()
			end
			connection:Disconnect()
			return
		end

		if not track.IsPlaying then
			connection:Disconnect()
			if not nearEndFired then
				nearEndFired = true
				onNearEnd()
			end
			return
		end

		if track.TimePosition >= track.Length * 0.8 and not fired then
			fired = true
			if alertServer then
				alertServer()
			end
		end

		if track.TimePosition >= track.Length * MIN_COMMIT then
			connection:Disconnect()
			if not nearEndFired then
				nearEndFired = true
				onNearEnd()
			end
		end
	end)
end
playPunch = function(animationId, speed, lastEndur, ins)
	local track = loadAnim(animationId, humanoid, Enum.AnimationPriority.Action2)
	track:Play(0.05, 1, speed)
	track:AdjustSpeed(speed)
	track:AdjustWeight(1.5)
	
	CameraController.SetShake(.4, .1)
	
	local waited = 0
	while track.Length <= 0 and waited < 2 do
		RunService.Heartbeat:Wait()
		waited += 0.016
	end
	if track.Length <= 0 then
		warn("Animation failed to load:", animationId)
		currentTrack = nil
		RE.PunchEndedRE:FireServer()
		return
	end

	currentTrack = track

	local effectiveLength = track.Length / speed
	RE.HitboxRE:FireServer(ins, char, lastEndur, effectiveLength)  
	
	chainNext(track, 
		function()
			if queuedBlock and activeBlockingTrigger then
				blocking = true
				blockAnim:Play(0.1)	
				
				currentTrack = nil
				
				queuedBlock = false
				queuedPunch = nil
				queuedDodge = nil
				
				blockVignette.Visible = true
				RE.BlockRE:FireServer(true)
				return
			else
				queuedBlock = false
			end
			
			if queuedDodge then
				--local savedPunch = queuedPunch  -- save before clearing
				queuedPunch = nil
				local dir = queuedDodge
				queuedDodge = nil

				performDodge(dir)
				return
			end
			
			local nextPunch = queuedPunch
			queuedPunch = nil
			
			if nextPunch then
				local punchIns = findIns(types, moveset[nextPunch.index])
				if not punchIns then warn("no punch ins") return end
				playPunch(punchIns:FindFirstChild("Animation").AnimationId, nextPunch.speed, nextPunch.lastEndur, nextPunch.ins)
				if currentTrack and currentTrack.IsPlaying then
					currentTrack:Stop(0.05) -- short fade so it doesn't pop
				end	
			else				
				currentTrack = nil
				RE.PunchEndedRE:FireServer()
			end
		end,
		
		function()
			RE.BufferingPunchRE:FireServer()
		end)
end

RE.PunchRE.OnClientEvent:Connect(function(punchStr, mainIndex, speed, lastEndur)
	if not equipped then return end
	if not punchStr then return end
	speed = speed or 1
	local index =  mainIndex 
	
	local punchIns = findIns(types, moveset[index])
	if not punchIns then return end

	local animation = punchIns:FindFirstChild("Animation")
	if not animation then return end
	
	--RE.HitboxRE:FireServer(punch, char, lastEndur, effectiveLength)
	
	if dodging then
		if not queuedPunch then
			queuedPunch = {
				index = mainIndex,
				speed = speed,
				lastEndur = lastEndur,
				ins = punchIns
			}
		end
		return
	end

	if currentTrack and currentTrack.IsPlaying then
		if not queuedPunch then
			queuedPunch = {
				index = mainIndex,
				speed = speed,
				lastEndur = lastEndur,
				ins = punchIns
			}
		end
		return	
	else
		playPunch(animation.AnimationId, speed, lastEndur, punchIns)
	end
end)

RE.SetCameraRE.OnClientEvent:Connect(function(targetChar)
	if targetChar then
		CameraController.setTarget(targetChar)
		currentTarget = targetChar
		tweenHealthUI(true)
	else
		CameraController.setTarget(nil)
		currentTarget = targetChar
		tweenHealthUI(false)
	end
end)

--DODGE HANDLING
local function canDodge(dir)
	if not equipped then return false end
	if dodgeDB or dodging then return false end
		
	if currentTrack and currentTrack.IsPlaying then 
		queuedDodge = dir
		return false
	end
	
	local fightingAttr = char:FindFirstChild("FightingAttributes")
	local endurance = fightingAttr.CurrentStamina.Value
	if endurance < MIN_DODGE_STAMINA then return false end
	
	if queuedPunch then
		queuedPunch = nil
	end

	return true
end

local function attemptDodge(direciton)
	if not canDodge(direciton) then return end
	performDodge(direciton)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not equipped then return end

	if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.DPadUp then
		attemptDodge("Forward")

	elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.DPadDown then
		attemptDodge("Back")

	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft then
		attemptDodge("Left")

	elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.DPadRight then
		attemptDodge("Right")	
	end
end)

--Blocking
local function canBlock()
	if not equipped then return false end
	if dodging then 
		queuedBlock = true
		return false 
	end
	return true
end

local function attemptToBlock()
	if not canBlock() then return end
	if currentTrack and currentTrack.IsPlaying then
		queuedBlock = true
		blocking = false	
		if blockAnim.IsPlaying then
			blockAnim:Stop(0.05)
		end	
	else
		blocking = true
		blockAnim:Play(0.1)	
		RE.BlockRE:FireServer(true)
		
		blockVignette.Visible = true
	end	
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonL2 then
		activeBlockingTrigger = true
		blockActivatedAt = tick() 
		attemptToBlock()
	end
end)

UIS.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonL2 then
		activeBlockingTrigger = false
		queuedBlock = false
		
		--if tick() - blockActivatedAt < BLOCK_MIN_HOLD then return end

		if not blocking then return end
		blocking = false
		blockAnim:Stop(0.1)

		blockVignette.Visible = false
		RE.BlockRE:FireServer(false)
	end
end)

local UI = plr.PlayerGui.FightingUI:FindFirstChild("ContextButtonFrame").Main
UI.Punch.Activated:Connect(function()
	if blocking then warn("Blockling ") return end
	if equipped then
		RE.PunchRE:FireServer(char)
	end
end)
UI.Dodge.InputBegan:Connect(function()
	attemptDodge(getMoveDodgeDirection())
end)
UI.Block.InputBegan:Connect(function()
	activeBlockingTrigger = true
	blockActivatedAt = tick() 
	attemptToBlock()
end)
UI.Block.InputEnded:Connect(function()
	activeBlockingTrigger = false
	queuedBlock = false

	if tick() - blockActivatedAt < BLOCK_MIN_HOLD then return end

	if not blocking then return end
	blocking = false
	blockAnim:Stop(0.05)

	blockVignette.Visible = false
	RE.BlockRE:FireServer(false)
end)

--On hit return
local maxDamageSeq = 20
local minDamageSeq = 4
local fadeTime = .05
RE.HitRE.OnClientEvent:Connect(function(targetChar, damage, action, contactPos)
	if action == "dodged" then
		hitStop(humanoid, .2, .9)
		CameraController.SetShake(.3, .1)
		
		
	elseif action == "perfectDodge" then
		hitStop(humanoid, 1)
		CameraController.SetShake(.5, .6)
		--freeze anims for a second
	elseif action == "landedHit" then
		--CameraController.SetShake(1,.2)
		--Show some sort of visual stimulus
		
		CameraController.SetShake(2, .15)
		RE.PunchEndedRE:FireServer()
	elseif action == "takenHit" then
		CameraController.SetShake(3.5, .2)
		for _, anim in pairs(takeAnims) do
			anim:Stop(0.3)
		end
		
		if contactPos then
			local rootPart = char:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
				local estimatePos = (targetRoot.Position + contactPos)/2
				
				local localHitPos = rootPart.CFrame:PointToObjectSpace(estimatePos)
				local hitDir = Vector3.new(localHitPos.X, 0, localHitPos.Z)

				if hitDir.Magnitude > 0 then
					hitDir = hitDir.Unit
				end

				local forwardWeight = hitDir.Z  -- positive = behind, negative = in front
				local rightWeight = hitDir.X    -- positive = right, negative = left
				
				if forwardWeight > 0 then
					takeAnims["Forward"]:Play(fadeTime, forwardWeight/2, takeAnimsSpeed["Forward"])
				else
					takeAnims["Back"]:Play(fadeTime, math.abs(forwardWeight/2), takeAnimsSpeed["Back"])
				end

				if rightWeight > 0 then
					takeAnims["Right"]:Play(fadeTime, rightWeight/2, takeAnimsSpeed["Right"])
				else
					takeAnims["Left"]:Play(fadeTime, math.abs(rightWeight/2), takeAnimsSpeed["Left"])
				end
			end
		else
			takeAnims["Forward"]:Play()
		end
		
		local damageRatio = damage/maxDamageSeq	
		--CameraController.SetShake(2*damageRatio,.1)
	end
end)

plr.CharacterRemoving:Connect(function()
	CameraController.deactivate()
	
	--tool.Parent = plr.Backpack
	
	if currentTrack then
		RE.PunchEndedRE:FireServer()
		currentTrack = nil
	end

	if blocking then
		RE.BlockRE:FireServer(false)
		blocking = false
	end
	activeBlockingTrigger = false

	dodging = false
	dodgeDB = false
	currentDodgeTrack = nil

	queuedPunch = nil
	queuedDodge = nil
	queuedBlock = false

	blockVignette.Visible = false
	tweenHealthUI(false)

	if tConn then
		tConn:Disconnect()
		tConn = nil
	end
end)