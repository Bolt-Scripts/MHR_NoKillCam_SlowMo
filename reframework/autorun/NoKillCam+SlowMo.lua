



---------------------------Settings----------------------

local settings = {
	disableKillCam = true; --Disables the hover view of the monster from different angles after killing them
	disableOtherCams = false; --Disables fast travel cutscene cam and end of quest cam (like petting your buddies etc.) slightly glitchy with fast travel camera transitions

	disableUiOnKill = true; --Disables the UI for the slow mo duration on monster kill

	useSlowMo = true; --Enable slow mo for a certain duration of time after the last blow on the monster
	useSlowMoInMP = true; --Whether or not to use slow mo in online quests
	useMotionBlurInSlowMo = false; --ForceAdd heavy motion blur during slowmo
	slowMoSpeed = 0.2; --Slow mo amount in percentage of realtime. 0.2 = 20% speed
	slowMoDuration = 5; --Slow mo duration in seconds
	slowMoRamp = 1.5; --Speed at which it transitions back to normal time after the slow mo duration has elapsed

	activateOnCapture = false; --will trigger slowmo/hide ui when capturing the monster

	--these only work when the script is first initialized and cannot be changed during play without resetting scripts
	--IMPORTANT: also mighttt cause freezes when using Coavins DPS meter or MHR Overlay if you change them
	activateForAllMonsters = false; --will trigger slowmo/hide ui when killing any large monster, not just the final one on quest clear
	activateByAnyPlayer = true; --will trigger slowmo/hide ui when any player kills a monster, otherwise only when you do it 
	activateByEnemies = true; --will trigger slowmo/hide ui when a small monster or your pets kill a large monster, otherwise only when players do it
	
	--keys
	--for keyboard keys you can look up keycodes online with something like a javascript keycode list or demo
	--note that some keys wont work as they are taken by the game or something idk
	padAnimSkipBtn = nil; -- persistent start button on controller, 32768 is probably start button but might be broken for some and cause slowmo not to work
	kbAnimSkipKey = 27; -- persistent escape key. 32 = spacebar
	kbToggleSlowMoKey = nil; --set this to whatever key you want to toggle slowmo
	kbToggleUiKey = nil; --set this to whatever key you want to toggle UI
}
----------------------------------------------------------



local hooked = false;
local isSlowMo = false;
local useSlowMoThisTime = false;
local slowMoStartTime = 0;
local curTimeScale = 1.0;
local lastHitPlayerIdx = 0;
local lastHitEnemy = nil;

local isMotionBlur = false;
local prevMotionBlurValue;
local prevMotionBlurEnabled;

local app_type = sdk.find_type_definition("via.Application");
local get_UpTimeSecond = app_type:get_method("get_UpTimeSecond");
local get_ElapsedSecond = app_type:get_method("get_ElapsedSecond");

local guiManager = nil;
local lobbyManager = nil;
local motionBlur = nil;
local hwKB = nil;
local hwPad = nil;


local enemyType = sdk.find_type_definition("snow.enemy.EnemyCharacterBase");
local get_isBossEnemy = enemyType:get_method("get_isBossEnemy");
local getTrg = sdk.find_type_definition("snow.GameKeyboard"):get_method("getTrg");

local function SaveSettings()
	json.dump_file("NoKillCam+SlowMo_settings.json", settings);
end

local function LoadSettings()
	local loadedSettings = json.load_file("NoKillCam+SlowMo_settings.json");
	if loadedSettings then
		settings = loadedSettings;
	end
end

-- Load setting first
LoadSettings();

local function GetMotionBlur()
	if not motionBlur then
		local cam = sdk.get_managed_singleton("snow.GameCamera");
		if not cam then return nil end;

		local post = cam:call("get_GameObject"):call("getComponent(System.Type)", sdk.typeof("snow.SnowPostEffectParam"));
		if not post then return nil end;

		motionBlur = post:get_field("_SnowMotionBlur");
	end

	return motionBlur;
