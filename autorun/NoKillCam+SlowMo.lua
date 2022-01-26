



---------------------------Settings----------------------

local disableKillCam = true; --Disables the hover view of the monster from different angles after killing them
local disableOtherCams = false; --Disables fast travel cutscene cam and end of quest cam (like petting your buddies etc.) slightly glitchy with fast travel camera transitions

local disableUiOnKill = true; --Disables the UI for the slow mo duration on monster kill

local useSlowMo = true; --Enable slow mo for a certain duration of time after the last blow on the monster
local useSlowMoInMP = true; --Whether or not to use slow mo in online quests
local slowMoSpeed = 0.2; --Slow mo amount in percentage of realtime. 0.2 = 20% speed
local slowMoDuration = 5; --Slow mo duration in seconds
local slowMoRamp = 1.5; --Speed at which it transitions back to normal time after the slow mo duration has elapsed

local activateForAllMonsters = true; --will trigger slowmo/hide ui when killing any large monster, not just the final one on quest clear
local activateByAnyPlayer = true; --will trigger slowmo/hide ui when any player kills a monster, otherwise only when you do it 
local activateByEnemies = true; --will trigger slowmo/hide ui when a small monster or your pets kill a large monster, otherwise only when players do it
local activateOnCapture = false; --will trigger slowmo/hide ui when capturing the monster

--skip slow mo keys
local padAnimSkipBtn = 32768 -- persistent start button on controller
local kbAnimSkipKey = 27 -- persistent escape key. 32 = spacebar
----------------------------------------------------------



local hooked = false;
local isSlowMo = false;
local useSlowMoThisTime = false;
local slowMoStartTime = 0;
local curTimeScale = 1.0;
local lastHitPlayerIdx = 0;
local lastHitEnemy = nil;

local app_type = sdk.find_type_definition("via.Application");
local get_UpTimeSecond = app_type:get_method("get_UpTimeSecond");
local get_ElapsedSecond = app_type:get_method("get_ElapsedSecond");

local guiManager = nil;
local lobbyManager = nil;

function GetLobbyManager()
	if not lobbyManager then
		lobbyManager = sdk.get_managed_singleton("snow.LobbyManager");
	end
	
	return lobbyManager;
end

function GetQuestIsOnline()
	return GetLobbyManager():call("IsQuestOnline");
end

function GetGuiManager()
	if not guiManager then
		guiManager = sdk.get_managed_singleton("snow.gui.GuiManager");
	end
	
	return guiManager;
end

function SetInvisibleUI(value)

	if not disableUiOnKill then
		return;
	end
	
	GetGuiManager():set_field("InvisibleAllGUI", value);
end


function GetTime()
	return get_UpTimeSecond:call(nil);
end

function GetDeltaTime()
	--no clue why but get_DeltaTime is complete nonsense seemingly whereas get_ElapsedSecond of all things is actual deltatime
	return get_ElapsedSecond:call(nil);
end

function CheckShouldActivate()

	--log.info("MONSTER KILL");
	--log.info("lastHitPlayerIdx: "..lastHitPlayerIdx);

	if GetQuestIsOnline() then

		--myself index is only really valid if online so yknow
		local myIdx = GetLobbyManager():get_field("_myselfQuestIndex");
		log.info("MyQuestIdx: "..myIdx);

		if not activateByAnyPlayer then
			if lastHitPlayerIdx ~= myIdx then
				return;
			end
		end
	end

	if lastHitEnemy then
		local dieInfo = lastHitEnemy:call("getNowDieInfo");
		--log.info("death type: "..dieInfo);
	end

	if not activateOnCapture and lastHitEnemy then
		local dieInfo = lastHitEnemy:call("getNowDieInfo");
		--2 == capture death
		if dieInfo == 2 then
			return;
		end
	end



	if lastHitPlayerIdx < 0 then
		return;
	end


	StartSlowMo();
end


function GetShouldUseSlowMo()

	if not useSlowMo then
		return false;
	end

	if not useSlowMoInMP and GetQuestIsOnline() then
		return false;
	end

	return true;
end

