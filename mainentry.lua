--[[
Lua入口文件
]]

-- 添加文件查找路径
local fileIns = cc.FileUtils:getInstance()
fileIns:setPopupNotify(false)

local updPath = fileIns:getWritablePath().."/update/"
fileIns:createDirectory(updPath)

fileIns:addSearchPath("src/", true)
fileIns:addSearchPath("res/", true)

local target = cc.Application:getInstance():getTargetPlatform()
local isIOS = (target==cc.PLATFORM_OS_IPHONE or target==cc.PLATFORM_OS_IPAD)
if isIOS then
	fileIns:addSearchPath("src/64bit/", true)
	fileIns:addSearchPath("res/64bit/", true)
end

fileIns:addSearchPath(updPath, true)
fileIns:addSearchPath(updPath.."src/", true)
fileIns:addSearchPath(updPath.."res/", true)

if isIOS then
	fileIns:addSearchPath(updPath.."src/64bit/", true)
	fileIns:addSearchPath(updPath.."res/64bit/", true)
end

require("main")

-- Poco
if not isIOS then
	if fileIns:isFileExist("poco/poco_manager.luac") or fileIns:isFileExist("poco/poco_manager.lua") then
	    local poco = require("poco.poco_manager")
	    if poco then
	        poco:init_server(12345)
	    end
	end
end