end

local function SetMotionBlur(val)
	GetMotionBlur():set_field("_ExposureFrame", val);
end

local function StartMotionBlur()

	if isMotionBlur or not GetMotionBlur() then return end;

	prevMotionBlurEnabled = GetMotionBlur():get_field("_Enable");
	prevMotionBlurValue = GetMotionBlur():get_field("_ExposureFrame");

	GetMotionBlur():set_field("_Enable", true);
	SetMotionBlur(100);

	isMotionBlur = true;
end


local function EndMotionBlur()

	if not isMotionBlur or not GetMotionBlur() then return end;

	GetMotionBlur():set_field("_Enable", prevMotionBlurEnabled);
	SetMotionBlur(prevMotionBlurValue);

	isMotionBlur = false;
end




local function GetMonsterActivateType(isEndQuest)
	local isRampage = sdk.get_managed_singleton("snow.QuestManager"):call("isHyakuryuQuest");
	if isEndQuest then
		if (isRampage and settings.activateForAllMonsters) or (not settings.activateForAllMonsters) then
			return true;
		end
	else
		if settings.activateForAllMonsters then
			if isRampage then
				return false;
			else
				return true;
			end
		end
	end

	return false;
end


local function GetPadDown(kc)
	-- grabbing the gamepad manager
    if not hwPad then
        hwPad = sdk.get_managed_singleton("snow.Pad"):get_field("hard"); -- getting hardware keyboard manager
    end
	
	return hwPad:call("orTrg", kc);
end
local function GetKeyDown(kc)
	-- grabbing the keyboard manager    
    if not hwKB then
        hwKB = sdk.get_managed_singleton("snow.GameKeyboard"):get_field("hardKeyboard"); -- getting hardware keyboard manager
    end

	--return getTrg:call(hwKB, kc);
	return hwKB:call("getTrg", kc);
end


local function GetLobbyManager()
	if not lobbyManager then
		lobbyManager = sdk.get_managed_singleton("snow.LobbyManager");
	end
	
	return lobbyManager;
end

local function GetQuestIsOnline()
	return GetLobbyManager():call("IsQuestOnline");
end

local function GetGuiManager()
	if not guiManager then
		guiManager = sdk.get_managed_singleton("snow.gui.GuiManager");
	end
	
	return guiManager;
end

local function SetInvisibleUI(value)

	if not settings.disableUiOnKill then
		return;
	end
	
	GetGuiManager():set_field("InvisibleAllGUI", value);
end


local function GetTime()
	return get_UpTimeSecond:call(nil);
end

local function GetDeltaTime()
	--no clue why but get_DeltaTime is complete nonsense seemingly whereas get_ElapsedSecond of all things is actual deltatime
	return get_ElapsedSecond:call(nil);
end

local function GetShouldUseSlowMo()

	if not settings.useSlowMo then
		return false;
	end

	if not settings.useSlowMoInMP and GetQuestIsOnline() then
		return false;
	end

	return true;
end

local function StartSlowMo()
	useSlowMoThisTime = GetShouldUseSlowMo();
	isSlowMo = true;
	slowMoStartTime = GetTime();
	SetInvisibleUI(true);
end

local function CheckShouldActivate()

	--log.info("MONSTER KILL");
	--log.info("lastHitPlayerIdx: "..lastHitPlayerIdx);

	if GetQuestIsOnline() then

		--myself index is only really valid if online so yknow
		local myIdx = GetLobbyManager():get_field("_myselfQuestIndex");
		--log.info("MyQuestIdx: "..myIdx);

		if not settings.activateByAnyPlayer then
			if lastHitPlayerIdx ~= myIdx then
				return;
			end
		end
	end

	if not activateOnCapture and lastHitEnemy then
		
		local dieInfo = nil;
		pcall(function() 
			dieInfo = lastHitEnemy:call("getNowDieInfo");
		end);

		--2 == capture death
		if dieInfo and dieInfo == 2 then
			return;
		end
	end

	if sdk.get_managed_singleton("snow.QuestManager"):call("isHyakuryuQuest") then
		return;
	end

	if lastHitPlayerIdx < 0 then
		return;
	end


	StartSlowMo();