function SetTimeScale(value)
	if useSlowMoThisTime then
		local scene_manager = sdk.get_native_singleton("via.SceneManager");
		local scene_manager_type = sdk.find_type_definition("via.SceneManager");
		local curScene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene");
		local timeManager = sdk.get_managed_singleton("snow.TimeScaleManager");
		
		curScene:call("set_TimeScale", value);
		timeManager:call("set_TimeScale", value);
	end
end

function StartSlowMo()
	useSlowMoThisTime = GetShouldUseSlowMo();
	isSlowMo = true;
	slowMoStartTime = GetTime();
	SetInvisibleUI(true);
end

function EndSlowMo()
	curTimeScale = 1.0;
	isSlowMo = false;
	SetInvisibleUI(false);
end

local hwKB = nil
local hwPad = nil

function CheckSlowMoSkip()

	-- grabbing the keyboard manager    
    if not hwKB then
        hwKB = sdk.get_managed_singleton("snow.GameKeyboard"):get_field("hardKeyboard") -- getting hardware keyboard manager
    end
    -- grabbing the gamepad manager
    if not hwPad then
        hwPad = sdk.get_managed_singleton("snow.Pad"):get_field("hard") -- getting hardware keyboard manager
    end
	 
	 
	if hwKB:call("getTrg", kbAnimSkipKey) or hwPad:call("orTrg", padAnimSkipBtn) then
		return true;
   end
	
	return false;
end

function HandleSlowMo()

	if not isSlowMo then
		return;
	end

	local curTime = GetTime();
	
	if CheckSlowMoSkip() then
		curTimeScale = 2;
		EndSlowMo();
		
		--if we dont make sure this is a float(1.0 instead of 1),
		--for some reason setting timescale to (int)1 actually freezes everything to zero
		--its bizarre especially as i was led to believe that lua used only floats anyway but w/e
		SetTimeScale(1.0);
		return;
	end
	
	if curTimeScale == 1 then
		curTimeScale = slowMoSpeed;
	elseif curTime - slowMoStartTime > slowMoDuration then
		curTimeScale = curTimeScale + slowMoRamp * GetDeltaTime();
		if curTimeScale >= 1 then
			EndSlowMo();
		end
	end

	SetTimeScale(curTimeScale);
end

function PreRequestCamChange(args)


	local type = sdk.to_int64(args[3]);
	--re.msg(type);
	if type == 3 then
		--type 3 == 'demo' camera type
		--somewhat annoyingly this is used for many different cameras, but we'll turn that into a feature anyway

		local manager = sdk.get_managed_singleton("snow.QuestManager");
		if not manager then
			return;
		end
		
		local endFlow = manager:get_field("_EndFlow");
		--idk, this was just the first value i found that actually changes the instant you complete the quest
		local endCapture = manager:get_field("_EndCaptureFlag");
		
		if endFlow <= 1 and endCapture == 2 then
			
			if not activateForAllMonsters then
				CheckShouldActivate();
			end
			
			if disableKillCam then				
				return sdk.PreHookResult.SKIP_ORIGINAL;
			else
				return;
			end
		elseif disableOtherCams then
			return sdk.PreHookResult.SKIP_ORIGINAL;
		end
	end
end



local enemyType;
local get_isBossEnemy;


------------------------------------MONSTER DMG AND DEATH LOGIC--------------------------------------------

function DefPost(retval)
	return retval;
end

function PreDmgCalc(args)

	if activateByEnemies then
		--dont invalidate otomo and enemy attacks if this is on
		return;
	end

	local enemy = sdk.to_managed_object(args[2]);
	local isBoss = get_isBossEnemy:call(enemy);
	if not isBoss then
		return;
	end
	
	--[[
	"Creature": 7,
	"CreatureShell": 8,
	"Enemy":  1,
	"EnemyShell":  2,
	"Otomo": 5,
	"OtomoShell" 6,
	"Player":  3,
	"PlayerShell": 4,
	"Props"  0,
	]]

	local hitInfo = sdk.to_managed_object(args[3]);
	local hitType = hitInfo:call("get_OwnerType");

	local isValidAttack = hitType == 0 or hitType == 3 or hitType == 4;
	if not isValidAttack then		
		--set last hit to negative to invalidate this attack if the monster dies from it
		lastHitPlayerIdx = -1;
		--log.info("invalid attack type: "..hitType);
	end
