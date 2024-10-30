--[[
管理器
]]

local director = cc.Director:getInstance()
local fileIns = cc.FileUtils:getInstance()
local scheduler = director:getScheduler()
local eventDispatcher = director:getEventDispatcher()

local M = class("GameMonitor")
local _TAG = "GAME"

-- 重载列表
local ReloadList = {
    "config.",
    "cocos.",
    "data.",
    "effect.",
    "games.",
    "lib.",
    "packages.",
    "tool.",
    "ui.",
    "util.",
    "game_config",
    "GameInit",
    "GameMonitor",
}
local ReloadListExt = {
    "app",
    "cmd",
    "main",
    "mainentry",
}
local ReloadVer = {
    ["xgame"] = "2.61.00",
    ["qgame"] = "2.71.00",
    ["zgame"] = "2.70.40",
    ["mgame"] = "2.71.00",
}

local function _crashEnd()
    if Platform.BuglyEnable and buglySetTag then
        buglySetTag(84453)
    end
    director:endToLua()
end

function M:ctor()
    if CC_SHOW_FPS then
        director:setDisplayStats(true)
    end

    -- 入口UI
    self._sceneEntry = {
        [ENUM.SCENCE.LOGIN]     = "ui.login.LoginUI",
        [ENUM.SCENCE.PLATFORM]  = "ui.hall.HallUI",
    }

    -- 前台
    self._isFore = true
    -- 场景ID（类似游戏状态机，并非Cocos Scene）
    self._scenceIdx = 0

    self._waitingLayer = nil
    self._blockStrs = nil

    self._restart = false
    self._verCfg = {}

    -- 更新函数列表
    self._updateFunc = {}
    -- 延迟回调
    self._delayStamp = 0
    self._delayFunc = {}
    -- 注册API列表
    self._pluginAPI = {}
    -- API字典
    self._apiMap = {}

    self._autoStart = false

    -- 登录成功后预先获取的数据执行函数
    self._preDataList = {}
    self._preDataIdx = 0

    -- 功能限制判断函数列表
    self._limitFuncList = {}

    -- 热更新检测备案 (二次进入不检测更新)
    self._updBackup = {}
    -- APK可选更新
    self.updApp = nil
    self.updAppV = nil

    self:scheduleUpdate()
end

function M:init()
    self.localDB = cc.UserDefault:getInstance()
    self.eventMgr = require_ex("data.EventManager")
    self.networkMgr = require_ex("data.NetworkManager")
    self.uiManager = require_ex("ui.base.UIManager")
    self.effManager = require_ex("effect.EffectManager")
    self.httpCom = require_ex("lib.HttpCom")
    self.connectHandler = require_ex("lib.Connector")
    cc.exports.Timer = require("lib.Timer").new()
end

function M:destroy()

end

function M:restart(callback)
    eventDispatcher:removeCustomEventListeners(cc.EVENT_COME_TO_FOREGROUND)
    eventDispatcher:removeCustomEventListeners(cc.EVENT_COME_TO_BACKGROUND)
    eventDispatcher:removeEventListenersForType(cc.EVENT_KEYBOARD)
    self.eventMgr:removeAllEvent()
    self.connectHandler:stopHeartBeat()
    netCom.endSchedule()
    netCom.clearCmdCallBack()
    netCom.clearParsePack()
    netCom.closeNetWork()
    self.httpCom:prepareNewDownload()

    Audio.setMusicVolume(0)
    Audio.stopAllSounds()

    GAME_RESTART = {
        marketId = Sdk.getMarketId(),
        sandbox = Sdk.getSandbox(),
        sdkId = Sdk.getSDKID(),
        sdkInit = Sdk.IS_INIT,
    }

    self:purgeAllCache(false, true)

    local keys = table.keys(_G)
    for _, k in ipairs(keys) do
        if string.find(k, "Config") then
            _G[k] = nil
        end
    end

    Game = nil
    cc.exports = {}

    if type(callback) == "function" then
        callback()
    elseif callback then
        display.runScene(display.newScene("Restart"))
        require("mainentry")
    end
end

------------------------------------
-- Update
function M:schedule(callback, interval)
    interval = interval or 0
    return scheduler:scheduleScriptFunc(callback, interval, false)
end

function M:scheduleUpdate()
    self._updateEntry = self:schedule(handler(self, self.update), 0)
end

function M:update(dt)
    for _, f in pairs(self._updateFunc) do
        f(dt)
    end
    while self._delayFunc[1] and self._delayFunc[1].stamp <= self._delayStamp do
        self._delayFunc[1].func()
        table.remove(self._delayFunc, 1)
    end
    -- 计时器
    self._delayStamp = self._delayStamp + dt
    if Timer then
        Timer:update(dt)
    end
    -- 声音播放序列
    if Audio then
        Audio.playSound_()
    end
end

--[[
添加/注册更新函数
@param key  string      关键字
@param func function    执行函数
]]
function M:registerUpdateFunc(key, func)
    if key then
        self._updateFunc[key] = func
    end
end

--[[
删除/注销更新函数
@param key  string  关键字
]]
function M:unregisterUpdateFunc(key)
    if key then
        self._updateFunc[key] = nil
    end
end

--[[
添加/注册账号登出重置时执行函数
账号登出时清空数据
@param target   class       类对象
@param func     function    执行函数
]]
function M:registerLogoutReset(target, func)
    self:addEventListenerWithSceneGraphPriority(target, GEvent("GAME_ON_LOGOUT_EVENT"), func)
end

--[[
延时回调函数
@param func     function    执行函数
@param delay    number      延迟时间
@param key      string      预留关键字(取消时使用)
]]
function M:performDelay(func, delay, key)
    delay = delay or 0.001
    local idx = Table.bsearch(self._delayFunc, self._delayStamp+delay, "stamp")
    table.insert(self._delayFunc, idx+1, {stamp=self._delayStamp+delay, func=func, key=key})
end

function M:unperformDelay(key)
    if not key then return end
    for i, v in ipairs(self._delayFunc) do
        if v.key == key then
            table.remove(self._delayFunc, i)
            break
        end 
    end
end

function M:unperformAll()
    self._delayFunc = {}
end

------------------------------------
-- 进入大厅前预先执行的函数
function M:registerPrepareData(func, toHead)
    if toHead then
        table.insert(self._preDataList, 1, func)
    else
        table.append(self._preDataList, func)
    end
end

function M:registerPrepareList(funcList, toHead)
    if toHead then
        table.beforeto(self._preDataList, funcList)
    else
        table.insertto(self._preDataList, funcList)
    end
end

