--[[
小游戏大厅接口文件，归属主框架
]]

local funcId = 666666
local funcKey = "demo"

Game:registerSceneEntry(funcId, string.format("games.%s.GameEntry", funcKey))

local function _checkLimit()
	return false
end

local function _checkDownload()
	return not Game:isPluginExist(funcId)
end

local function _download()
	local url = string.gsub(CDN_HOST, "platform", device.platform)
	local urlRES = string.gsub(CDN_HOST_RES, "platform", device.platform)
	local args = string.format("%s/%s.zip", AppName, funcKey)
	Game.httpCom:requestUpdatePkg(funcKey, url..args, urlRES..args)
end

local function _enterPlugin()
	if _checkDownload() then
		Game:tipMsg(Config.localize("need_download"), 3)
	elseif _checkLimit() then
		Game:tipMsg(Config.localize("condi_limit"))
	else
	    Game:enterScene(funcId, nil, funcKey)
	end
end

Game:registerAPI("enter", funcKey, function(sender)
	_enterPlugin()
end)

local apiList = {
	{"checkLimit", 		funcKey, 		_checkLimit},
	{"checkDownload", 	funcKey, 		_checkDownload},
	{"download", 		funcKey, 		_download},
}
Game:registerAPIList(apiList)
