



---------------------------Settings----------------------

local disableKillCam = true; --Disables the hover view of the monster from different angles after killing them
local disableOtherCams = false; --Disables fast travel cutscene cam and end of quest cam (like petting your buddies etc.) slightly glitchy with fast travel camera transitions

local useSlowMo = true; --Enable slow mo for a certain duration of time after the last blow on the monster
local slowMoSpeed = 0.2; --Slow mo amount in percentage of realtime. 0.2 = 20% speed
local slowMoDuration = 5; --Slow mo duration in seconds
local slowMoRamp = 0.0175; --Speed at which it transitions back to normal time after the slow mo duration has elapsed (may be framerate dependant because im lazy)

----------------------------------------------------------



local hooked = false;
local isSlowMo = false;
local slowMoStartTime = 0;
local curTimeScale = 1.0;

function GetTime()
	local app = sdk.get_native_singleton("via.Application");
	local appType = sdk.find_type_definition("via.Application");
	local curTime = sdk.call_native_func(app, appType, "get_UpTimeSecond");
	return curTime;
end

function SetTimeScale(value)
	local scene_manager = sdk.get_native_singleton("via.SceneManager");
	local scene_manager_type = sdk.find_type_definition("via.SceneManager");
	local curScene = sdk.call_native_func(scene_manager, scene_manager_type, "get_CurrentScene");
	local timeManager = sdk.get_managed_singleton("snow.TimeScaleManager");
	
	curScene:call("set_TimeScale", value);
	timeManager:call("set_TimeScale", value);
end

function StartSlowMo()
	isSlowMo = true;
	slowMoStartTime = GetTime();
end

function HandleSlowMo()

	if not isSlowMo then
		return;
	end

	local curTime = GetTime();
	
	if curTimeScale == 1 then
		curTimeScale = slowMoSpeed;
	elseif curTime - slowMoStartTime > slowMoDuration then
		curTimeScale = curTimeScale + slowMoRamp;
		if curTimeScale >= 1 then
			--if we dont make sure this is a float(1.0 instead of 1),
			--for some reason setting timescale to (int)1 actually freezes everything to zero
			--its bizarre especially as i was led to believe that lua used only floats anyway but w/e
			curTimeScale = 1.0;
			isSlowMo = false;
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
		
			if useSlowMo then
				StartSlowMo();
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
		  
		  changed, useSlowMo = imgui.checkbox("Use SlowMo", useSlowMo);
		  changed, slowMoSpeed = imgui.slider_float("SlowMo Speed", slowMoSpeed, 0.01, 1.0);
		  changed, slowMoDuration = imgui.slider_float("SlowMo Duration", slowMoDuration, 0.01, 30.0);
		  changed, slowMoRamp = imgui.slider_float("SlowMo Ramp", slowMoRamp, 0.001, 0.1);
		  
		  --[[
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