end

function PrePlayerAttack(args)

	local enemy = sdk.to_managed_object(args[2]);
	local isBoss = get_isBossEnemy:call(enemy);
	
	if isBoss then
		--set the last hit for this monster to the player that hit it
		local pIdx = sdk.to_int64(args[3]);
		lastHitPlayerIdx = pIdx;
		lastHitEnemy = enemy;
		--log.info("player attack idx: "..pIdx);
	end
end


function PreDie(args)

	if not activateForAllMonsters then
		--use end of quest detection logic instead
		return;
	end

	local enemy = sdk.to_managed_object(args[2]);
	local isBoss = get_isBossEnemy:call(enemy);

	if isBoss then
		CheckShouldActivate();
	end	
end

re.on_draw_ui(function()
    local changed = false;

    if imgui.tree_node("No Kill-Cam + SlowMo") then
	 
		  changed, disableKillCam = imgui.checkbox("Disable KillCam", disableKillCam);
		  changed, disableOtherCams = imgui.checkbox("Disable Other Cams", disableOtherCams);
		  changed, disableUiOnKill = imgui.checkbox("Disable UI on Kill", disableUiOnKill);		
		  
		  changed, useSlowMo = imgui.checkbox("Use SlowMo", useSlowMo);
		  changed, useSlowMoInMP = imgui.checkbox("Use SlowMo Online", useSlowMoInMP);
		  changed, slowMoSpeed = imgui.slider_float("SlowMo Speed", slowMoSpeed, 0.01, 1.0);
		  changed, slowMoDuration = imgui.slider_float("SlowMo Duration", slowMoDuration, 0.01, 30.0);
		  changed, slowMoRamp = imgui.slider_float("SlowMo Ramp", slowMoRamp, 0.1, 10);
		  
		  changed, activateForAllMonsters = imgui.checkbox("Activate For All Monsters", activateForAllMonsters);
		  changed, activateByAnyPlayer = imgui.checkbox("Activate By Any Player", activateByAnyPlayer);	
		  changed, activateByEnemies = imgui.checkbox("Activate by Enemies", activateByEnemies);	
		  changed, activateOnCapture = imgui.checkbox("Activate on Capture", activateOnCapture);
		  

		  --[[
		  --debug
		  changed, hooked = imgui.checkbox("hooked", hooked);
		  changed, isSlowMo = imgui.checkbox("isSlowMo", isSlowMo);
		  if changed and isSlowMo then
			StartSlowMo();
		  end
		  
		  changed, curTimeScale = imgui.slider_float("curTimeScale", curTimeScale, 0, 1);
		  changed, slowMoStartTime = imgui.slider_float("slowMoStartTime", slowMoStartTime, 0, 9999999);

		  changed, lastHitPlayerIdx = imgui.slider_int("lastHitPlayerIdx", lastHitPlayerIdx, -1, 3);
		  --]]
		  
        imgui.tree_pop();
    end
end)

function CheckHook()

	if hooked then
		return;
	end

	local manager = sdk.get_managed_singleton("snow.CameraManager");
	if not manager then
		return;
	end
	
	sdk.hook(sdk.find_type_definition("snow.CameraManager"):get_method("RequestActive"), PreRequestCamChange, DefPost);

	enemyType = sdk.find_type_definition("snow.enemy.EnemyCharacterBase");
	get_isBossEnemy = enemyType:get_method("get_isBossEnemy");	

	sdk.hook(enemyType:get_method("getAdjustPhysicalDamageRateBySkill"), PrePlayerAttack, DefPost, true);
	sdk.hook(enemyType:get_method("calcDamageCore"), PreDmgCalc, DefPost, true);
	sdk.hook(enemyType:get_method("questEnemyDie"), PreDie, DefPost, true);

	hooked = true;	
end


re.on_pre_application_entry("UpdateBehavior", function()
	CheckHook();
	HandleSlowMo();
end)