end




local function SetTimeScale(value)
	if useSlowMoThisTime then
		local scene_manager = sdk.get_native_singleton("via.SceneManager");
		local scene_manager_type = sdk.find_type_definition("via.SceneManager");
		local curScene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene");
		local timeManager = sdk.get_managed_singleton("snow.TimeScaleManager");
		
		curScene:call("set_TimeScale", value);
		timeManager:call("set_TimeScale", value);

		if settings.useMotionBlurInSlowMo and GetMotionBlur() then
			SetMotionBlur(100 * (1.0 - value));
		end
	end
end



local function EndSlowMo()
	curTimeScale = 1.0;
	isSlowMo = false;
	SetInvisibleUI(false);
	EndMotionBlur();
end

local function CheckSlowMoSkip()
	return (settings.kbAnimSkipKey and GetKeyDown(settings.kbAnimSkipKey)) or (settings.padAnimSkipBtn and GetPadDown(settings.padAnimSkipBtn));
end

local ks = 200;
local function HandleSlowMo()

	if settings.kbToggleSlowMoKey and GetKeyDown(settings.kbToggleSlowMoKey) then
		if curTimeScale == 1 then
			useSlowMoThisTime = true;
			curTimeScale = settings.slowMoSpeed;
			SetTimeScale(curTimeScale);
		else
			curTimeScale = 1.0;
			SetTimeScale(curTimeScale);
		end
	end

	if settings.kbToggleUiKey and GetKeyDown(settings.kbToggleUiKey) then
		local uiState = GetGuiManager():get_field("InvisibleAllGUI");
		GetGuiManager():set_field("InvisibleAllGUI", not uiState);
	end

	if not isSlowMo then
		return;
	end

	local curTime = GetTime();
	
	if CheckSlowMoSkip() then
		log.info("SLOWMO: SKIPPED");
		curTimeScale = 2;
		EndSlowMo();
		
		--if we dont make sure this is a float(1.0 instead of 1),
		--for some reason setting timescale to (int)1 actually freezes everything to zero
		--its bizarre especially as i was led to believe that lua used only floats anyway but w/e
		SetTimeScale(1.0);
		return;
	end
	
	if curTimeScale == 1 then
		
		curTimeScale = settings.slowMoSpeed;

		if settings.useMotionBlurInSlowMo then
			StartMotionBlur();
		end

	elseif curTime - slowMoStartTime > settings.slowMoDuration then
		curTimeScale = curTimeScale + settings.slowMoRamp * GetDeltaTime();
		if curTimeScale >= 1 then
			EndSlowMo();
		end
	end

	SetTimeScale(curTimeScale);
end

local function PreRequestCamChange(args)


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
		
		if endFlow <= 0 and endCapture == 2 then
			
			if GetMonsterActivateType(true) then
				CheckShouldActivate();
			end
			
			if settings.disableKillCam then				
				return sdk.PreHookResult.SKIP_ORIGINAL;
			else
				return;
			end
		elseif settings.disableOtherCams then
			return sdk.PreHookResult.SKIP_ORIGINAL;
		end
	end
end




------------------------------------MONSTER DMG AND DEATH LOGIC--------------------------------------------

local function DefPost(retval)
	return retval;
end

local function PreDmgCalc(args)

	if settings.activateByEnemies then
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

	lastHitEnemy = enemy;
	local hitInfo = sdk.to_managed_object(args[3]);
	local hitType = hitInfo:call("get_OwnerType");

	local isValidAttack = hitType == 0 or hitType == 3 or hitType == 4;
	if not isValidAttack then		
		--set last hit to negative to invalidate this attack if the monster dies from it
		lastHitPlayerIdx = -1;
		--log.info("invalid attack type: "..hitType);
	else
		lastHitPlayerIdx = 0;
	end
