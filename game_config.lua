--[[
全局配置
]]

------测试用配置（SDKID,平台,马甲,包名,刘海宽度,设备方向）------
DEBUG_SDKID = 0
DEBUG_MARKET = ""
DEBUG_APPNAME = "捕鱼圣手"
DEBUG_APP_PACKAGE = "com.mmcy.byjhz"
DEBUG_SIDEMARGIN = 0
DEBUG_LANDSCAPELEFT = true
-------------------------------------------------

-- 测试/开发 ([true 外测] - [false内测])
IS_TEST = false

-- 单机模式调试 (PC微信登录开启)
DEBUG_OFFLINE = false

-- GM调试
GM_DEBUG = (device.platform == "windows")
-- 渔场显示击杀数据
FISH_DEBUG = true
-- 显示鱼的碰撞区域
SHOW_FISH_FRAME = false
-- 显示渔场按钮
SHOW_FISH_RAPID = false
-- 碰撞检测方案
COLLISION_PHYSIC = (cc.PhysicsBody~=nil)
-- 低端机
LOW_MACHINE = (display.sizeInPixels.height<700 or AppName=="mgame")

-- 是否为开发模式 [正式包false,开发测试包true]
DEVELOP_MODE = false

-- 显示Cocos状态信息
CC_SHOW_FPS = false

--[[
日志过滤
LV: 5(all) 4(debug) 3(info) 2(warn) 1(error) 0(fatal)
TAG: 自定义标签
]]
LOG_FILTER_LV = 5
LOG_FILTER = {
    LV = LOG_FILTER_LV,
    TAG = ""
}
print = Log.P
dump = Log.T

-- 热更新相关 (框架ID,主游戏ID,主游戏funcKey,资源后缀)
GAME_FRAME_ID = 1000
GAME_MAIN_ID = 1018
GAME_MAIN_KEY = "fish"
GAME_RES_EXT = ".x"

-- APK静默下载
APK_SILENT_DOWN = false

-- 优先检测TP纹理集
CHECK_PLIST_TEX = true

-- 预设服务器HOST (开发,预发布,正式)
DOMAIN_DEV = "inner-server.fish.poker3a.com"
if IS_TEST or device.platform ~= "windows" then
    DOMAIN_DEV = "test-server.fish.poker3a.com"
end
DOMAIN_BUILD = "pre-server.fish.poker3a.com"
DOMAIN_RELEASE = "server.fish.poker3a.com"
DOMAIN_COPYRIGHT = "banshu-jh.x-men.co"
DOMAIN_REVIEW = "ts-svr.fish.mb1768.cn"

DOMAIN_NAME = DOMAIN_RELEASE

if DEVELOP_MODE or Platform.isTestPackage() then
    DEVELOP_MODE = true
    DOMAIN_NAME = DOMAIN_DEV
else
    if Platform.isBuildPackage() then
        DOMAIN_NAME = DOMAIN_BUILD
    elseif Platform.isCRPackage() then
        DOMAIN_NAME = DOMAIN_COPYRIGHT
    else
        -- 提审时使用提审服
        -- DOMAIN_NAME = DOMAIN_REVIEW
    end
end

-- 免校验token
CHEAT_TOKEN = nil
if DEVELOP_MODE or device.platform == "windows" or 
    (FuncListKeyConfig and FuncListKeyConfig["sdk"] and FuncListKeyConfig["sdk"].state == 0) then
    CHEAT_TOKEN = "46D6C2CF850EABEF76C371D792E6968D"
end

-- 其他预设值
LOGIN_HOST = "http://123.207.31.192:11001/"
WEB_PAGE_NAME = "http://static.mmcy808.com/gamepage/"
PHP_HOST = "http://"..DOMAIN_NAME..":8888/"
PHP_HOST_RES = "http://"..DOMAIN_NAME..":8888/"
CDN_HOST = "http://"..DOMAIN_NAME..":8888/upload/temp/"
CDN_HOST_RES = "http://"..DOMAIN_NAME..":8888/upload/temp/"
UPDNOTICE_PAGE = "http://www.mmcy818.cc/page/yxddz/game/notice.html"
GM_PAGE = "https://tb.53kf.com/code/client/10144804/1"
PROMO_PAGE = "http://by.mmcy808.com/"
SHARE_PAGE = "http://by.mmcy808.com/"
SHARE_IMG = ""
SERVER_STATE = ""
IDC_CHECK = ""
IDC_CHECK_IP = ""
-- 服务器信息（IP,端口,协议版本）
S_HOST = cc.LuaCHelper:theHelper():getHostIP(DOMAIN_NAME)
S_PORT = 7788
S_TCPV = 1.0

--[[
修改主服务器
其他预设值根据主服务器配置改变
]]
function ChangeServer(domain)
    DOMAIN_NAME = domain or DOMAIN_NAME
    
    local cfg = ServerListConfig and ServerListConfig[DOMAIN_NAME]
    if cfg then
        S_HOST = cc.LuaCHelper:theHelper():getHostIP(cfg.host_name)
        S_PORT = cfg.port
        S_TCPV = cfg.tcp_ver
        WEB_PAGE_NAME = cfg.web_host
        LOGIN_HOST = cfg.login_host
        PHP_HOST = cfg.php_host
        PHP_HOST_RES = cfg.php_host_RES
        CDN_HOST = cfg.zip_host
        CDN_HOST_RES = cfg.zip_host_RES
        UPDNOTICE_PAGE = cfg.updnotice_page
        PROMO_PAGE = cfg.promo_page
        SHARE_PAGE = cfg.share_page
        SHARE_IMG = cfg.share_image
        IDC_CHECK = cfg.idc_check
        IDC_CHECK_IP = cfg.idc_check_ip
        GM_DEBUG = cfg.gm_state == 1
        SERVER_STATE = cfg.server_state
    else
        S_HOST = cc.LuaCHelper:theHelper():getHostIP(DOMAIN_NAME)
    end

    Log.I("ChangeServer", DOMAIN_NAME, "SERVER")
    Log.I(S_HOST, S_PORT, S_TCPV, "SERVER")

    -- 正式服非白名单设备关闭日志,其他情况开启日志
    if checknumber(DEV_DEBUG) == 0 and DOMAIN_NAME == DOMAIN_RELEASE then
        print = NULL.F
        dump = NULL.F
        LOG_FILTER.LV = 0
    else
        print = Log.P
        dump = Log.T
        LOG_FILTER.LV = LOG_FILTER_LV or 5
    end
end

ChangeServer(DOMAIN_NAME)
