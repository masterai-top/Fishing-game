--[[
主入口
]]

-- 标记版本号
GAME_VERSION = "2.74.60"

local ignorNames = {
    ["math"] = true,
    ["string"] = true,
    ["table"] = true,
}

--[[
require扩展
重载模块
]]
function require_ex( _mname )
    if ignorNames[_mname] ~= nil then
        return require(_mname)
    end
    package.loaded[_mname] = nil
    return require(_mname)
end

--[[
try..catch..
]]
local function tryRequire()
    require_ex "zlib"
end

--[[
启动APP
]]
local function startApp()
    require_ex("app.MyApp"):create():run()
end

local function main()
    startApp()
    tryRequire()
end

require_ex "GameInit"
Sdk.init()

local status, msg = xpcall(main, __G__TRACKBACK__)
if not status then
    print(msg)
    if GAME_OPEN_C_ASSERT == true then
        local CHelper = cc.LuaCHelper:theHelper()
        CHelper:luaCAssert()
    end
end
