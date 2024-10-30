
--[[
初始化
]]

setmetatable(_G, {
    __newindex = function(_, name, value)
        rawset(_G, name, value)
    end
})

-- 版本兼容 (重启)[2.15.00]
local target = cc.Application:getInstance():getTargetPlatform()
if target == cc.PLATFORM_OS_ANDROID and 
    (not GAME_VERSION or GAME_VERSION < "2.15.00") then
    local luaj = require_ex "cocos.cocos2d.luaj"
    local args = {}
    local sigs = "()V"
    local className = "org/cocos2dx/lua/LuaInterface"
    luaj.callStaticMethod(className, "doReStartGame", args, sigs)
    return
end

--------------------------------------------------------------
-- framework init
CC_VERSION = cc.Configuration:getInstance():getValue("cocos2d.x.version")
CC_DISABLE_GLOBAL = false
CC_USE_FRAMEWORK = true
GAME_OPEN_C_ASSERT = false
DEBUG = (target==cc.PLATFORM_OS_WINDOWS and 2 or 0)
REPORT_BUG = false

function ReportWidgetClick(sender)
    if sender and MonitorConfig then
        local data = {
            name = sender:getName(),
            tag = sender:getTag(),
            addr = sender
        }
        if Game then
            Game:dispatchCustomEvent("CMD_CLICK_EVENT", data)
        else
            local event = cc.EventCustom:new("CMD_CLICK_EVENT")
            event.data = data
            cc.Director:getInstance():getEventDispatcher():dispatchEvent(event)
        end
    end
end

-- design init
GAME_USE_SCALE_UNKNOWN = true
FORCE_UI_CENTER = nil -- "center"

CC_DESIGN_RESOLUTION = {
    landscape = true,
    width = 1280,
    height = 720,
    cx = 640,
    cy = 360,
    autoscale = "UNKNOWN" -- UNKNOWN SHOW_ALL
}

require_ex "cocos.init"
require_ex "util.util_init"
require_ex "data.cfg_init"
require_ex "data.enum"
require_ex "data.protocol_init"
require_ex "data.event_init"
require_ex "game_config"

netCom = require_ex "lib.Network"
netCom.startSchedule()

require_ex "ui.ui_init"

--------------------------------------------------------------
-- 版本兼容 (sdk_util->Sdk, platform_util->Platform)[2.05.00]
if sdk_util and platform_util then
    if sdk_util.getMarketId then
        Sdk.setMarketId(sdk_util.getMarketId())
    else
        Sdk.setMarketId(platform_util.getMarketId())
    end
    if sdk_util.getSandbox then
        Sdk.setSandbox(sdk_util.getSandbox())
    else
        Sdk.setSandbox(platform_util.getSandbox())
    end
    Sdk.setSDKID(sdk_util.getSDKID())
    Sdk.IS_INIT = sdk_util.IS_INIT
end