function M:getPrepareInfo()
    return string.format("Prepare [%s/%s]", self._preDataIdx, #self._preDataList)
end

function M:resetPrepare()
    self._preDataIdx = 0
    self:unperformDelay("ACTIVITY_CDN")
end

function M:isPreparing()
    return self._preDataIdx > 0
end

function M:prepareNext()
    if self._rePreparing then
        self:unperformDelay("REPREPARE")
        self._rePreparing = nil
    end
    self:destroyNetBadUI()
    if self:funcIsOpen("loading") then
        self:destroyWaitUI()
    end

    self._preDataIdx = self._preDataIdx + 1
    if self._preDataIdx > #self._preDataList then
        self:doPluginAPI("update", "loading", 100)
        Log.i("Prepare Finished", _TAG)
        self:performDelay(handler(self, self.prepareFinish), 0.1)
    else
        self:doPluginAPI("update", "loading", 100*self._preDataIdx/#self._preDataList)
        self._preDataList[self._preDataIdx]()
    end
end

function M:prepareFinish()
    self._preDataIdx = 0
    self:destroyWaitUI()
    self:unlockTouch()
    if self._handlePPF then
        scheduler:unscheduleScriptEntry(self._handlePPF)
        self._handlePPF = nil
    end
    
    if self:funcIsOpen("loading") then
        self:dispatchCustomEvent(GEvent("GAME_PREPARE_FINISH"))
        return
    end
    if self._scenceIdx > ENUM.SCENCE.PLATFORM then
        self.reloadToGame = true
        self:enterScene(self._scenceIdx)
    else
        -- 记录登录状态
        self.localDB:setStringForKey("login_acnt", self:doPluginAPI("get", "account"))
        self:enterScene(ENUM.SCENCE.PLATFORM)
    end
end

------------------------------------
-- 热更新备份，每个检测点只检测一次
function M:backupUpdate(gameid)
    self._updBackup[gameid] = true
end

function M:isGameUpdated(gameid)
    return self._updBackup[gameid]
end

function M:resetUpdate(gameid)
    if gameid then
        self._updBackup[gameid] = nil
    else
        self._updBackup = {}
    end
end

------------------------------------
-- Background or foreground
function M:onBack()
    self._isFore = false
end

function M:onFore()
    self._isFore = true
end

function M:isFore()
    return self._isFore
end

function M:showCapture()
    -- local captureFile = fileIns:getWritablePath()..ENUM.DEFAULT.CAPTURE
    -- if not fileIns:isFileExist(captureFile) then
    --     captureFile = ENUM.DEFAULT.SCREENSHOT
    -- end
    -- local winSize = director:getWinSize()
    -- if not Assist.isEmpty(self.screenshot) then
    --     self.screenshot:removeSelf()
    --     self.screenshot = nil
    -- end
    -- director:getTextureCache():reloadTexture(captureFile)
    -- local sp = display.newSprite(captureFile)
    -- if not sp then return end

    -- -- blur
    -- if ENUM.DEFAULT.SHADER and ENUM.DEFAULT.SHADER.blur then
    --     local size = sp:getContentSize()
    --     local glprogram = cc.GLProgramCache:getInstance():getGLProgram(ENUM.DEFAULT.SHADER.blur)
    --     local glprogramstate = cc.GLProgramState:getOrCreateWithGLProgram(glprogram)
    --     glprogramstate:setUniformVec2("resolution", {x=size.width, y=size.height})
    --     glprogramstate:setUniformFloat("blurRadius", 8.0)
    --     glprogramstate:setUniformFloat("sampleNum", 4.0)
    --     sp:setGLProgramState(glprogramstate)
    -- end
    -- -- adapt
    -- adaptNode(sp, -667)

    -- self:getScene():addChild(sp)
    -- sp:setPosition(winSize.width / 2, winSize.height / 2)

    -- self.screenshot = sp
end

function M:hideCapture()
    -- if not Assist.isEmpty(self.screenshot) then
    --     self.screenshot:removeSelf()
    -- end
    -- self.screenshot = nil
    -- self:getScene():performWithDelay(function()
    --     Assist.captureScreen()
    -- end, 0.5)
end

------------------------------------
-- 退出游戏
--[[
用户交互退出游戏
如果接了第三方SDK，优先调用第三方SDK的退出
@param ignoreTip  boolean   忽略二次确认
]]
function M:exitGame(ignoreTip)
    if device.platform == "android" and Sdk.checkOpen() then
        Sdk.exit()
    else
        self:exitByGame(ignoreTip)
    end
end

--[[
游戏退出逻辑
@param ignoreTip  boolean   忽略二次确认
]]
function M:exitByGame(ignoreTip)
    if ignoreTip then
        _crashEnd()
    else
        showConfirmTip({
            sTip = Config.localize("exit_confirm"),
            fCallBack1 = function()
                _crashEnd()
            end,
            ignoreClose = true,
            sLayerName = "exit"
        }, nil, ENUM.UI_Z.SYSTIP)
    end
end

------------------------------------
-- 功能入口开放检测
function M:checkFuncLimit(funcKey, limit)
    return {open = true, tip = FuncListKeyConfig[funcKey].limit_tip}
end

function M:setFuncLimit(funcKey, limitFunc)
    if type(funcKey) == "number" then
        funcKey = FuncListConfig.key(funcKey)
    end
    self._limitFuncList[funcKey] = limitFunc
end

--[[
功能是否开放
@param funcKey  string  功能名称(关键字)
]]
function M:funcIsOpen(funcKey, params, default)
    if type(funcKey) == "number" then
        funcKey = FuncListConfig.key(funcKey)
    end
    if self._limitFuncList[funcKey] then
        return self._limitFuncList[funcKey](params)
    end

    if not FuncListKeyConfig[funcKey] then
        if default ~= nil then
            return default
        else
            return true
        end
    end

    local state = FuncListKeyConfig[funcKey].state
    --local limit = FuncListKeyConfig[funcKey].limit
    --if state == 2 and not Assist.isEmpty(limit) then
    --    limit = self:checkFuncLimit(funcKey, limit)
    --end
    return state > 0
end

------------------------------------
-- 资源预加载
function M:preloadSpriteFrame(addList)
    if not CHECK_PLIST_TEX then return end
    local SpriteFrames = {
        "tp/gameres_activity",
        "tp/gameres_general_board",
        "tp/gameres_general_board_ext",
        "tp/gameres_general_button",
        "tp/gameres_general_daoju",
        "tp/gameres_general_front",
        "tp/gameres_general_Icon",
        "tp/gameres_general_poke",
        "tp/gameres_general_touxiang",
    }
    if type(addList) == "table" then
        table.insertto(SpriteFrames, addList)
    elseif type(addList) == "boolean" and addList then
        table.insert(SpriteFrames, "subgame/catchFish/tp/subgame_catchFish")
        table.insert(SpriteFrames, "subgame/catchFish/tp/subgame_catchFish_fish")
		table.insert(SpriteFrames, "subgame/catchFish/tp/subgame_catchFish_ext")
    end
    for _,v in ipairs(SpriteFrames) do
        Assist.addSpriteFrames(v)
    end
end

function M:preloadSpine(sIdx)
    -- Spine预加载
    local SpinePreload = {
        [ENUM.SCENCE.LOGIN] = {},
        [ENUM.SCENCE.PLATFORM] = {},
    }
    if sIdx and SpinePreload[sIdx] and #SpinePreload[sIdx] > 0 then
        local Actor = require_ex("ui.base.Actor")
        for _, spine in ipairs(SpinePreload[sIdx]) do
            Actor:new(spine)
        end
    end
end

function M:preloadShader()
    if not ENUM.DEFAULT.SHADER then return end
    for _, v in pairs(ENUM.DEFAULT.SHADER) do
        local p = cc.GLProgram:create(v .. ".vsh", v .. ".fsh")
        p:link()
        p:updateUniforms()
        cc.GLProgramCache:getInstance():addGLProgram(p, v)
    end
end

function M:preloadMusic()
    local filename
    -- 登录背景音乐
    filename = SoundConfig.file("LoginUI>bgm")
    Audio.preloadMusic(filename)
    -- 大厅背景音乐
    filename = SoundConfig.file("HallUI>bgm")
    Audio.preloadMusic(filename)
end

function M:preloadEffect()

end

--[[
清除所有缓存
@param ignoreReload     boolean     忽略重载
@param withExt          boolean     重载扩展列表（模拟App重启）
]]
function M:purgeAllCache(ignoreReload, withExt)
    if self._updateEntry then
        scheduler:unscheduleScriptEntry(self._updateEntry)
        self._updateEntry = nil
    end
    if self.betMng then
        self.betMng:betStop()
    end
    if self.eventMgr then
        self.eventMgr:removeAllEvent()
    end

    if ignoreReload then return end

    director:purgeCachedData()
    cc.SpriteFrameCache:destroyInstance()
    director:getTextureCache():removeAllTextures()

    local reloadList = {}
    if withExt then
        table.merge(reloadList, ReloadList)
        table.merge(reloadList, ReloadListExt)
    else
        reloadList = ReloadList
    end
    for k, _ in pairs(package.preload) do
        for _, v in ipairs(reloadList) do
            if string.find(k, v) == 1 then
                package.preload[k] = nil
                break
            end
        end
    end
    for k, _ in pairs(package.loaded) do
        for _, v in ipairs(reloadList) do
            if string.find(k, v) == 1 then
                package.loaded[k] = nil
                break
            end
        end
    end
end

function M:purgeUnused(addList, force)
    force = true -- 强制清(MemoryWarning)
    if LOW_MACHINE or device.platform=="ios" or force then
        display.removeUnusedSpriteFrames()
        if CHECK_PLIST_TEX then
            self:preloadSpriteFrame(addList)
        end
    end
end

------------------------------------
-- 通信接口
function M:initNetWork()
    self.connectHandler:startSchedule()
    self.connectHandler:doConnect()
end

function M:closeNetWork()
    self:dispatchCustomEvent(GEvent("NET_READY_RECONNECT"), {reconnect=true})
    self:showWaitUI(Config.localize("svr_is_connecting"))
    self.connectHandler:reinitConnectEnv()
    netCom.closeNetWork()
    self.connectHandler:clearTimeLimit()
    self.connectHandler:startSchedule()
    self.connectHandler:doConnect()
end

function M:reconnect()
    self.connectHandler:reinitConnectEnv()
    self.connectHandler:doConnect()
end

function M:isGameNeedReconn()
    return self._scenceIdx > ENUM.SCENCE.LOGIN
end

------------------------------------
-- 登入登出
function M:preLogin()
    self:initPlugin("chat")
    self:initPlugin("loading")
    self:initPlugin("service")
    self:initPlugin("set")

    self:initPlugin("login")
end

function M:login(callback, updated)
    -- 初始化登录所依赖的其他模块
    self:preLogin()

    self.uiManager:hideLoading()
    self:enterScene(ENUM.SCENCE.LOGIN)

    if type(callback) == "function" then 
        callback()
    end
end

function M:onLoginFinished(info)
    if self._preDataIdx > 0 then 
        self:performDelay(function()
            self._preDataIdx = self._preDataIdx - 1
            self:prepareNext()
        end, 2, "REPREPARE")
        self._rePreparing = true
        return 
    end
    self:dispatchCustomEvent(GEvent("GAME_ON_LOGOUT_EVENT"), {reconnect=true})

    if self.uiManager then
        self.uiManager:hideLoading()
    end

    if self:funcIsOpen("loading") then
        self:doPluginAPI("enter", "loading")
    else
        self:showWaitUI(Config.localize("loading_hall"), true)
    end

    self:initPlugin()
    Timer:setCurTimeStamp(info.tick)
    if DEBUG_OFFLINE then
        self:doPluginAPI("update", "loading", 100)
        self._handlePPF = self:schedule(handler(self, self.prepareFinish), 1)
    else
        local scene = self:getScene()
        if scene and scene.__action__ then
            scene:stopAction(scene.__action__)
            scene.__action__ = nil
        end

        self:resetPrepare()
        self:prepareNext()
    end
end

function M:onLoginFail(msg)
    self:destroyNetBadUI()
    self:destroyWaitUI()
    if self.uiManager then
        self.uiManager:hideLoading()
    end

    local function _resetLogin_()
        local loginUI = self.uiManager:getLayer("LoginUI")
        if loginUI then
            loginUI:resetLoginCD(true)
        else
            self:doPluginAPI("login", "out")
        end
    end

    if tonumber(msg) then
        self:tipError(msg, 2, _resetLogin_)
    elseif type(msg) == "string" then
        self:tipMsg(msg, 2, _resetLogin_)
    else
        _resetLogin_()
    end
end

-- 账号登出
function M:logOut()
    self._preDataIdx = 0
    self:destroyWaitUI()
    netCom.closeNetWork(true)
    self.connectHandler:onLogout()
    self:dispatchCustomEvent(GEvent("GAME_ON_LOGOUT_EVENT"), {})
    
    if self:funcIsOpen("loading") then
        self.uiManager:removeLoadingUI()
    end
end

------------------------------------
-- 游戏模块初始化
local checkLuaExt = {".lua", ".luac"}

function M:isPluginExist(pIdx)
    if not pIdx or not self._sceneEntry[pIdx] then
        return false
    end
    return self:isLuaFileExist(self._sceneEntry[pIdx])
end

function M:isLuaFileExist(luaPath)
    local localPath = string.gsub(luaPath, "%.", "/")
    local checkPath, fullName = false

    for _,v in pairs(checkLuaExt) do
        checkPath = localPath..v
        fullName = fileIns:fullPathForFilename(checkPath)
        if fullName ~= "" then
            return true
        end
    end

    return false
end

--[[
插件(功能模块)初始化
@param k            插件名或ID
@param init_path    lua入口 (1:ui.[k].[K]Init)
]]
function M:initPlugin(k)
    local function requireInit_(key, init_path)
        if init_path == "1" then
            init_path = string.format("ui.%s.%sInit", key, string.ucfirst(key))
        end
        if self:isLuaFileExist(init_path) then
            require(init_path)
        end
    end

    if k then
        local v = FuncListKeyConfig[k]
        if v and not Assist.isEmpty(v.init_path) then
            requireInit_(k, v.init_path)
        end
    else
        for kk, v in pairs(FuncListKeyConfig) do
            if type(v) == "table" and not Assist.isEmpty(v.init_path) then
                requireInit_(kk, v.init_path)
            end
        end
    end
end

------------------------------------
-- 场景流
function M:preStart(reload)
    -- 注册全局监听事件（键盘事件），只注册一次
    if not reload then
        self:addGlobalEvent()
    end
    -- 预加载
    self:preloadSpriteFrame()
    self:preloadShader()
    self:preloadMusic()
    self:preloadEffect()

    if not self._scene then
        self:setScene()
    end
end

function M:gameStart(reload, checkReload)
    if not reload and not checkReload then
        fileIns:writeStringToFile("========GameStart========\n", director:getLogFilePath())
    end

    -- 二次请求/版本兼容
    if not FuncListServer or (reload and GAME_VERSION < ReloadVer[AppName]) then
        self:checkVersionComp(handler(self, self.gameStart))
        return
    end

    self:preStart(reload or checkReload)

    -- 更新检测
    local entryUI = self._scene:getChildByTag(-9866)
    if not Assist.isEmpty(entryUI) then
        entryUI:removeFromParent()
        entryUI = nil
    end
    local params = {
        csb = "ui/common/updateUI.csb",
        gameid = GAME_FRAME_ID,
        version = GAME_VERSION or Platform.getAppVersion(),
        onenter = handler(self, self.checkUpdNotice),
        onexit = handler(self, self.login),
    }
    entryUI = require("ui.update.GameEntryUI").new(params):addToScene()
    entryUI:setTag(-9866)
end

--[[
登录前请求维护公告
]]
function M:checkUpdNotice()
    if GAME_VERSION < "2.07.00" then
        self:login()
        return
    end

    local function _checkSucc_(recv)
        local t = json.decode(recv)
        if type(t) == "table" and #t > 0 then
            NoticeList = t
            for _,v in ipairs(t) do
                if v.key == "update" then
                    UPDNOTICE_PAGE = v.url or UPDNOTICE_PAGE
                    break
                end
            end
        else
            NoticeList = nil
        end

        self:login()
    end

    self.httpCom:httpGet(PHP_HOST.."notices/prelogin", _checkSucc_, handler(self, self.login), PHP_HOST_RES.."notices/prelogin")
end

--[[
版本兼容（2.61.00）
二次请求，减少后台配置信息请求失败
]]
function M:checkVersionComp(callback)
    local function _checkSucc_(recv)
        FuncListServer = {}
        local t = json.decode(recv)
        if type(t) == "table" and #t == 0 then
            FuncListServer = t.plugins or {}
            HallServer = {
                left = {area="left", funcs=String.toTable(t.hall_left)},
                center = {area="center", funcs=String.toTable(t.hall_center)},
                right = {area="right", funcs=String.toTable(t.hall_right)},
                top = {area="top", funcs=String.toTable(t.hall_top)},
                bottom = {area="bottom", funcs=String.toTable(t.hall_bottom)},
                welfare = {area="welfare", funcs=String.toTable(t.hall_welfare)},
                hotact = {area="hotact", funcs=String.toTable(t.hall_hotact)},
            }
            resetFuncList()
        end

        callback(nil, true)
    end

    local function _checkFail_()
        FuncListServer = {}
        callback(nil, true)
    end

    local url = PHP_HOST.."cmdcheck.php"
    local urlRES = PHP_HOST_RES.."cmdcheck.php"
    local data = {
        opid = Sdk.getMarketId(),
        opsig = Sdk.getMarketId(),
        platform = device.platform,
        udid = Platform.getUdid(),
        appv = Platform.getAppVersion(),
        resv = self.localDB:getStringForKey("res_ver_"..GAME_FRAME_ID, Platform.getAppVersion()),
        actv = self.localDB:getStringForKey("actv"),
    }
    local req = {}
    for k,v in pairs(data) do
        req[#req+1] = string.format("%s=%s", k, v)
    end
    local reqStr = table.concat(req, "&")

    self.httpCom:httpGet(string.format("%s?%s", url, reqStr), _checkSucc_, _checkFail_, string.format("%s?%s", urlRES, reqStr))
end

--[[
检测游戏是否需要更新
@param gameid       number/function     游戏ID/callback
@param callback     function/boolean    检测回调/通用提示
@usage 
    -- 使用默认处理方案
    Game:checkGameUpd(true)
    -- 自定义处理方案
    Game:checkGameUpd(1103, function(verUpd)
        if verUpd then
            -- do something
        else
            -- do something or nothing
        end
    end)
]]
function M:checkGameUpd(gameid, callback)
    if device.platform == "windows" or not self:funcIsOpen("update") then return end
    if type(gameid) ~= "number" and not callback then
        callback = gameid
        gameid = GAME_FRAME_ID
    end
    gameid = gameid or GAME_FRAME_ID

    if type(callback) == "boolean" and callback then
        callback = function(verUpd)
            if verUpd then
                showConfirmTip({
                    sTip = string.format(Config.localize("check_upd_tip"), verUpd),
                    fCallBack1 = function()
                        if device.platform == "android" then
                            Platform.doReStartGame("", 0.1)
                        else
                            self:restart(true)
                        end
                    end,
                    delay1 = 10,
                    blankClose = false
                }, nil, ENUM.UI_Z.SYSTIP)
            end
        end
    end

    if type(callback) ~= "function" then return end

    local version = Game.localDB:getStringForKey("res_ver_"..gameid)
    if Assist.isEmpty(version) then
        if gameid == GAME_FRAME_ID then
            version = GAME_VERSION
        elseif SubgameConfig then
            version = SubgameConfig.version(gameid)
        end
        version = version or Platform.getAppVersion() or "1.00.00"
    end
    local opid = Sdk.getMarketId()
    local deviceId = Platform.getUdid()

    local url = string.format("%supdcheck.php?opid=%s&gameid=%s&platform=%s&version=%s&app=%s&udid=%s", 
                PHP_HOST, opid, gameid, device.platform, version, deviceId, checknumber(DEV_DEBUG))
    local urlRES = string.gsub(url, PHP_HOST, PHP_HOST_RES)

    local function _checkSucc_(recv)
        local t = recv
        if type(recv) == "string" then
            local startIdx = string.find(recv, "{")
            local endIdx = string.find(recv, "}")
            if not startIdx or not endIdx then
                callback()
                return
            end
            recv = string.sub(recv, startIdx, endIdx+1)
            recv = string.gsub(recv, "\\/", "/")
            t = json.decode(recv)
        end
        if type(t) == "table" and checknumber(t.status) > 0 then
            callback(t.version)
        else
            callback()
        end
    end

    local function _checkFail_()
        callback()
    end

    self.httpCom:httpGet(url, _checkSucc_, _checkFail_, urlRES)
end

-- 重载（热更新后）
function M:reload(ui)
    --local verCfg = self._verCfg or {}
    local isReStart = self._restart or (not GAME_VERSION) or GAME_VERSION < "2.00.00"

    ui = ui or self:getScene()
    ui:performWithDelay(function()
        if device.platform == "android" and isReStart then
            Platform.doReStartGame()
        else
            self:purgeAllCache()
            
            local updApp = self.updApp
            local updAppV = self.updAppV
            local marketId = Sdk.getMarketId()
            local sandbox = Sdk.getSandbox()
            local sdkId = Sdk.getSDKID()
            local sdkInit = Sdk.IS_INIT
            DEBUG_MARKET = marketId

            require_ex "GameInit"

            Sdk.setMarketId(marketId)
            Sdk.setSandbox(sandbox)
            Sdk.setSDKID(sdkId)
            Sdk.IS_INIT = sdkInit

            DEBUG_MARKET = ""

            require_ex "GameMonitor"
            Game:init()
            Game.updApp = updApp
            Game.updAppV = updAppV

            Game:gameStart(true)
        end
    end, 0.5)
end

---------------------------------------
-- 视图（场景）切换控制
function M:registerSceneEntry(idx, path)
    self._sceneEntry[idx] = path
end

--[[
进入场景
@param idx      number              场景索引
@param mix      string/function     返回场景后默认打开的界面/调用函数
@param theme    string              场景主题
]]
function M:enterScene(idx, mix, theme)
    Log.I("===Enter Scene: ", idx, tostring(self.sceneChanging), _TAG)

    if self.sceneChanging then return end
    self.sceneChanging = true

    -- 资源释放
    self:purgeUnused()

    -- 是否保留主界面
    local reserveMain = (idx >= ENUM.SCENCE.PLATFORM)
    local ignoreWait = (idx > ENUM.SCENCE.PLATFORM)
    self.uiManager:cleanAllLayer(reserveMain, ignoreWait)

    self:destroyNetBadUI()

    if self._scenceIdx > ENUM.SCENCE.LOGIN and idx == ENUM.SCENCE.LOGIN then
        self:resetMonitor()
    end
    self.theme = theme

    if self.hallUI and not self.hallUI:isVisible() then
        self:showCapture()
    end

    local currSceneIdx = self._scenceIdx
    self._scenceIdx = idx
    if currSceneIdx < ENUM.SCENCE.PLATFORM or idx ~= ENUM.SCENCE.PLATFORM then
        self:preloadSpine(idx)
        if idx ~= ENUM.SCENCE.PLATFORM then
            local pullSubGame = self:doPluginAPI("get", "pullSubGame")
            if pullSubGame then
                self.fieldId = pullSubGame.room_id
                self:doPluginAPI("set", "pullSubGame")
            end
        end
        -- 进入场景UI
        local layer = require_ex(self._sceneEntry[idx]).new(idx)
        self:addLayer(layer)

    elseif idx == ENUM.SCENCE.PLATFORM then
        if self.hallUI then
            self.hallUI.animateIn = true
            self.hallUI:toFront(true)
            self.uiManager:removeLoadingUI()
        end
        self:hideCapture()
    end

    -- 派发场景切换事件
    self:dispatchCustomEvent(GEvent("CHANGE_SCENE_EVENT"))

    -- 回调
    if type(mix) == "string" then
        self:addLayer(require_ex(mix):new())
    elseif type(mix) == "function" then
        mix()
    end

    -- 设置玩家进入过游戏
    if self._scenceIdx > ENUM.SCENCE.PLATFORM then
        Game:doPluginAPI("set", "setGameType", 1)
    end

    self:performDelay(function() 
        self.sceneChanging = nil 
        -- 确保心跳开启
        if reserveMain then
            self.connectHandler:startHeartBeat()
        end
    end, 0.3)
end

function M:getSceneIdx()
    return self._scenceIdx
end

function M:setSceneIdx(idx)
    self._scenceIdx = idx
end

function M:setScene(scene)
    self._scene = scene or display.getRunningScene()
end

function M:getScene()
    return self._scene or display.getRunningScene()
end

function M:resetMonitor()
    self:doPluginAPI("clear", "marquee")
end

-- 兼容旧版API
function M:getScenceIdx()
    return self._scenceIdx
end
function M:getScence()
    return self._scene or display.getRunningScene()
end

------------------------------------
-- 是否拉回游戏场景
function M:isAutoStart()
    return self._autoStart
end

function M:setAutoStart(autoStart)
    self._autoStart = autoStart
end

------------------------------------
-- 通用接口
--[[
打开GM命令界面
]]
function M:openGMView()
    if self.uiManager:getLayer("GmInputUI") then return end
    self:addLayer(require_ex("tool.gm.GmInputUI").new(), ENUM.UI_Z.TOP)
end

--[[
提示网络状态
]]
function M:showNetCloseTips()
    if self:doPluginAPI("check", "kicked") then return end

    local isNetBad = self.networkMgr:getNetBad()
    self:destroyNetBadUI()
    self:destroyWaitUI()
    if self.uiManager then
        self.uiManager:hideLoading()
    end

    local scene = self:getScene()
    if scene and scene.__action__ then
        return
    end

    if isNetBad then
        if self._scenceIdx >= ENUM.SCENCE.PLATFORM then
            self.networkMgr:setRecvData(false)
            showConfirmTip({
                sTip = Config.localize("srv_rsp_longtime"),
                fCallBack1 = function()
                    local isNetBad1 = self.networkMgr:getNetBad()
                    if isNetBad1 == true then
                        self.networkMgr:clearEnv()
                        self:closeNetWork()
                        scene.__action__ = scene:performWithDelay(function()
                            self:showLogoutTips()
                        end, 7)
                    end
                end,
                fCallBack2 = function()
                    self:doPluginAPI("login", "out")
                end,
                delay1 = 15,
                blankClose = false,
                sLayerName = "NetBad",
                fCheck2 = function()
                    return self.networkMgr:isRecvData()
                end,
            }, nil, ENUM.UI_Z.SYSTOP+10)
        else
            self:onLoginFail()
        end
    end
end

function M:showLogoutTips(tip)
    tip = tip or Config.localize("net_is_closed")
    self.networkMgr:setRecvData(false)
    showConfirmTip({sTip=tip, btn2Hide=true, sLayerName="NetBad", blankClose=false}, function()
        self:doPluginAPI("login", "out")
    end, ENUM.UI_Z.SYSTOP+20)
end

--[[
通用提示（等待）视图
]]
function M:getWaitLayer()
    return self._waitingLayer
end

function M:setWaitLayer(value)
    self._waitingLayer = value
end

--[[
遮罩提示（等待）对话框
@param tipsText     string      提示信息
@param ignoreTipNet boolean     忽略网络状态提示
@param callback     function    超时回调
@param spineRes     table       等待特效
@param timeout      number      等待时长
@param ignoreTouch  boolean     忽略点击（穿透）
]]
function M:showWaitUI(tipsText, ignoreTipNet, callback, spineRes, timeout, ignoreTouch)
    self:destroyWaitUI()
    self:destroyNetBadUI()

    local layer = require("ui.common.WaitUI").new(callback, ignoreTipNet, spineRes, timeout, ignoreTouch)
    if tipsText ~= nil then
        layer:setTipsText(tipsText)
    end
    self:addLayer(layer, ENUM.UI_Z.SYSTIP)
    self._waitingLayer = layer
end

function M:destroyWaitUI()
    if not Assist.isEmpty(self._waitingLayer) then
        self._waitingLayer:onClose()
        self._waitingLayer = nil
    end
end

function M:destroyNetBadUI()
    self.networkMgr:clearEnv()
end

------------------------------------
-- 通用提示
--[[
无交互文字提示对话框
@param tip          string      提示信息
@param dur          number      持续展示时长
@param cbExit       function    对话框退出回调(onExit)
@param cbFinish     function    对话框展示完成回调
@param delay        number      延时展示
]]
function M:tipMsg(tip, dur, cbExit, cbFinish, delay)
    dur = dur == nil and 2 or dur
    if type(tip) == "string" and string.len(tip) > 0 then
        local param = {
            content = tip,
            dur = dur,
            delay = delay,
            callback = cbExit,
            afterDestory = cbFinish
        }

        local layer = self.uiManager:getLayer("MsgTip")
        if not Assist.isEmpty(layer) then
            layer:onClose(param)
        end
        require("ui.common.MsgTip").new(param):addToScene(ENUM.UI_Z.SYSTOP, true)
    end
end

--[[
错误信息提示
从MsgConfig中获取对应错误码的提示信息
@param errCode      number      错误码
@param dur          number      持续展示时长
@param cbExit       function    对话框退出回调(onExit)
@param cbFinish     function    对话框展示完成回调
@param cbConfirm    function    二次确认回调
]]
function M:tipError(errCode, dur, cbExit, cbFinish, cbConfirm)
    errCode = tonumber(errCode)
    -- 经典场/弹头场(海魔来袭) 区分
    if errCode == ENUM.ERR_CODE.LIMIT_CANNON and self.tipEvent then
        errCode = ENUM.ERR_CODE.LIMIT_CANNON2
    end

    local cfgData = Config.getConfigValue(MsgConfig, errCode) or {}
    local tip = cfgData.text or tostring(errCode)
    local event = checknumber(cfgData.event)

    if event == ENUM.ERR_EVENT.RECHARGE then
        -- 充值提示
        showConfirmTip({sTip=tip, sBtnName1=Config.localize("chong_zhi")}, function()
            self:doPluginAPI("enter", "shop", ShopType.gold)
        end, ENUM.UI_Z.TOP)
    elseif event == ENUM.ERR_EVENT.SHOP then
        -- 跳转商城
        showConfirmTip({sTip=tip, sBtnName1=Config.localize("vip_goumai")}, function()
            self:doPluginAPI("storeCom", "openStoreView")
        end, ENUM.UI_Z.TOP)
    elseif event == ENUM.ERR_EVENT.CONFIRM then
        -- 确定弹窗
        showConfirmTip({sTip=tip, btn2Hide=true}, nil, ENUM.UI_Z.TOP)
    elseif event == ENUM.ERR_EVENT.WARNING then
        -- 二次确认（充值）
        showConfirmTip({sTip=tip, sBtnName1=Config.localize("title_continue"), fCallBack1=cbConfirm}, nil, ENUM.UI_Z.TOP)
    elseif event == ENUM.ERR_EVENT.BIND then
        -- 需要绑定手机
        self:doPluginAPI("enter", "binding")
    elseif event == ENUM.ERR_EVENT.RECH_QUICK then
        -- 快充
        self:doPluginAPI("recharge", "quick")
    elseif event == ENUM.ERR_EVENT.GOUP_GIFT and self.tipEvent then
        -- 直升礼包
        self.tipEvent = nil
        showConfirmTip({sTip=tip, btn2Hide=true}, function()
            self:doPluginAPI("enter", "goupGift")
        end, ENUM.UI_Z.TOP)
    elseif event == ENUM.ERR_EVENT.SHIPPING then
        -- 需要填写收货信息
        self:doPluginAPI("shipping", "info")
    elseif event == ENUM.ERR_EVENT.NOTICE then
        -- 更新维护
        self:doPluginAPI("notice", "update", true)
    elseif event == ENUM.ERR_EVENT.GLOBAL_TIP then
        -- 全局提示(只显示关闭，3秒可手动关闭，dur[15]秒自动关闭)
        showConfirmTip({
            sTip = tip,
            sBtnName1 = Config.localize("title_close"),
            delay1 = 3,
            delay1Disabled = true,
            fCallBack1 = cbExit,
            btn2Hide = true,
            delay2 = dur or 15,
        }, nil, ENUM.UI_Z.TIP)
    elseif event == ENUM.ERR_EVENT.GLOBAL_KICKOUT then
        -- 全局被踢出
        showConfirmTip({
            sTip = tip, 
            sBtnName1 = Config.localize("title_close"), 
            btn2Hide = true, 
            fCallBack1 = (cbConfirm or cbExit)
        }, nil, ENUM.UI_Z.SYSTOP)
    else
        -- 无事件普通提示
        self:tipMsg(tip, dur, cbExit , cbFinish)
    end
end

------------------------------------
-- 事件分发
function M:dispatchCustomEvent(eventName, eventData)
    if self.eventMgr and self.eventMgr:hasEvent(eventName) then
        self.eventMgr:dispatchEvent(eventName, eventData)
        return
    end
    local event = cc.EventCustom:new(eventName)
    if eventData then
        event.data = eventData
    end
    eventDispatcher:dispatchEvent(event)
end

function M:addEventListenerWithFixedPriority(eventName, callback, priority)
    if self.eventMgr then
        self.eventMgr:addEventListener(eventName, self, callback)
        return
    end
    return self:registCustomEventListener(eventName, callback, priority)
end

function M:addEventListenerWithSceneGraphPriority(node, eventName, callback)
    if self.eventMgr then
        self.eventMgr:addEventListener(eventName, node, callback)
        return
    end
    local listener = cc.EventListenerCustom:create(eventName, callback)
    local nEventDispatcher = node:getEventDispatcher()
    nEventDispatcher:addEventListenerWithSceneGraphPriority(listener, node)
    return listener
end

function M:removeEventListener(target, listeners)
    if self.eventMgr then
        self.eventMgr:removeEventByTarget(target)
        return
    end
    if listeners then
        local dispatcher = target:getEventDispatcher()
        for _, listener in pairs(listeners) do
            dispatcher:removeEventListener(listener)
        end
    end
end

function M:registCustomEventListener(eventName, handler, priority)
    local listener = cc.EventListenerCustom:create(eventName, handler)
    eventDispatcher:addEventListenerWithFixedPriority(listener, priority or 1)
    return listener
end

function M:registKeyboardEventListener(handler, priority)
    local listener = cc.EventListenerKeyboard:create()
    listener:registerScriptHandler(handler, cc.Handler.EVENT_KEYBOARD_RELEASED)
    eventDispatcher:addEventListenerWithFixedPriority(listener, priority or 1)
    return listener
end

function M:registAccelerationEventListener(layer, handler)
    layer:setAccelerometerEnabled(true)
    local listener = cc.EventListenerAcceleration:create(handler)
    eventDispatcher:addEventListenerWithSceneGraphPriority(listener, layer)
    return listener
end

--[[
全局监听（只调用一次）
]]
function M:addGlobalEvent()
    local function onKeyReleased(keyCode)
        if Game and Game._scenceIdx > 0 then
            if keyCode == cc.KeyCode.KEY_BACK or keyCode == cc.KeyCode.KEY_ESCAPE then
                if Game.uiManager and not Game.sceneChanging then
                    Game.uiManager:popTopView()
                end
            elseif keyCode == 35 and GM_DEBUG then
                Game:openGMView()
            end
        end
    end
    self:registKeyboardEventListener(onKeyReleased)

    local function onComeToForeground()
        if Game and Game.background then
            Game.background = nil
            Game.networkMgr:checkNetworkState()
            Log.I("Come To Foreground", _TAG)
            if not Game:doPluginAPI("check", "kicked") then
                Game:performDelay(function()
                    Game:onFore()
                    Game:resetMonitor()
                    if Game:getSceneIdx() == ENUM.SCENCE.PLATFORM then
                        Game:hideCapture()
                    end

                    Audio.resumeAllSounds()

                    if Game.eventMgr then
                        Game.eventMgr:dispatchEvent(cc.EVENT_COME_TO_FOREGROUND)
                    end
                end, 0.01, "GameToForeground")
            end
        end
    end
    self:registCustomEventListener(cc.EVENT_COME_TO_FOREGROUND, onComeToForeground)

    local function onComeToBackground()
        if Game and not Game.background then
            Game:unperformDelay("GameToForeground")
            Game.background = true
            Log.I("Come To Background", _TAG)
            Game:onBack()
            Audio.pauseAllSounds()
            if Game:getSceneIdx() >= ENUM.SCENCE.PLATFORM then
                Game:showCapture()
            end

            if Game.eventMgr then
                Game.eventMgr:dispatchEvent(cc.EVENT_COME_TO_BACKGROUND)
            end
        end
    end
    self:registCustomEventListener(cc.EVENT_COME_TO_BACKGROUND, onComeToBackground)

	-- win32 quit
    if device.platform == "windows" then
        local function onSimulatorQuit()
            if netCom then
                netCom.closeNetWork(true)
            end
            _crashEnd()
        end
        self:registCustomEventListener("simulator_quit", onSimulatorQuit)
    end
end

------------------------------------
--[[
添加UI视图，实现对UI的规范管理
@param layer        UIBase    UI视图对象
@param zOrder       number  层级
@param layerName    string  自定义名称
@param isCenter     boolean 居中
@param isRepeat     boolean 重复利用（不销毁）
@param unManage     boolean 不需要UIManager进行管理
]]
function M:addLayer(layer, zOrder, layerName, isCenter, isRepeat, unManage)
    local className = layerName or layer.__cname
    --local name = layer.__cname

    if self.uiManager and (not unManage) then
        self.uiManager:addLayer(className, layer, isRepeat)
    end

    if isCenter then
        local s = director:getWinSize()
        layer:setPosition(s.width/2, s.height/2)
    end

    zOrder = Number.max(layer:getLayerIndex(), zOrder or ENUM.UI_Z.UI)
    if not self._scene then
        self:setScene()
    end
    self._scene:addChild(layer, zOrder)
end

------------------------------------
-- API桥
-- getDB&getCom 兼容旧的API
function M:getDB(key)
    key = tostring(key)
    if string.sub(key, -2) == "DB" then
        return self[key]
    else
        return self[key.."DB"]
    end
end

function M:getCom(key)
    key = tostring(key)
    if string.sub(key, -3) == "Com" then
        return self[key]
    else
        return self[key.."Com"]
    end
end

function M:registerAPI(key, name, func)
    local api = string.format("%s_%s", key, name)
    self._pluginAPI[api] = func
end

function M:registerAPIList(list)
    if not list or #list == 0 then return end
    for _,v in ipairs(list) do
        self:registerAPI(v[1], v[2], v[3])
    end
end

--[[
执行插件(功能模块)API
@param key  string  注册关键字
@param name string  注册函数名
@param ...          不定长参数列表  
]]
function M:doPluginAPI(key, name, ...)
    if not key or not name then
        return
    end
    
    if key == "enter" and not self:funcIsOpen(name) then
        local limit_tip = FuncListKeyConfig[name] and FuncListKeyConfig[name].limit_tip
        if Assist.isEmpty(limit_tip) then
            limit_tip = Config.localize("coming_soon")
        end
        self:tipMsg(limit_tip, 2)
        return
    end

    local api = string.format("%s_%s", key, name)

    -- 通过映射表获取key, name
    if self._apiMap[api] then
        key, name = self._apiMap[api].key, self._apiMap[api].name
    end

    if self._pluginAPI[api] then
        return self._pluginAPI[api](...)
    end

    if key ~= "get" then
        local com_ = self:getCom(key)
        if com_ and com_[name] then
            return com_[name](com_, ...)
        end

        local db_ = self:getDB(key)
        if db_ and db_[name] then
            return db_[name](db_, ...)
        end
    end

    Log.W("API not found: ", api, _TAG)
end

--[[
执行特效API
@param effType  number  特效类型
@param ...              不定长参数列表  
]]
function M:doEffectAPI(effType, ...)
    if self.effManager then
        self.effManager:doEffectAPI(effType, ...)
    end
end

function M:doEffectList(effType, nodes, inv, delay, ...)
    if not Assist.isEmpty(nodes) and self.effManager then
        if type(nodes) ~= "table" and nodes.getChildren then
            nodes = nodes:getChildren()
        end
        if type(inv) ~= "number" then
            inv = 0.034
        end
        if type(delay) == "number" then
            for i, node in ipairs(nodes) do
                self.effManager:doEffectAPI(effType, node, delay+i*inv, ...)
            end
        else
            local args = {...}
            if delay == nil then
                for i, node in ipairs(nodes) do
                    node:performWithDelay(function()
                        self.effManager:doEffectAPI(effType, node, args[1], args[2], args[3], args[4], args[5])
                    end, i*inv)
                end
            else
                for i, node in ipairs(nodes) do
                    node:performWithDelay(function()
                        self.effManager:doEffectAPI(effType, node, delay, args[1], args[2], args[3], args[4], args[5])
                    end, i*inv)
                end
            end
        end
    end
end

------------------------------------
-- 通信桥
function M:registerParsePack(mixCmd, packKey)
    if not Assist.isEmpty(mixCmd) then
        netCom.registerParsePack(mixCmd, packKey)
    end
end

function M:unregisterParsePack(mixCmd)
    if not Assist.isEmpty(mixCmd) then
        netCom.registerParsePack(mixCmd, nil)
    end
end

function M:registerPushMsg(mixCmd, callback)
    if not Assist.isEmpty(mixCmd) then
        if type(mixCmd) == "table" then
            for _, v in ipairs(mixCmd) do
                netCom.registerCallBack(v[1], v[2], true)
            end
        else
            netCom.registerCallBack(mixCmd, callback, true)
        end
    end
end

function M:unregisterPushMsg(mixCmd)
    if not Assist.isEmpty(mixCmd) then
        if type(mixCmd) == "table" then
            if #mixCmd == 0 then
                for _, v in pairs(mixCmd) do
                    netCom.unRegisterCallBack(v[1])
                end
            else
                for _, v in ipairs(mixCmd) do
                    netCom.unRegisterCallBack(v)
                end
            end
        else
            netCom.unRegisterCallBack(mixCmd)
        end
    end
end

------------------------------------
-- 全局触摸限制
function M:lockTouch(duration)
    local scene = self:getScene()
    if scene then
        if not scene.__touchLayer__ then
            local touchLayer = require_ex("ui.common.TopTouchUI").new(true)
            scene:addChild(touchLayer, 9999)
            scene.__touchLayer__ = touchLayer
        else
            scene.__touchLayer__:stopAllActions()
        end
        if checknumber(duration) > 0 then
            scene.__touchLayer__:performWithDelay(function()
                if scene.__touchLayer__ then
                    scene.__touchLayer__:removeSelf()
                    scene.__touchLayer__ = nil
                end
            end, duration)
        end
    end
end

function M:unlockTouch()
    local scene = self:getScene()
    if scene and scene.__touchLayer__ then
        scene.__touchLayer__:removeSelf()
        scene.__touchLayer__ = nil
    end
end

------------------------------------
--[[
GM指令 (灰度测试)
某个输入框（如好友搜索）输入指令
]]
function M:checkGMCMD(msg)
    -- 仅对白名单设备开放
    if checknumber(DEV_DEBUG) == 0 then
        return false
    end

    local cmd = string.split(msg, " ")
    
    -- FPS
    if cmd[1] == "txfps" then
        if tonumber(cmd[2]) then
            director:setDisplayStats(checknumber(cmd[2]) == 1)
        end
        return true
    end

    -- 单元测试
    if cmd[1] == "tunit" then
        local unitTest = require_ex("util.unit_test").new()
        local func = "test"..cmd[2]
        if type(unitTest[func]) == "function" then
            unitTest[func](unitTest, cmd[3], cmd[4], cmd[5], cmd[6])
        end
        return true
    end

    return false
end

--[[
敏感词检测
@param text     string  需要检测的文本
@return boolean
]]
function M:checkBlock()
    if not self._blockStrs then
        self._blockStrs = {}
        local tmp = string.split(BlockTxt, ',')
        for i, v in ipairs(tmp) do
            local tmpV = string.trim(String.replaceMatch(v))
            if not Assist.isEmpty(tmpV) then
                self._blockStrs[i] = tmpV
            end
        end
    end
end

function M:checkSensitive(text)
    self:checkBlock()
    local tmpT = String.replaceMatch(text)
    for _, v in ipairs(self._blockStrs) do
        local i1, j1 = string.find(tmpT, v)
        local i2, j2 = string.find(text, v)
        if (i1 and j1) or (i2 and j2) then
            return true
        end
    end
    return false
end

function M:filterSensitive(text, rpt)
    self:checkBlock()
    rpt = rpt or "*"
    local tmpT = String.replaceMatch(text)
    local result, tmpR = false, false
    for _, v in ipairs(self._blockStrs) do
        local i1, j1 = string.find(tmpT, v)
        local i2, j2 = string.find(text, v)
        if (i1 and j1) or (i2 and j2) then
            result = true
            tmpT = string.gsub(tmpT, v, rpt)
        end
    end

    return result and tmpT or text
end

--[[
日志上报
]]
function M:reportInfo(data, TAG)
    dump(data, TAG or _TAG)
    self:dispatchCustomEvent("CMD_INFO_EVENT", data)
    if checknumber(data.count) > 2 then
        self:showLogoutTips()
    end
end

--[[
EditBox输入界面
]]
function M:showEditBox(params)
    if device.platform == "ios" then
        require_ex("ui.common.EditBoxUI").new(params):addToScene()
        return true
    end
end

------------------------------------
-- 全局单例
cc.exports.Game = M:new()