end

local function PrePlayerAttack(args)

	local enemy = sdk.to_managed_object(args[2]);
	local isBoss = get_isBossEnemy:call(enemy);
	
	if isBoss then
		--set the last hit for this monster to the player that hit it
		local pIdx = sdk.to_int64(args[3]);
		lastHitPlayerIdx = pIdx;
		if lastHitPlayerIdx < 0 then
			lastHitPlayerIdx = 0;
		end
		lastHitEnemy = enemy;
		--log.info("player attack idx: "..pIdx);
	end
end


local function PreDie(args)

	if not settings.activateForAllMonsters then
		--use end of quest detection logic instead
		return;
	end

	local enemy = sdk.to_managed_object(args[2]);
	local isBoss = get_isBossEnemy:call(enemy);

	if isBoss then
		dieInfo = enemy:call("getNowDieInfo");
		if dieInfo == 65535 then
			--dont trigger for non death related leavings
			return;
		end

		lastHitEnemy = enemy;
		if GetMonsterActivateType(false) then
			CheckShouldActivate();
		end
	end
end





local function CheckHook()

	if hooked then
		return;
	end

	sdk.hook(sdk.find_type_definition("snow.CameraManager"):get_method("RequestActive"), PreRequestCamChange, DefPost);

	sdk.hook(enemyType:get_method("getAdjustPhysicalDamageRateBySkill"), PrePlayerAttack, DefPost, true);
	sdk.hook(enemyType:get_method("calcDamageCore"), PreDmgCalc, DefPost, true);
	sdk.hook(enemyType:get_method("questEnemyDie"), PreDie, DefPost, true);

	hooked = true;
end


re.on_pre_application_entry("UpdateBehavior", function()
	CheckHook();
	HandleSlowMo();
end)




-------------------------UI GARBAGE----------------------------------

re.on_draw_ui(function()
    local changed = false;

    if imgui.tree_node("No Kill-Cam + SlowMo") then
	 
		changed, settings.disableKillCam = imgui.checkbox("Disable KillCam", settings.disableKillCam);
		changed, settings.disableOtherCams = imgui.checkbox("Disable Other Cams", settings.disableOtherCams);
		changed, settings.disableUiOnKill = imgui.checkbox("Disable UI on Kill", settings.disableUiOnKill);
		changed, settings.useSlowMo = imgui.checkbox("Use SlowMo", settings.useSlowMo);
		changed, settings.useSlowMoInMP = imgui.checkbox("Use SlowMo Online", settings.useSlowMoInMP);
		changed, settings.useMotionBlurInSlowMo = imgui.checkbox("Use Motion Blur In SlowMo", settings.useMotionBlurInSlowMo);

		changed, settings.slowMoSpeed = imgui.slider_float("SlowMo Speed", settings.slowMoSpeed, 0.01, 1.0);
		changed, settings.slowMoDuration = imgui.slider_float("SlowMo Duration", settings.slowMoDuration, 0.1, 15.0);
		changed, settings.slowMoRamp = imgui.slider_float("SlowMo Ramp", settings.slowMoRamp, 0.1, 10);



		changed, settings.activateForAllMonsters = imgui.checkbox("Activate For All Monsters", settings.activateForAllMonsters);
		changed, settings.activateByAnyPlayer = imgui.checkbox("Activate By Any Player", settings.activateByAnyPlayer);
		changed, settings.activateByEnemies = imgui.checkbox("Activate by Enemies", settings.activateByEnemies);
		changed, settings.activateOnCapture = imgui.checkbox("Activate on Capture", settings.activateOnCapture);

		

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

re.on_config_save(function()
	SaveSettings();
end)