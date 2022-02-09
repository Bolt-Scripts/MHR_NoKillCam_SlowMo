

-- Whether hit stop has been reset since the last time it has been set to a positive value
local was_reset = true

-- Whether hit stop has been multiplied this frame (prevent double-multiplication)
local was_set_this_frame = false

-- The last updated value of the hit stop timer
local last_timer = 0.0

local timeScaled = false;

local timeManager;
function GetTimeManager()
    if not timeManager then
        timeManager = sdk.get_managed_singleton("snow.TimeScaleManager");
    end

    return timeManager;
end

local get_TimeScale = sdk.find_type_definition("snow.TimeScaleManager"):get_method("get_TimeScale");
function GetTimescale()
    return get_TimeScale:call(GetTimeManager());
end

-- setHitStop is called once when an attack with hit stop happens.
-- Then, it's called again each frame until mHitStopTimer reaches 0.
sdk.hook(
    sdk.find_type_definition("snow.player.PlayerQuestBase"):get_method("setHitStop"),
    function(args)
        local quest_base = sdk.to_managed_object(args[2])

        -- The number of frames left for hit stop (e.g. 45.0 at the beginning of a True Charged Slash)
        local timer = quest_base:get_field("mHitStopTimer")
        local tScale = GetTimescale();
        -- re.msg("sethit "..tScale.." : "..timer.." < "..last_timer..(was_reset and "wr" or "nr").." : "..(was_set_this_frame and "wstf" or "nstf"));


        -- Prevent double-multiplication in the same frame as well as the value being
        -- multiplied every frame until infinity, when it should be decreasing steadily.
        -- The check against 50.0 is just a safeguard something wacky happens.
        if tScale < 1 then
            if timer > 0.0 and timer < 50.0 and 
                was_reset and not was_set_this_frame and not timeScaled then
                    
                log.info("hst: "..timer);
                -- re.msg("trigger "..tScale.." : "..timer);
                quest_base:set_field("mHitStopTimer", timer * tScale)
                was_reset = false
                was_set_this_frame = true
                timeScaled = true;
            end
        elseif timeScaled then
            -- re.msg("reset");
            timeScaled = false;
        end

    end,
    function(retval)
        return retval
    end
)

-- updateHitStop is called multiple times each frame.
sdk.hook(
    sdk.find_type_definition("snow.player.PlayerQuestBase"):get_method("updateHitStop"),
    function(args)
        local quest_base = sdk.to_managed_object(args[2])
        local timer = quest_base:get_field("mHitStopTimer")

        -- In multiplayer, mHitStopTimer will sometimes read as 0.0 when this method is called,
        -- while another call in the same frame will have the real value (a positive number).
        -- So, don't set last_timer to 0 unless the hit stop has definitely been reset.
        if was_reset or timer > 0.0 then
            last_timer = timer
        end
    end,
    function(retval)
        return retval
    end
)

-- resetHitStop is called frequently when hit stop is not active.
sdk.hook(
    sdk.find_type_definition("snow.player.PlayerQuestBase"):get_method("resetHitStop"),
    function(args)
        was_reset = true
    end,
    function(retval)
        return retval
    end
)

-- Called every frame (duh).
re.on_frame(
    function()
        was_set_this_frame = false
    end
)
