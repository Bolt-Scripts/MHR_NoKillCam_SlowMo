



---------------------------Settings----------------------

local disableKillCam = true; --Disables the hover view of the monster from different angles after killing them
local disableOtherCams = false; --Disables fast travel cutscene cam and end of quest cam (like petting your buddies etc.) slightly glitchy with fast travel camera transitions

local disableUiOnKill = true; --Disables the UI for the slow mo duration on monster kill

local useSlowMo = true; --Enable slow mo for a certain duration of time after the last blow on the monster
local slowMoSpeed = 0.2; --Slow mo amount in percentage of realtime. 0.2 = 20% speed
local slowMoDuration = 5; --Slow mo duration in seconds
local slowMoRamp = 1.5; --Speed at which it transitions back to normal time after the slow mo duration has elapsed

----------------------------------------------------------



local hooked = false;
local isSlowMo = false;
local slowMoStartTime = 0;
local curTimeScale = 1.0;

local wasUiVisible = false;

local app_type = sdk.find_type_definition("via.Application");
local get_UpTimeSecond = app_type:get_method("get_UpTimeSecond");
local get_ElapsedSecond = app_type:get_method("get_ElapsedSecond");

local guiManager = nil;

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
	
	if value then
		wasUiVisible = GetGuiManager():get_field("InvisibleAllGUI");
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

function SetTimeScale(value)
	if useSlowMo then
		local scene_manager = sdk.get_native_singleton("via.SceneManager");
		local scene_manager_type = sdk.find_type_definition("via.SceneManager");
		local curScene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene");
		local timeManager = sdk.get_managed_singleton("snow.TimeScaleManager");
		
		curScene:call("set_TimeScale", value);
		timeManager:call("set_TimeScale", value);
	end
end

function StartSlowMo()
	isSlowMo = true;
	slowMoStartTime = GetTime();
	SetInvisibleUI(true);
end



function HandleSlowMo()

	if not isSlowMo then
		return;
	end

	local curTime = GetTime();
	
	if curTimeScale == 1 then
		curTimeScale = slowMoSpeed;
	elseif curTime - slowMoStartTime > slowMoDuration then
		curTimeScale = curTimeScale + slowMoRamp * GetDeltaTime();
		if curTimeScale >= 1 then
			--if we dont make sure this is a float(1.0 instead of 1),
			--for some reason setting timescale to (int)1 actually freezes everything to zero
			--its bizarre especially as i was led to believe that lua used only floats anyway but w/e
			curTimeScale = 1.0;
			isSlowMo = false;
			SetInvisibleUI(wasUiVisible);
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
			
			StartSlowMo();
			
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

function PostRequestCamChange(ret)
	return ret;
end

function CheckHook()

	if hooked then
		return;
	end

	local manager = sdk.get_managed_singleton("snow.CameraManager");
	if not manager then
		return;
	end
	
	sdk.hook(sdk.find_type_definition("snow.CameraManager"):get_method("RequestActive"), PreRequestCamChange, PostRequestCamChange);
	hooked = true;	
end



re.on_draw_ui(function()
    local changed = false;

    if imgui.tree_node("No Kill-Cam + SlowMo") then
	 
		  changed, disableKillCam = imgui.checkbox("Disable KillCam", disableKillCam);
		  changed, disableOtherCams = imgui.checkbox("Disable Other Cams", disableOtherCams);
		  changed, disableUiOnKill = imgui.checkbox("Disable UI on Kill", disableUiOnKill);		
		  
		  changed, useSlowMo = imgui.checkbox("Use SlowMo", useSlowMo);
		  changed, slowMoSpeed = imgui.slider_float("SlowMo Speed", slowMoSpeed, 0.01, 1.0);
		  changed, slowMoDuration = imgui.slider_float("SlowMo Duration", slowMoDuration, 0.01, 30.0);
		  changed, slowMoRamp = imgui.slider_float("SlowMo Ramp", slowMoRamp, 0.1, 10);
		  
		  --[[
		  --debug
		  changed, hooked = imgui.checkbox("hooked", hooked);
		  changed, isSlowMo = imgui.checkbox("isSlowMo", isSlowMo);
		  if changed and isSlowMo then
			StartSlowMo();
		  end
		  
		  changed, curTimeScale = imgui.slider_float("curTimeScale", curTimeScale, 0, 1);
		  changed, slowMoStartTime = imgui.slider_float("slowMoStartTime", slowMoStartTime, 0, 9999999);
		  --]]
		  
        imgui.tree_pop();
    end
end)


re.on_pre_application_entry("UpdateBehavior", function()
	CheckHook();
	HandleSlowMo();
end)