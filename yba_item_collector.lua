--!strict
--[[
    YBA Ultimate Collector & Merchant Auto-Seller (Xeno)
    Merchant dialogue: official Options only; Option1 -> Option1 -> Option6.
    One mouse click per selection; cleanup isolation and delayed damage monitoring.
    Movement, collection, UI and inventory configuration retained.
    Runtime behavior and server acceptance require verification in the game.
]]
--------------------------------------------------------------------------------
-- 1. СЕРВИСЫ
--------------------------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- 2. КОНФИГУРАЦИЯ И СТАТИСТИКА
--------------------------------------------------------------------------------
local VERSION = "collector-keygate-2026-10-26.27"
local sharedEnvironment = (typeof(getgenv) == "function" and getgenv()) or _G
local previousRuntime = sharedEnvironment.YBACollectorRuntime
if previousRuntime and typeof(previousRuntime.Stop) == "function" then pcall(previousRuntime.Stop) end
local runtime = {Running = true, Connections = {}, Cleanup = nil}
sharedEnvironment.YBACollectorRuntime = runtime
local function connectOwned(signal: RBXScriptSignal, callback: any): RBXScriptConnection
    local connection = signal:Connect(callback)
    table.insert(runtime.Connections, connection)
    return connection
end
local function tracebackError(err: any): string
    local message = tostring(err)
    local ok, trace = pcall(function() return debug.traceback(message, 2) end)
    return ok and trace or message
end
print("[YBA Debug] Version " .. VERSION)
local CONFIG = {
    Enabled = false,               -- Главный переключатель автофарма
    MoveMode = "Stealth Velocity", -- "Stealth Velocity" или "Instant Teleport"
    Speed = 40,                    -- Скорость полета (20 - 350 studs/s)
    Radius = 5000,                 -- Радиус поиска (по умолчанию 5000 - вся карта)
    NearbyRadius = 100,            -- Сначала очистить ближайшую группу предметов
    ScanDelay = 0.1,               -- Пауза при пустом поиске
    ArrivalTolerance = 3.5,        -- Допустимая погрешность прибытия
    AimCamera = true,              -- Поворачивать камеру только во время подбора
    MerchantCooldown = 3,         -- Кулдаун автопродажи в секундах при неудаче

    -- User-provided patrol order; no generated summit destinations.
    PatrolPoints = {
        Vector3.new(434.07568359375, 8.664657592773438, -284.1914367675781),
        Vector3.new(969.05419921875, 30.89854621887207, -121.26042175292969),
        Vector3.new(427.4265441894531, -33.48724365234375, 19.17989158630371),
        Vector3.new(125.23611450195312, 11.546395301818848, 383.9647521972656),
        Vector3.new(74.24984741210938, -33.48724365234375, 49.92197036743164),
        Vector3.new(-2.977844715118408, 39.04592514038086, -346.4732666015625),
        Vector3.new(14.228238105773926, -33.48724365234375, -620.3599853515625),
        Vector3.new(-400.194580078125, -42.48056411743164, -671.3759155273438),
        Vector3.new(-473.43975830078125, -25.204429626464844, -260.7947692871094),
        Vector3.new(-691.3316650390625, -22.669572830200195, -532.97802734375),
        Vector3.new(-660.8092041015625, -0.8479737043380737, -190.610107421875),
        Vector3.new(-296.2780456542969, -33.48724365234375, 38.523887634277344),
        Vector3.new(-24.535314559936523, -33.48724365234375, -198.28347778320312),
        Vector3.new(-635.9397583007812, -25.899749755859375, -756.3812866210938),
        Vector3.new(352.2597351074219, -29.55698585510254, -186.70521545410156),
        Vector3.new(192.8800048828125, -33.48724365234375, -316.76300048828125),
        Vector3.new(196.39694213867188, -26.244874954223633, -647.4442749023438),
    },

    -- Populated from the shared sellable-item catalog below.
    SellItems = {},
    Limits = {},
}

local Settings = {Folder = "YBACollector", Path = "YBACollector/settings.json", Data = {}, Ready = false,
    Reported = false, Revision = 0, Read = readfile, Write = writefile, MakeFolder = makefolder, IsFolder = isfolder, IsFile = isfile}
function Settings.report(message: string)
    if Settings.Reported then return end
    Settings.Reported = true
    warn("[YBA Settings] " .. message .. "; фарм продолжит работать")
end
function Settings.finite(value: any): boolean
    return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end
function Settings.threshold(value: any): number?
    if not Settings.finite(value) or value < 1 then return nil end
    return math.clamp(math.floor(value), 1, 10000)
end
function Settings.load()
    if typeof(Settings.Read) ~= "function" or typeof(Settings.Write) ~= "function" or typeof(Settings.MakeFolder) ~= "function" then
        Settings.report("Файловые API Xeno недоступны: сохранение выключено")
        return
    end
    local folderOk, folderError = pcall(function()
        if typeof(Settings.IsFolder) ~= "function" or not Settings.IsFolder(Settings.Folder) then Settings.MakeFolder(Settings.Folder) end
    end)
    if not folderOk then Settings.report("Не удалось создать папку: " .. tostring(folderError)); return end
    Settings.Ready = true
    local ok, data = pcall(function()
        if typeof(Settings.IsFile) == "function" and not Settings.IsFile(Settings.Path) then return nil end
        return HttpService:JSONDecode(Settings.Read(Settings.Path))
    end)
    if not ok then Settings.report("Не удалось прочитать JSON; используются значения по умолчанию"); return end
    if data == nil then return end
    if typeof(data) ~= "table" or data.Version ~= 1 then Settings.report("Формат настроек не поддерживается; используются значения по умолчанию"); return end
    Settings.Data = data
    if data.MoveMode == "Stealth Velocity" or data.MoveMode == "Instant Teleport" then CONFIG.MoveMode = data.MoveMode end
    if Settings.finite(data.Speed) then CONFIG.Speed = math.clamp(math.floor(data.Speed), 20, 350) end
    if Settings.finite(data.Radius) then CONFIG.Radius = math.clamp(math.floor(data.Radius), 50, 5000) end
    if Settings.finite(data.NearbyRadius) then CONFIG.NearbyRadius = math.clamp(math.floor(data.NearbyRadius), 10, 5000) end
    if typeof(data.AimCamera) == "boolean" then CONFIG.AimCamera = data.AimCamera end
    CONFIG.Enabled = false
    print("[YBA Settings] Loaded " .. Settings.Path .. "; auto farm starts disabled")
end
function Settings.applySale(name: string)
    if typeof(Settings.Data.SellItems) == "table" and typeof(Settings.Data.SellItems[name]) == "boolean" then
        CONFIG.SellItems[name] = Settings.Data.SellItems[name]
    end
    if typeof(Settings.Data.Limits) == "table" then
        local threshold = Settings.threshold(Settings.Data.Limits[name])
        if threshold then CONFIG.Limits[name] = threshold end
    end
end
function Settings.capture(): any
    local sellItems, limits = {}, {}
    -- Retain saved entries for dynamically discovered items absent from this session.
    for _, source in ipairs({Settings.Data.SellItems or {}, CONFIG.SellItems}) do
        if typeof(source) == "table" then
            for name, enabled in pairs(source) do
                if typeof(name) == "string" and typeof(enabled) == "boolean" and not string.find(string.lower(name), "lucky", 1, true) then sellItems[name] = enabled end
            end
        end
    end
    for _, source in ipairs({Settings.Data.Limits or {}, CONFIG.Limits}) do
        if typeof(source) == "table" then
            for name, value in pairs(source) do
                local threshold = Settings.threshold(value)
                if typeof(name) == "string" and threshold and not string.find(string.lower(name), "lucky", 1, true) then limits[name] = threshold end
            end
        end
    end
    local auth = Settings.Data.Auth
    local savedAuth = nil
    if typeof(auth) == "table" and typeof(auth.Key) == "string" and #auth.Key > 0 and #auth.Key <= 128
        and Settings.finite(auth.Revision) and auth.Revision >= 1 and auth.Revision == math.floor(auth.Revision) then
        savedAuth = {Key = auth.Key, Revision = auth.Revision}
    end
    return {Version = 1, Auth = savedAuth, MoveMode = CONFIG.MoveMode, Speed = CONFIG.Speed, Radius = CONFIG.Radius,
        NearbyRadius = CONFIG.NearbyRadius, AimCamera = CONFIG.AimCamera, SellItems = sellItems, Limits = limits}
end
function Settings.flush(): boolean
    if not Settings.Ready then return false end
    Settings.Revision += 1
    local ok, err = pcall(function()
        local data = Settings.capture()
        local result = Settings.Write(Settings.Path, HttpService:JSONEncode(data))
        if result == false then error("writefile returned false") end
        Settings.Data = data
    end)
    if not ok then Settings.Ready = false; Settings.report("Ошибка записи: " .. tostring(err)) end
    return ok
end
function Settings.requestSave()
    if not Settings.Ready then return end
    Settings.Revision += 1
    local revision = Settings.Revision
    task.delay(0.5, function()
        if runtime.Running and revision == Settings.Revision then Settings.flush() end
    end)
end
Settings.load()

-- Sample on demand, including during flights and transactions; never assume a fixed RTT.
local NetworkTiming = {LastSample = -math.huge, RTT = 0.2, Jitter = 0, Previous = nil,
    StableSince = nil, StepWait = 0.075, CorrectionAt = -math.huge, Corrections = 0,
    FallbackUntil = 0, RecoveryPending = false}
function NetworkTiming.seconds(): number
    if os.clock() - NetworkTiming.LastSample >= 0.1 then
        NetworkTiming.LastSample = os.clock()
        local ok, milliseconds = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and Settings.finite(milliseconds) and milliseconds >= 0 then
            local sample = math.clamp(milliseconds / 1000, 0.02, 5)
            local change = NetworkTiming.Previous and math.abs(sample - NetworkTiming.Previous) or 0
            NetworkTiming.Previous = sample
            NetworkTiming.Jitter = math.max(change, NetworkTiming.Jitter * 0.85)
            if sample <= 0.12 and NetworkTiming.Jitter <= 0.03 then
                NetworkTiming.StableSince = NetworkTiming.StableSince or os.clock()
            else
                NetworkTiming.StableSince = nil
            end
            -- React immediately to spikes; decay slowly when the connection improves.
            NetworkTiming.RTT = math.max(sample, NetworkTiming.RTT * 0.85)
        else
            NetworkTiming.RTT = math.max(NetworkTiming.RTT, 0.5)
            NetworkTiming.StableSince = nil
        end
    end
    return NetworkTiming.RTT
end
function NetworkTiming.speed(): number
    local rtt = NetworkTiming.seconds()
    return math.clamp(CONFIG.Speed, 20, 350) / math.max(1, (rtt + NetworkTiming.Jitter) / 0.15)
end
function NetworkTiming.stepDelay(distance: number): number
    local rtt = NetworkTiming.seconds()
    local stable = NetworkTiming.StableSince and os.clock() - NetworkTiming.StableSince >= 3
        and os.clock() - NetworkTiming.CorrectionAt >= 10
    local desired = math.max(stable and 0.05 or 0.075, distance / NetworkTiming.speed(), rtt * 0.5 + NetworkTiming.Jitter)
    -- Increase immediately; shorten gradually only after sustained stable samples.
    NetworkTiming.StepWait = math.max(desired, NetworkTiming.StepWait * 0.9)
    return NetworkTiming.StepWait
end
function NetworkTiming.corrected()
    local now = os.clock()
    NetworkTiming.Corrections = now - NetworkTiming.CorrectionAt <= 120 and NetworkTiming.Corrections + 1 or 1
    NetworkTiming.CorrectionAt, NetworkTiming.StableSince = now, nil
    local cooldown = NetworkTiming.Corrections >= 2 and 60 or 15
    NetworkTiming.FallbackUntil, NetworkTiming.RecoveryPending = now + cooldown, true
    warn(string.format("[YBA Movement] Position correction #%d; velocity fallback for %ds; RTT=%.3f jitter=%.3f",
        NetworkTiming.Corrections, cooldown, NetworkTiming.RTT, NetworkTiming.Jitter))
end

local Sales = {Order = {}, Aliases = {}, LastScan = -math.huge, Counts = {}, Unknown = {}, UnknownCount = 0, AddRow = nil}
-- Thresholds trigger a sale; they are not claims about the account's maximum capacity.
Sales.Catalog = {
    {"Mysterious Arrow", 25, {}},
    {"Rokakaka", 25, {"Rokakaka Fruit"}},
    {"Gold Coin", 25, {}}, {"Diamond", 25, {}},
    {"Quinton's Glove", 10, {"Quintons Glove"}},
    {"Pure Rokakaka", 10, {"Pure Rokakaka Fruit"}},
    {"Rib Cage of the Saint's Corpse", 10, {"Ribcage of the Saint's Corpse", "Rib Cage", "Ribcage"}},
    {"Ancient Scroll", 10, {}},
    {"Zepellin's Headband", 10, {"Zeppelin's Headband", "Zeppeli's Headband", "Zepelli's Headband"}},
    {"Zeppeli's Hat", 10, {"Zepelli's Hat", "Zeppelli's Hat", "Zeppelis Hat"}},
    {"Clackers", 10, {}}, {"Stone Mask", 10, {}}, {"Candy", 50, {}},
    {"Steel Ball", 10, {}}, {"Caesar's Headband", 10, {}}, {"Dio's Headband", 10, {"DEO's Headband"}},
    {"Dio's Diary", 10, {"DEO's Diary"}}, {"Green Baby", 10, {}},
    {"Heart of the Saint's Corpse", 10, {}}, {"Left Arm of the Saint's Corpse", 10, {}},
    {"Pelvis of the Saint's Corpse", 10, {}},
    {"Redeemed Mysterious Arrow", 25, {"Redeemed Stand Arrow"}},
    {"Redeemed Rokakaka", 25, {"Redeemed Rokakaka Fruit"}},
    {"Redeemed Pure Rokakaka", 10, {"Redeemed Pure Rokakaka Fruit"}},
    {"Redeemed Rib Cage of the Saint's Corpse", 10, {"Redeemed Ribcage of the Saint's Corpse"}},
    {"Redeemed Left Arm of the Saint's Corpse", 10, {}},
    {"Redeemed Heart of the Saint's Corpse", 10, {}}, {"Redeemed Pelvis of the Saint's Corpse", 10, {}},
    {"Comp MBR Money 1", 1, {}}, {"Comp MBR Money 2", 1, {}}, {"Comp MBR Money 3", 1, {}},
    {"Casual MBR Money 1", 1, {}}, {"Casual MBR Money 2", 1, {}}, {"Casual MBR Money 3", 1, {}},
}
function Sales.normalize(name: string): string
    local clean = name:gsub("%[%d+%]", ""):gsub("[’‘]", "'")
    return string.lower(clean):gsub("[^%w]", "")
end
function Sales.protected(name: string): boolean
    local normalized = Sales.normalize(name)
    return normalized == "standarrow" or normalized == "vampiremask"
        or string.find(normalized, "lucky", 1, true) ~= nil
end
function Sales.add(name: string, threshold: number, aliases: {string})
    if Sales.protected(name) or CONFIG.Limits[name] then return end
    table.insert(Sales.Order, name)
    CONFIG.SellItems[name], CONFIG.Limits[name] = true, threshold
    Settings.applySale(name)
    Sales.Aliases[Sales.normalize(name)] = name
    for _, alias in ipairs(aliases) do
        if not Sales.protected(alias) then Sales.Aliases[Sales.normalize(alias)] = name end
    end
    if Sales.AddRow then Sales.AddRow(name, CONFIG.Limits[name], #Sales.Order) end
end
for _, definition in ipairs(Sales.Catalog) do Sales.add(definition[1], definition[2], definition[3]) end
function Sales.resolve(tool: Instance): string?
    if not tool:IsA("Tool") or Sales.protected(tool.Name) then return nil end
    local identifiers = {tool.Name}
    for _, key in ipairs({"ItemName", "DisplayName", "ItemType"}) do
        local value = tool:GetAttribute(key)
        if typeof(value) == "string" then
            if Sales.protected(value) then return nil end
            table.insert(identifiers, value)
        end
    end
    if tool:GetAttribute("Sellable") == false or tool:GetAttribute("CanSell") == false then return nil end
    for _, name in ipairs(identifiers) do
        local canonical = Sales.Aliases[Sales.normalize(name)]
        if canonical then return canonical end
    end
    -- Unknown combat tools are not assumed sellable. Positive game metadata can opt an item in.
    if tool:GetAttribute("Sellable") == true or tool:GetAttribute("CanSell") == true then
        local threshold = tool:GetAttribute("StackLimit") or tool:GetAttribute("MaxStack")
        if typeof(threshold) ~= "number" or threshold < 1 then threshold = 10 end
        Sales.add(tool.Name, math.floor(threshold), {})
        return tool.Name
    end
    if not Sales.Unknown[tool.Name] and Sales.UnknownCount < 40 then
        Sales.Unknown[tool.Name] = true
        Sales.UnknownCount += 1
        print("[YBA Inventory] Unrecognized/non-sellable Tool=" .. tool.Name .. "; not sold without sellable metadata")
    end
    return nil
end
function Sales.quantity(tool: Instance): number
    local quantity = tool:GetAttribute("StackCount") or tool:GetAttribute("Quantity")
    if typeof(quantity) == "number" and quantity >= 1 and quantity == math.floor(quantity) then return quantity end
    return 1
end
function Sales.snapshot(): {[string]: number}
    if os.clock() - Sales.LastScan < 0.1 then return Sales.Counts end
    Sales.LastScan = os.clock()
    local counts = {}
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    for _, container in ipairs({backpack or false, localPlayer.Character or false}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                local name = Sales.resolve(tool)
                if name then counts[name] = (counts[name] or 0) + Sales.quantity(tool) end
            end
        end
    end
    Sales.Counts = counts
    return counts
end

local Farm = {State = "Search", UserRevision = 0, Items = {}, Dirty = {}, FolderConnections = {},
    Folder = nil, LastRefresh = -math.huge, LastPick = -math.huge, Best = nil, UnknownNames = {}, UnknownCount = 0,
    LastEnabled = false}
local STATS = {
    Collected = 0,
    SoldBatches = 0,
}

-- Черный список фантомных/забагованных предметов
local itemBlacklist: { [Instance]: boolean } = {}

-- Кулдаун повторной попытки продажи при неудаче (защита от циклической смерти)
local lastFailedSellTime = 0
local FAILED_SELL_COOLDOWN = CONFIG.MerchantCooldown or 15 -- Кулдаун при неудачном диалоге (защита от зацикливания)

-- Глобальные переменные NoClip и трекер коллизий
local isFlying = false

-- Хранилище исходной прозрачности персонажа
local originalTransparencies: { [Instance]: number } = {}

local function setCharacterClientInvisibility(character: Model, invisible: boolean)
    pcall(function()
        if invisible then
            table.clear(originalTransparencies)
            for _, desc in ipairs(character:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
                    originalTransparencies[desc] = desc.Transparency
                    desc.Transparency = 1
                elseif desc:IsA("Decal") then
                    originalTransparencies[desc] = desc.Transparency
                    desc.Transparency = 1
                end
            end
        else
            for part, trans in pairs(originalTransparencies) do
                if part and part.Parent then
                    if part:IsA("BasePart") or part:IsA("Decal") then
                        (part :: any).Transparency = trans
                    end
                end
            end
            table.clear(originalTransparencies)
        end
    end)
end

--------------------------------------------------------------------------------
-- 3. ЦВЕТОВАЯ ПАЛИТРА И ИКОНКИ
--------------------------------------------------------------------------------
local THEME = {
    Background = Color3.fromRGB(15, 17, 24),
    Header = Color3.fromRGB(20, 23, 34),
    CardBg = Color3.fromRGB(24, 28, 42),
    CardInner = Color3.fromRGB(30, 35, 52),
    Accent = Color3.fromRGB(99, 102, 241),
    AccentHover = Color3.fromRGB(129, 140, 248),
    Success = Color3.fromRGB(34, 197, 94),
    Warning = Color3.fromRGB(234, 179, 8),
    TextPrimary = Color3.fromRGB(248, 250, 252),
    TextSecondary = Color3.fromRGB(148, 163, 184),
    Border = Color3.fromRGB(38, 44, 66),
    TrackOff = Color3.fromRGB(45, 51, 74),
}

local ICONS = {
    Radar = "rbxassetid://10723415766",
    Power = "rbxassetid://10734923549",
    Speed = "rbxassetid://10747372167",
    Target = "rbxassetid://10709769841",
    Merchant = "rbxassetid://10734950309",
    Check = "rbxassetid://10709790644",
    Close = "rbxassetid://10747384394",
    Sparkle = "rbxassetid://10709819149",
}

--------------------------------------------------------------------------------
-- 4. СОЗДАНИЕ ГРАФИЧЕСКОГО ИНТЕРФЕЙСА (UI)
--------------------------------------------------------------------------------
local function getGuiContainer(): Instance
    local success, core = pcall(function()
        return CoreGui
    end)
    if success and core then
        return core
    end
    return localPlayer:WaitForChild("PlayerGui")
end

-- key.json was published and verified on the repository main branch.
-- Only JSON is fetched. A local key record never substitutes for a failed online check.
local Auth = {Url = "https://raw.githubusercontent.com/avov53/ItemsInThemap/main/key.json", SessionOnly = false}
function Auth.decodeBase64(text: string): string
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local buffer, bits, output = 0, 0, {}
    for character in text:gmatch(".") do
        if character == "=" then break end
        local index = alphabet:find(character, 1, true)
        if index then
            buffer = buffer * 64 + index - 1
            bits += 6
            if bits >= 8 then
                bits -= 8
                table.insert(output, string.char(math.floor(buffer / 2 ^ bits) % 256))
                buffer = buffer % 2 ^ bits
            end
        end
    end
    return table.concat(output)
end
function Auth.parse(body: any): any
    if typeof(body) ~= "string" or #body > 32768 then error("Invalid response size/type") end
    local document = HttpService:JSONDecode(body)
    -- HttpGet cannot set Accept: raw; handle the documented Contents API envelope too.
    if typeof(document) == "table" and document.encoding == "base64" and typeof(document.content) == "string" then
        document = HttpService:JSONDecode(Auth.decodeBase64(document.content))
    end
    if typeof(document) ~= "table" or document.schemaVersion ~= 1
        or not Settings.finite(document.revision) or document.revision < 1 or document.revision ~= math.floor(document.revision)
        or typeof(document.key) ~= "string" or #document.key == 0 or #document.key > 128
        or document.key:match("^%s*(.-)%s*$") ~= document.key then error("Unsupported key.json format") end
    return {Key = document.key, Revision = document.revision}
end
function Auth.fetch(): any
    local url = Auth.Url .. "?t=" .. tostring(os.time()) .. "&n=" .. HttpService:GenerateGUID(false)
    local requestFunction = request or http_request or (typeof(http) == "table" and http.request)
    local body
    if typeof(requestFunction) == "function" then
        local response = requestFunction({Url = url, Method = "GET", Headers = {
            ["Accept"] = "application/vnd.github.raw+json", ["Cache-Control"] = "no-cache", ["User-Agent"] = "YBACollector"}})
        if typeof(response) ~= "table" or typeof(response.StatusCode) ~= "number"
            or response.StatusCode < 200 or response.StatusCode >= 300 then
            error("GitHub HTTP " .. tostring(typeof(response) == "table" and response.StatusCode or "unavailable"))
        end
        body = response.Body
    else
        body = game:HttpGet(url)
    end
    return Auth.parse(body)
end
function Auth.savedMatches(remote: any): boolean
    local saved = Settings.Data.Auth
    return typeof(saved) == "table" and typeof(saved.Key) == "string" and saved.Key == remote.Key
        and Settings.finite(saved.Revision) and saved.Revision == remote.Revision
end
function Auth.run(): boolean
    local container = getGuiContainer()
    for _, name in ipairs({"YBA_Key_UI", "YBA_Final_UI"}) do
        local old = container:FindFirstChild(name)
        if old then old:Destroy() end
    end
    local gui = Instance.new("ScreenGui")
    gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "YBA_Key_UI", false, 1000
    gui.Parent = container
    local frame = Instance.new("Frame")
    frame.Size, frame.Position = UDim2.fromOffset(350, 242), UDim2.new(0.5, -175, 0.5, -121)
    frame.BackgroundColor3, frame.BorderSizePixel, frame.Parent = THEME.Background, 0, gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius, corner.Parent = UDim.new(0, 12), frame
    local title = Instance.new("TextLabel")
    title.Size, title.Position = UDim2.fromOffset(285, 30), UDim2.fromOffset(16, 12)
    title.BackgroundTransparency, title.Text, title.TextColor3 = 1, "YBA — Ключ доступа", THEME.TextPrimary
    title.Font, title.TextSize, title.Parent = Enum.Font.GothamBold, 16, frame
    local input = Instance.new("TextBox")
    input.Size, input.Position = UDim2.fromOffset(318, 38), UDim2.fromOffset(16, 62)
    input.Text, input.PlaceholderText, input.ClearTextOnFocus = "", "Введите ключ", false
    input.BackgroundColor3, input.TextColor3, input.TextSize, input.Parent = THEME.CardInner, THEME.TextPrimary, 16, frame
    input.Visible = false
    local function button(text: string, x: number, y: number, width: number): TextButton
        local object = Instance.new("TextButton")
        object.Size, object.Position = UDim2.fromOffset(width, 34), UDim2.fromOffset(x, y)
        object.Text, object.TextSize, object.TextColor3 = text, 13, THEME.TextPrimary
        object.BackgroundColor3, object.Parent = THEME.Accent, frame
        return object
    end
    local submit = button("Отправить", 16, 112, 152)
    local retry = button("Повторить проверку", 180, 112, 154)
    local close = button("×", 310, 12, 24)
    submit.Visible = false
    local message = Instance.new("TextLabel")
    message.Size, message.Position = UDim2.fromOffset(318, 70), UDim2.fromOffset(16, 158)
    message.BackgroundTransparency, message.TextWrapped, message.TextSize = 1, true, 12
    message.TextColor3, message.Text, message.Parent = THEME.TextSecondary, "Проверяем актуальный ключ на GitHub…", frame
    local signal = Instance.new("BindableEvent")
    local state = {Done = false, Allowed = false, Busy = false, Submitting = false, Generation = 0, Remote = nil, Worker = nil, Timer = nil}
    local connections = {}
    local function cancelTask(thread: any)
        if thread and thread ~= coroutine.running() then pcall(task.cancel, thread) end
    end
    local function finish(allowed: boolean)
        if state.Done then return end
        state.Done, state.Allowed, state.Busy = true, allowed and runtime.Running, false
        state.Generation += 1
        cancelTask(state.Worker); cancelTask(state.Timer)
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        gui:Destroy()
        signal:Fire()
    end
    runtime.AuthCancel = function() finish(false) end
    -- Stop exists even while startup is waiting for the key (including reruns).
    runtime.Stop = function()
        if not runtime.Running then return end
        runtime.Running, CONFIG.Enabled = false, false
        finish(false)
        for _, connection in ipairs(runtime.Connections) do pcall(function() connection:Disconnect() end) end
        table.clear(runtime.Connections)
        if runtime.RootGui then runtime.RootGui:Destroy() end
    end
    local function accept(remote: any)
        if state.Done or state.Submitting or not runtime.Running or state.Busy or state.Remote ~= remote then return end
        state.Submitting = true
        Settings.Data.Auth = {Key = remote.Key, Revision = remote.Revision}
        Auth.SessionOnly = not Settings.flush()
        if Auth.SessionOnly then warn("[YBA Auth] Ключ принят только на этот запуск; допуск не удалось сохранить") end
        finish(true)
    end
    local function fetchKey()
        if state.Done or state.Busy or not runtime.Running then return end
        state.Generation += 1
        local generation = state.Generation
        state.Busy, state.Remote = true, nil
        input.Visible, submit.Visible = false, false
        retry.Active, retry.AutoButtonColor = false, false
        message.Text, message.TextColor3 = "Проверяем актуальный ключ на GitHub…", THEME.TextSecondary
        state.Timer = task.delay(10, function()
            if state.Done or not runtime.Running or generation ~= state.Generation then return end
            state.Generation += 1
            state.Busy, state.Remote = false, nil
            cancelTask(state.Worker)
            retry.Active, retry.AutoButtonColor = true, true
            message.Text, message.TextColor3 = "GitHub не ответил за 10 секунд. Нажмите «Повторить проверку».", THEME.Warning
        end)
        state.Worker = task.spawn(function()
            local ok, remote = pcall(Auth.fetch)
            if state.Done or not runtime.Running or generation ~= state.Generation then return end
            cancelTask(state.Timer)
            state.Busy = false
            retry.Active, retry.AutoButtonColor = true, true
            if not ok then
                message.Text, message.TextColor3 = "Проверка GitHub недоступна. Нажмите «Повторить проверку».", THEME.Warning
                warn("[YBA Auth] Online check failed: " .. tostring(remote):sub(1, 220))
                return
            end
            state.Remote = remote
            if Auth.savedMatches(remote) then
                print("[YBA Auth] Saved access matches current online revision")
                accept(remote)
            else
                input.Visible, submit.Visible = true, true
                message.Text, message.TextColor3 = "Введите актуальный ключ и нажмите «Отправить».", THEME.TextSecondary
            end
        end)
    end
    local function submitKey()
        if state.Done or state.Busy or state.Submitting or not state.Remote then return end
        local entered = input.Text:match("^%s*(.-)%s*$")
        if entered ~= state.Remote.Key then
            message.Text, message.TextColor3 = "Неверный ключ. Проверьте регистр и попробуйте снова.", THEME.Warning
            return
        end
        accept(state.Remote)
    end
    table.insert(connections, submit.MouseButton1Click:Connect(submitKey))
    table.insert(connections, input.FocusLost:Connect(function(enterPressed) if enterPressed then submitKey() end end))
    table.insert(connections, retry.MouseButton1Click:Connect(fetchKey))
    table.insert(connections, close.MouseButton1Click:Connect(function() runtime.Stop() end))
    fetchKey()
    while not state.Done and runtime.Running do signal.Event:Wait() end
    local allowed = state.Done and state.Allowed and runtime.Running
    if not state.Done then finish(false) end
    runtime.AuthCancel = nil
    signal:Destroy()
    return allowed
end
if not Auth.run() then return end
CONFIG.Enabled = false

local oldGui = getGuiContainer():FindFirstChild("YBA_Final_UI")
if oldGui then
    oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "YBA_Final_UI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = getGuiContainer()
runtime.RootGui = screenGui

-- Главное окно
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 350, 0, 520)
mainFrame.Position = UDim2.new(0.5, -175, 0.5, -260)
mainFrame.BackgroundColor3 = THEME.Background
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 14)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Thickness = 1.2
mainStroke.Color = THEME.Border
mainStroke.Transparency = 0.1
mainStroke.Parent = mainFrame

-- Хедер
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = THEME.Header
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 14)
headerCorner.Parent = header

local headerCover = Instance.new("Frame")
headerCover.Size = UDim2.new(1, 0, 0, 12)
headerCover.Position = UDim2.new(0, 0, 1, -12)
headerCover.BackgroundColor3 = THEME.Header
headerCover.BorderSizePixel = 0
headerCover.Parent = header

local logoImg = Instance.new("ImageLabel")
logoImg.Size = UDim2.new(0, 20, 0, 20)
logoImg.Position = UDim2.new(0, 14, 0.5, -10)
logoImg.BackgroundTransparency = 1
logoImg.Image = ICONS.Radar
logoImg.ImageColor3 = THEME.Accent
logoImg.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "YBA Ultimate Collector"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextColor3 = THEME.TextPrimary
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Position = UDim2.new(0, 42, 0, 9)
titleLabel.Size = UDim2.new(0, 200, 0, 18)
titleLabel.BackgroundTransparency = 1
titleLabel.Parent = header

local subLabel = Instance.new("TextLabel")
subLabel.Text = "NoClip & Key Nav Auto-Seller"
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextSize = 11
subLabel.TextColor3 = THEME.TextSecondary
subLabel.TextXAlignment = Enum.TextXAlignment.Left
subLabel.Position = UDim2.new(0, 42, 0, 26)
subLabel.Size = UDim2.new(0, 200, 0, 16)
subLabel.BackgroundTransparency = 1
subLabel.Parent = header

local closeButton = Instance.new("ImageButton")
closeButton.Size = UDim2.new(0, 26, 0, 26)
closeButton.Position = UDim2.new(1, -36, 0.5, -13)
closeButton.BackgroundColor3 = THEME.CardBg
closeButton.BorderSizePixel = 0
closeButton.Image = ICONS.Close
closeButton.ImageColor3 = THEME.TextSecondary
closeButton.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

connectOwned(closeButton.MouseButton1Click, function()
    runtime.Stop()
end)

-- Drag & Drop
local isDragging = false
local dragStart = Vector2.zero
local startPos = UDim2.new()
local currentDragInput: InputObject? = nil

connectOwned(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        startPos = mainFrame.Position

        connectOwned(input.Changed, function()
            if input.UserInputState == Enum.UserInputState.End then
                isDragging = false
            end
        end)
    end
end)

connectOwned(header.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        currentDragInput = input
    end
end)

connectOwned(UserInputService.InputChanged, function(input)
    if isDragging and input == currentDragInput then
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        local target = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
        TweenService:Create(mainFrame, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
    end
end)

-- Скролл-контейнер
local scrollContent = Instance.new("ScrollingFrame")
scrollContent.Name = "ScrollContent"
scrollContent.Size = UDim2.new(1, -20, 1, -58)
scrollContent.Position = UDim2.new(0, 10, 0, 54)
scrollContent.BackgroundTransparency = 1
scrollContent.BorderSizePixel = 0
scrollContent.ScrollBarThickness = 3
scrollContent.ScrollBarImageColor3 = THEME.Border
scrollContent.CanvasSize = UDim2.new(0, 0, 0, 720)
scrollContent.Parent = mainFrame

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 8)
contentLayout.Parent = scrollContent

--------------------------------------------------------------------------------
-- ЭЛЕМЕНТЫ UI: TOGGLE, РЕЖИМ, СЛАЙДЕРЫ
--------------------------------------------------------------------------------
-- 1. Toggle автофарма
local farmToggleCard = Instance.new("Frame")
farmToggleCard.Size = UDim2.new(1, 0, 0, 84)
farmToggleCard.BackgroundColor3 = THEME.CardBg
farmToggleCard.BorderSizePixel = 0
farmToggleCard.LayoutOrder = 1
farmToggleCard.Parent = scrollContent

local farmCorner = Instance.new("UICorner")
farmCorner.CornerRadius = UDim.new(0, 10)
farmCorner.Parent = farmToggleCard

local farmIcon = Instance.new("ImageLabel")
farmIcon.Size = UDim2.new(0, 18, 0, 18)
farmIcon.Position = UDim2.new(0, 12, 0.5, -9)
farmIcon.BackgroundTransparency = 1
farmIcon.Image = ICONS.Power
farmIcon.ImageColor3 = THEME.Accent
farmIcon.Parent = farmToggleCard

local farmTitle = Instance.new("TextLabel")
farmTitle.Text = "Основной автофарм"
farmTitle.Font = Enum.Font.GothamMedium
farmTitle.TextSize = 13
farmTitle.TextColor3 = THEME.TextPrimary
farmTitle.TextXAlignment = Enum.TextXAlignment.Left
farmTitle.Position = UDim2.new(0, 38, 0, 10)
farmTitle.Size = UDim2.new(0, 170, 0, 16)
farmTitle.BackgroundTransparency = 1
farmTitle.Parent = farmToggleCard

local farmDesc = Instance.new("TextLabel")
farmDesc.Text = "Сбор лута + продажа торговцу"
farmDesc.Font = Enum.Font.Gotham
farmDesc.TextSize = 10
farmDesc.TextColor3 = THEME.TextSecondary
farmDesc.TextXAlignment = Enum.TextXAlignment.Left
farmDesc.Position = UDim2.new(0, 38, 0, 27)
farmDesc.Size = UDim2.new(0, 170, 0, 14)
farmDesc.BackgroundTransparency = 1
farmDesc.Parent = farmToggleCard

local farmSwitchBack = Instance.new("TextButton")
farmSwitchBack.Text = ""
farmSwitchBack.AutoButtonColor = false
farmSwitchBack.Size = UDim2.new(0, 44, 0, 22)
farmSwitchBack.Position = UDim2.new(1, -54, 0.5, -11)
farmSwitchBack.BackgroundColor3 = THEME.TrackOff
farmSwitchBack.BorderSizePixel = 0
farmSwitchBack.Parent = farmToggleCard

local farmSwitchCorner = Instance.new("UICorner")
farmSwitchCorner.CornerRadius = UDim.new(1, 0)
farmSwitchCorner.Parent = farmSwitchBack

local farmKnob = Instance.new("Frame")
farmKnob.Size = UDim2.new(0, 16, 0, 16)
farmKnob.Position = UDim2.new(0, 3, 0.5, -8)
farmKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
farmKnob.BorderSizePixel = 0
farmKnob.Parent = farmSwitchBack

local farmKnobCorner = Instance.new("UICorner")
farmKnobCorner.CornerRadius = UDim.new(1, 0)
farmKnobCorner.Parent = farmKnob

local aimCameraButton = Instance.new("TextButton")
aimCameraButton.Size = UDim2.new(1, -24, 0, 24)
aimCameraButton.Position = UDim2.fromOffset(12, 54)
aimCameraButton.BackgroundColor3 = THEME.CardInner
aimCameraButton.TextColor3 = THEME.TextPrimary
aimCameraButton.TextSize = 11
aimCameraButton.Text = "Камера при подборе: " .. (CONFIG.AimCamera and "ВКЛ" or "ВЫКЛ")
aimCameraButton.Parent = farmToggleCard
connectOwned(aimCameraButton.MouseButton1Click, function()
    CONFIG.AimCamera = not CONFIG.AimCamera
    aimCameraButton.Text = "Камера при подборе: " .. (CONFIG.AimCamera and "ВКЛ" or "ВЫКЛ")
    Settings.requestSave()
end)

-- 2. Селектор режима перемещения
local modeCard = Instance.new("Frame")
modeCard.Size = UDim2.new(1, 0, 0, 54)
modeCard.BackgroundColor3 = THEME.CardBg
modeCard.BorderSizePixel = 0
modeCard.LayoutOrder = 2
modeCard.Parent = scrollContent

local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = UDim.new(0, 10)
modeCorner.Parent = modeCard

local modeTitle = Instance.new("TextLabel")
modeTitle.Text = "Режим перемещения"
modeTitle.Font = Enum.Font.GothamMedium
modeTitle.TextSize = 12
modeTitle.TextColor3 = THEME.TextPrimary
modeTitle.TextXAlignment = Enum.TextXAlignment.Left
modeTitle.Position = UDim2.new(0, 14, 0, 8)
modeTitle.Size = UDim2.new(0, 150, 0, 14)
modeTitle.BackgroundTransparency = 1
modeTitle.Parent = modeCard

local modeBtn = Instance.new("TextButton")
modeBtn.Text = CONFIG.MoveMode
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 11
modeBtn.TextColor3 = (CONFIG.MoveMode == "Instant Teleport") and THEME.Warning or THEME.TextPrimary
modeBtn.BackgroundColor3 = THEME.CardInner
modeBtn.BorderSizePixel = 0
modeBtn.Size = UDim2.new(1, -28, 0, 24)
modeBtn.Position = UDim2.new(0, 14, 0, 24)
modeBtn.Parent = modeCard

local modeBtnCorner = Instance.new("UICorner")
modeBtnCorner.CornerRadius = UDim.new(0, 6)
modeBtnCorner.Parent = modeBtn

local modeBtnStroke = Instance.new("UIStroke")
modeBtnStroke.Color = THEME.Border
modeBtnStroke.Thickness = 1
modeBtnStroke.Parent = modeBtn

connectOwned(modeBtn.MouseButton1Click, function()
    if CONFIG.MoveMode == "Stealth Velocity" then
        CONFIG.MoveMode = "Instant Teleport"
        modeBtn.TextColor3 = THEME.Warning
    else
        CONFIG.MoveMode = "Stealth Velocity"
        modeBtn.TextColor3 = THEME.TextPrimary
    end
    modeBtn.Text = CONFIG.MoveMode
    Settings.requestSave()
end)

-- 3. Слайдер скорости (20 - 350)
local speedCard = Instance.new("Frame")
speedCard.Size = UDim2.new(1, 0, 0, 60)
speedCard.BackgroundColor3 = THEME.CardBg
speedCard.BorderSizePixel = 0
speedCard.LayoutOrder = 3
speedCard.Parent = scrollContent

local speedCorner = Instance.new("UICorner")
speedCorner.CornerRadius = UDim.new(0, 10)
speedCorner.Parent = speedCard

local speedTitle = Instance.new("TextLabel")
speedTitle.Text = "Скорость движения"
speedTitle.Font = Enum.Font.GothamMedium
speedTitle.TextSize = 12
speedTitle.TextColor3 = THEME.TextPrimary
speedTitle.TextXAlignment = Enum.TextXAlignment.Left
speedTitle.Position = UDim2.new(0, 14, 0, 10)
speedTitle.Size = UDim2.new(0, 160, 0, 14)
speedTitle.BackgroundTransparency = 1
speedTitle.Parent = speedCard

local speedIndicator = Instance.new("TextLabel")
speedIndicator.Text = tostring(CONFIG.Speed) .. " studs/s"
speedIndicator.Font = Enum.Font.GothamBold
speedIndicator.TextSize = 11
speedIndicator.TextColor3 = THEME.Accent
speedIndicator.TextXAlignment = Enum.TextXAlignment.Right
speedIndicator.Position = UDim2.new(1, -90, 0, 10)
speedIndicator.Size = UDim2.new(0, 76, 0, 14)
speedIndicator.BackgroundTransparency = 1
speedIndicator.Parent = speedCard

local speedTrack = Instance.new("Frame")
speedTrack.Size = UDim2.new(1, -28, 0, 6)
speedTrack.Position = UDim2.new(0, 14, 0, 38)
speedTrack.BackgroundColor3 = THEME.Border
speedTrack.BorderSizePixel = 0
speedTrack.Parent = speedCard

local speedTrackCorner = Instance.new("UICorner")
speedTrackCorner.CornerRadius = UDim.new(1, 0)
speedTrackCorner.Parent = speedTrack

local speedFill = Instance.new("Frame")
local defSpeedRatio = math.clamp((CONFIG.Speed - 20) / (350 - 20), 0, 1)
speedFill.Size = UDim2.new(defSpeedRatio, 0, 1, 0)
speedFill.BackgroundColor3 = THEME.Accent
speedFill.BorderSizePixel = 0
speedFill.Parent = speedTrack

local speedFillCorner = Instance.new("UICorner")
speedFillCorner.CornerRadius = UDim.new(1, 0)
speedFillCorner.Parent = speedFill

local speedTrigger = Instance.new("TextButton")
speedTrigger.Text = ""
speedTrigger.BackgroundTransparency = 1
speedTrigger.Size = UDim2.new(1, 0, 1, 20)
speedTrigger.Position = UDim2.new(0, 0, 0, -10)
speedTrigger.Parent = speedTrack

-- 4. Слайдер радиуса (50 - 5000)
local radiusCard = Instance.new("Frame")
radiusCard.Size = UDim2.new(1, 0, 0, 60)
radiusCard.BackgroundColor3 = THEME.CardBg
radiusCard.BorderSizePixel = 0
radiusCard.LayoutOrder = 4
radiusCard.Parent = scrollContent

local radiusCorner = Instance.new("UICorner")
radiusCorner.CornerRadius = UDim.new(0, 10)
radiusCorner.Parent = radiusCard

local radiusTitle = Instance.new("TextLabel")
radiusTitle.Text = "Радиус поиска"
radiusTitle.Font = Enum.Font.GothamMedium
radiusTitle.TextSize = 12
radiusTitle.TextColor3 = THEME.TextPrimary
radiusTitle.TextXAlignment = Enum.TextXAlignment.Left
radiusTitle.Position = UDim2.new(0, 14, 0, 10)
radiusTitle.Size = UDim2.new(0, 160, 0, 14)
radiusTitle.BackgroundTransparency = 1
radiusTitle.Parent = radiusCard

local radiusIndicator = Instance.new("TextLabel")
radiusIndicator.Text = tostring(CONFIG.Radius) .. " studs"
radiusIndicator.Font = Enum.Font.GothamBold
radiusIndicator.TextSize = 11
radiusIndicator.TextColor3 = THEME.Accent
radiusIndicator.TextXAlignment = Enum.TextXAlignment.Right
radiusIndicator.Position = UDim2.new(1, -90, 0, 10)
radiusIndicator.Size = UDim2.new(0, 76, 0, 14)
radiusIndicator.BackgroundTransparency = 1
radiusIndicator.Parent = radiusCard

local radiusTrack = Instance.new("Frame")
radiusTrack.Size = UDim2.new(1, -28, 0, 6)
radiusTrack.Position = UDim2.new(0, 14, 0, 38)
radiusTrack.BackgroundColor3 = THEME.Border
radiusTrack.BorderSizePixel = 0
radiusTrack.Parent = radiusCard

local radiusTrackCorner = Instance.new("UICorner")
radiusTrackCorner.CornerRadius = UDim.new(1, 0)
radiusTrackCorner.Parent = radiusTrack

local radiusFill = Instance.new("Frame")
local defRadRatio = math.clamp((CONFIG.Radius - 50) / (5000 - 50), 0, 1)
radiusFill.Size = UDim2.new(defRadRatio, 0, 1, 0)
radiusFill.BackgroundColor3 = THEME.Accent
radiusFill.BorderSizePixel = 0
radiusFill.Parent = radiusTrack

local radiusFillCorner = Instance.new("UICorner")
radiusFillCorner.CornerRadius = UDim.new(1, 0)
radiusFillCorner.Parent = radiusFill

local radiusTrigger = Instance.new("TextButton")
radiusTrigger.Text = ""
radiusTrigger.BackgroundTransparency = 1
radiusTrigger.Size = UDim2.new(1, 0, 1, 20)
radiusTrigger.Position = UDim2.new(0, 0, 0, -10)
radiusTrigger.Parent = radiusTrack

--------------------------------------------------------------------------------
-- 5. СЕКЦИЯ: РАСШИРЕННЫЙ СПИСОК ПРЕДМЕТОВ ПРОДАЖИ (SHIFTPLOX)
--------------------------------------------------------------------------------
local merchCard = Instance.new("Frame")
merchCard.Size = UDim2.new(1, 0, 0, 310)
merchCard.BackgroundColor3 = THEME.CardBg
merchCard.BorderSizePixel = 0
merchCard.LayoutOrder = 5
merchCard.Parent = scrollContent

local merchCorner = Instance.new("UICorner")
merchCorner.CornerRadius = UDim.new(0, 10)
merchCorner.Parent = merchCard

local merchHeader = Instance.new("Frame")
merchHeader.Size = UDim2.new(1, 0, 0, 40)
merchHeader.BackgroundTransparency = 1
merchHeader.Parent = merchCard

local merchIcon = Instance.new("ImageLabel")
merchIcon.Size = UDim2.new(0, 18, 0, 18)
merchIcon.Position = UDim2.new(0, 12, 0.5, -9)
merchIcon.BackgroundTransparency = 1
merchIcon.Image = ICONS.Merchant
merchIcon.ImageColor3 = THEME.Warning
merchIcon.Parent = merchHeader

local merchTitle = Instance.new("TextLabel")
merchTitle.Text = "Лимиты автопродажи (ShiftPlox)"
merchTitle.Font = Enum.Font.GothamMedium
merchTitle.TextSize = 13
merchTitle.TextColor3 = THEME.TextPrimary
merchTitle.TextXAlignment = Enum.TextXAlignment.Left
merchTitle.Position = UDim2.new(0, 38, 0, 8)
merchTitle.Size = UDim2.new(0, 200, 0, 16)
merchTitle.BackgroundTransparency = 1
merchTitle.Parent = merchHeader

local merchDesc = Instance.new("TextLabel")
merchDesc.Text = "Продажа при достижении лимита"
merchDesc.Font = Enum.Font.Gotham
merchDesc.TextSize = 10
merchDesc.TextColor3 = THEME.TextSecondary
merchDesc.TextXAlignment = Enum.TextXAlignment.Left
merchDesc.Position = UDim2.new(0, 38, 0, 24)
merchDesc.Size = UDim2.new(0, 200, 0, 14)
merchDesc.BackgroundTransparency = 1
merchDesc.Parent = merchHeader

local checkListScroll = Instance.new("ScrollingFrame")
checkListScroll.Size = UDim2.new(1, -20, 0, 255)
checkListScroll.Position = UDim2.new(0, 10, 0, 44)
checkListScroll.BackgroundColor3 = THEME.CardInner
checkListScroll.BorderSizePixel = 0
checkListScroll.ScrollBarThickness = 3
checkListScroll.ScrollBarImageColor3 = THEME.Border
checkListScroll.CanvasSize = UDim2.new(0, 0, 0, 480)
checkListScroll.Parent = merchCard

local checkListCorner = Instance.new("UICorner")
checkListCorner.CornerRadius = UDim.new(0, 8)
checkListCorner.Parent = checkListScroll

local checkListLayout = Instance.new("UIListLayout")
checkListLayout.SortOrder = Enum.SortOrder.LayoutOrder
checkListLayout.Padding = UDim.new(0, 2)
checkListLayout.Parent = checkListScroll

local function createItemCheckRow(itemName: string, limitVal: number, order: number)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, 34)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = checkListScroll

    local boxBtn = Instance.new("TextButton")
    boxBtn.Text = ""
    boxBtn.AutoButtonColor = false
    boxBtn.Size = UDim2.new(0, 18, 0, 18)
    boxBtn.Position = UDim2.new(0, 10, 0.5, -9)
    boxBtn.BackgroundColor3 = CONFIG.SellItems[itemName] and THEME.Accent or THEME.Border
    boxBtn.BorderSizePixel = 0
    boxBtn.Parent = row

    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 4)
    boxCorner.Parent = boxBtn

    local checkIcon = Instance.new("ImageLabel")
    checkIcon.Size = UDim2.new(0, 14, 0, 14)
    checkIcon.Position = UDim2.new(0.5, -7, 0.5, -7)
    checkIcon.BackgroundTransparency = 1
    checkIcon.Image = ICONS.Check
    checkIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    checkIcon.Visible = CONFIG.SellItems[itemName]
    checkIcon.Parent = boxBtn

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Text = itemName
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 11
    nameLabel.TextColor3 = THEME.TextPrimary
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Position = UDim2.new(0, 36, 0, 0)
    nameLabel.Size = UDim2.new(0, 160, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Parent = row

    local limitLabel = Instance.new("TextLabel")
    limitLabel.Text = "Порог: " .. tostring(limitVal)
    limitLabel.Font = Enum.Font.Gotham
    limitLabel.TextSize = 10
    limitLabel.TextColor3 = THEME.TextSecondary
    limitLabel.TextXAlignment = Enum.TextXAlignment.Right
    limitLabel.Position = UDim2.new(1, -80, 0, 0)
    limitLabel.Size = UDim2.new(0, 70, 1, 0)
    limitLabel.BackgroundTransparency = 1
    limitLabel.Parent = row

    connectOwned(boxBtn.MouseButton1Click, function()
        CONFIG.SellItems[itemName] = not CONFIG.SellItems[itemName]
        local isEnabled = CONFIG.SellItems[itemName]
        Settings.requestSave()
        checkIcon.Visible = isEnabled
        TweenService:Create(boxBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = isEnabled and THEME.Accent or THEME.Border
        }):Play()
    end)
end

-- Shared catalog drives the UI and inventory matching, including aliases.
Sales.AddRow = function(itemName: string, threshold: number, order: number)
    createItemCheckRow(itemName, threshold, order)
    checkListScroll.CanvasSize = UDim2.fromOffset(0, #Sales.Order * 36)
end
for order, itemName in ipairs(Sales.Order) do Sales.AddRow(itemName, CONFIG.Limits[itemName], order) end

-- 6. Статус и индикаторы
local statusCard = Instance.new("Frame")
statusCard.Size = UDim2.new(1, 0, 0, 70)
statusCard.BackgroundColor3 = THEME.CardBg
statusCard.BorderSizePixel = 0
statusCard.LayoutOrder = 6
statusCard.Parent = scrollContent

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 10)
statusCorner.Parent = statusCard

local statusIcon = Instance.new("ImageLabel")
statusIcon.Size = UDim2.new(0, 18, 0, 18)
statusIcon.Position = UDim2.new(0, 12, 0.18, 0)
statusIcon.BackgroundTransparency = 1
statusIcon.Image = ICONS.Sparkle
statusIcon.ImageColor3 = THEME.Accent
statusIcon.Parent = statusCard

local statusLabel = Instance.new("TextLabel")
statusLabel.Text = "Статус: Ожидание запуска"
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 12
statusLabel.TextColor3 = THEME.TextSecondary
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Position = UDim2.new(0, 38, 0, 14)
statusLabel.Size = UDim2.new(1, -50, 0, 16)
statusLabel.BackgroundTransparency = 1
statusLabel.Parent = statusCard
if Auth.SessionOnly then statusLabel.Text = "Ключ принят; допуск не сохранён на следующий запуск" end

local statsSubLabel = Instance.new("TextLabel")
statsSubLabel.Text = "Собрано: 0 | Продано партий: 0"
statsSubLabel.Font = Enum.Font.Gotham
statsSubLabel.TextSize = 11
statsSubLabel.TextColor3 = THEME.TextSecondary
statsSubLabel.TextXAlignment = Enum.TextXAlignment.Left
statsSubLabel.Position = UDim2.new(0, 38, 0, 36)
statsSubLabel.Size = UDim2.new(1, -50, 0, 16)
statsSubLabel.BackgroundTransparency = 1
statsSubLabel.Parent = statusCard

--------------------------------------------------------------------------------
-- 6. УПРАВЛЕНИЕ UI И СЛАЙДЕРЫ
--------------------------------------------------------------------------------
local function setFarmToggle(active: boolean)
    local targetPos = active and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    local targetBg = active and THEME.Success or THEME.TrackOff

    TweenService:Create(farmKnob, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = targetPos }):Play()
    TweenService:Create(farmSwitchBack, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { BackgroundColor3 = targetBg }):Play()
end

local function restoreCollisions()
    isFlying = false

    local char = localPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                -- КРИТИЧЕСКИ ВАЖНО: Никогда не включать CanCollide для HumanoidRootPart в R15!
                -- Это вызывает физический разрыв RootJoint суставов и смерть персонажа (Replace lowerTorso with new)
                if part.Name ~= "HumanoidRootPart" then
                    if part.Name == "UpperTorso" or part.Name == "LowerTorso" or part.Name == "Head" or part.Name == "Torso" then
                        part.CanCollide = true
                    else
                        part.CanCollide = false
                    end
                else
                    part.CanCollide = false
                end
            end
        end
    end
end

connectOwned(farmSwitchBack.MouseButton1Click, function()
    Farm.UserRevision += 1
    print("[YBA Farm] User toggle=" .. tostring(not CONFIG.Enabled) .. " revision=" .. Farm.UserRevision)
    CONFIG.Enabled = not CONFIG.Enabled
    setFarmToggle(CONFIG.Enabled)
    if not CONFIG.Enabled then
        statusLabel.Text = "Статус: Отключен"
        statusLabel.TextColor3 = THEME.TextSecondary
        restoreCollisions()
    end
end)

-- Слайдер скорости
local isSpeedMoving = false
local function handleSpeed(frac: number)
    frac = math.clamp(frac, 0, 1)
    TweenService:Create(speedFill, TweenInfo.new(0.04), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
    local val = math.floor(20 + frac * (350 - 20))
    CONFIG.Speed = val
    speedIndicator.Text = tostring(val) .. " studs/s"
    Settings.requestSave()
end

connectOwned(speedTrigger.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isSpeedMoving = true
        handleSpeed((input.Position.X - speedTrack.AbsolutePosition.X) / speedTrack.AbsoluteSize.X)
    end
end)

-- Слайдер радиуса
local isRadiusMoving = false
local function handleRadius(frac: number)
    frac = math.clamp(frac, 0, 1)
    TweenService:Create(radiusFill, TweenInfo.new(0.04), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
    local val = math.floor(50 + frac * (5000 - 50))
    CONFIG.Radius = val
    radiusIndicator.Text = tostring(val) .. " studs"
    Settings.requestSave()
end

connectOwned(radiusTrigger.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isRadiusMoving = true
        handleRadius((input.Position.X - radiusTrack.AbsolutePosition.X) / radiusTrack.AbsoluteSize.X)
    end
end)

connectOwned(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isSpeedMoving = false
        isRadiusMoving = false
    end
end)

connectOwned(UserInputService.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        if isSpeedMoving then
            handleSpeed((input.Position.X - speedTrack.AbsolutePosition.X) / speedTrack.AbsoluteSize.X)
        elseif isRadiusMoving then
            handleRadius((input.Position.X - radiusTrack.AbsolutePosition.X) / radiusTrack.AbsoluteSize.X)
        end
    end
end)

local diagnostic = {Mode = "Full", Failed = false, Waiting = false, SellRequested = false}
local diagnosticCard = Instance.new("Frame")
diagnosticCard.Name = "MerchantDiagnostics"
diagnosticCard.Size = UDim2.new(1, 0, 0, 194)
diagnosticCard.BackgroundColor3 = THEME.CardBg
diagnosticCard.LayoutOrder = 7
diagnosticCard.Parent = scrollContent
local diagnosticLabel = Instance.new("TextLabel")
diagnosticLabel.Size = UDim2.new(1, -16, 0, 46)
diagnosticLabel.Position = UDim2.fromOffset(8, 4)
diagnosticLabel.BackgroundTransparency = 1
diagnosticLabel.TextColor3 = THEME.TextPrimary
diagnosticLabel.TextSize = 11
diagnosticLabel.TextWrapped = true
diagnosticLabel.Text = "Полная автопродажа без настройки координат. Выберите режим, закройте F9 и включите автофарм."
diagnosticLabel.Parent = diagnosticCard
local function merchantModeButton(text: string, x: number, y: number, width: number, color: Color3): TextButton
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(width, -12, 0, 38)
    button.Position = UDim2.new(x, 8, 0, y)
    button.Text = text
    button.TextSize = 11
    button.TextWrapped = true
    button.BackgroundColor3 = color
    button.Parent = diagnosticCard
    return button
end
local fullSaleButton = merchantModeButton("Полная автопродажа", 0, 56, 0.5, THEME.Success)
local firstClickButton = merchantModeButton("Проверка первого клика", 0.5, 56, 0.5, THEME.Accent)
local compareInputButton = merchantModeButton("Сравнить ввод (диагностика)", 0, 102, 1, THEME.Accent)
local stopSaleButton = merchantModeButton("Остановить попытку", 0, 146, 1, THEME.Warning)
local function selectMerchantMode(mode: string)
    if CONFIG.Enabled then
        diagnosticLabel.Text = "Сначала выключите автофарм, затем выберите режим продажи."
        return
    end
    if runtime.MerchantHold then runtime.MerchantHold.ComparisonPause = false end
    if mode == "Compare" then runtime.InputComparisonDone = false end
    diagnostic.Mode = mode
    diagnostic.SellRequested = mode == "Full"
    diagnosticLabel.Text = mode == "Compare"
        and "Диагностика: программный клик, при неудаче — один ручной по подсказке. Затем пауза. Включите автофарм."
        or mode == "Full"
        and "Полная продажа по порядку: Option1 → Option1 → Option6. Включите автофарм. Закройте F9."
        or "Проверка: только первый клик, затем штатная отмена без проверки текста Deal. Включите автофарм."
    print("[YBA Debug] Merchant mode selected=" .. mode)
end
connectOwned(compareInputButton.MouseButton1Click, function() selectMerchantMode("Compare") end)
connectOwned(fullSaleButton.MouseButton1Click, function() selectMerchantMode("Full") end)
connectOwned(firstClickButton.MouseButton1Click, function() selectMerchantMode("FirstClick") end)
connectOwned(stopSaleButton.MouseButton1Click, function()
    Farm.UserRevision += 1
    print("[YBA Farm] User requested stop revision=" .. Farm.UserRevision)
    diagnostic.Failed = true
    CONFIG.Enabled = false
    setFarmToggle(false)
    statusLabel.Text = "Статус: Попытка остановлена пользователем"
end)
scrollContent.CanvasSize = UDim2.fromOffset(0, 966)
Settings.requestSave()

--------------------------------------------------------------------------------
-- 7. КАРДИНАЛЬНЫЙ NOCLIP
--------------------------------------------------------------------------------
connectOwned(RunService.Stepped, function()
    if not isFlying or not CONFIG.Enabled then return end

    local char = localPlayer.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.CanCollide = false
        end
    end
end)

--------------------------------------------------------------------------------
-- 8. ПЕРЕМЕЩЕНИЕ: STEALTH VELOCITY & INSTANT TELEPORT
--------------------------------------------------------------------------------
local function getCharacterParts(): (Model?, BasePart?, Humanoid?)
    local character = localPlayer.Character
    if not character then return nil, nil, nil end

    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return character, hrp, humanoid
end

local stealthPlatform: Part? = nil

local function getStealthPlatform(): Part
    if stealthPlatform and stealthPlatform.Parent == Workspace then
        return stealthPlatform
    end

    local part = Instance.new("Part")
    part.Name = "YBA_StealthFloor"
    part.Size = Vector3.new(4, 0.5, 4)
    part.Transparency = 1
    part.CanCollide = true
    part.Anchored = true
    part.CastShadow = false
    part.Parent = Workspace
    stealthPlatform = part
    return part
end

local function removeStealthPlatform()
    if stealthPlatform then
        pcall(function() stealthPlatform:Destroy() end)
        stealthPlatform = nil
    end
end

-- Stage outside the merchant building at the NPC floor, not on the roof above it.
function Farm.merchantStage(hrp: BasePart, target: Vector3): Vector3?
    local dialogues = Workspace:FindFirstChild("Dialogues")
    local merchant = dialogues and dialogues:FindFirstChild("ShiftPlox, The Travelling Merchant")
    local npcRoot = merchant and (merchant:FindFirstChild("HumanoidRootPart") or merchant:FindFirstChildWhichIsA("BasePart", true))
    local direction = npcRoot and Vector3.new(target.X - npcRoot.Position.X, 0, target.Z - npcRoot.Position.Z)
        or Vector3.new(hrp.Position.X - target.X, 0, hrp.Position.Z - target.Z)
    if direction.Magnitude < 0.1 then direction = Vector3.new(0, 0, 1) end
    direction = direction.Unit
    local ignore = {}
    if localPlayer.Character then table.insert(ignore, localPlayer.Character) end
    if merchant then table.insert(ignore, merchant) end
    if stealthPlatform then table.insert(ignore, stealthPlatform) end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.RespectCanCollide = true
    local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    local standingHeight = math.max(2.8, hrp.Size.Y * 0.5 + (humanoid and humanoid.HipHeight or 2))
    for _, distance in ipairs({12, 20, 28, 36}) do
        local horizontal = target + direction * distance
        local ground = Workspace:Raycast(horizontal + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), params)
        if ground and ground.Position.Y < target.Y - 0.5 then
            local candidate = Vector3.new(horizontal.X, ground.Position.Y + standingHeight, horizontal.Z)
            local ceiling = Workspace:Raycast(candidate - Vector3.new(0, 2, 0), Vector3.new(0, 5, 0), params)
            if not ceiling then return candidate end
        end
    end
    return nil
end

-- Универсальное перемещение
local function moveToTargetVelocity(hrp: BasePart, targetPos: Vector3, cancelRequested: (() -> boolean)?, forceVelocity: boolean?): boolean
    if not hrp or not hrp.Parent then return false end
    local moveCharacter = hrp.Parent
    local cancelled = false
    local function shouldCancel(): boolean
        local owner = hrp.Parent
        local humanoid = owner and owner:FindFirstChildOfClass("Humanoid")
        cancelled = cancelled or not runtime.Running or not CONFIG.Enabled or owner ~= moveCharacter
            or localPlayer.Character ~= moveCharacter or not humanoid or humanoid.Health <= 0
            or (cancelRequested ~= nil and cancelRequested())
        return cancelled
    end
    if shouldCancel() then return false end
    if NetworkTiming.RecoveryPending then
        local reference, stableSince = hrp.Position, os.clock()
        local deadline = os.clock() + math.max(3, NetworkTiming.seconds() * 5)
        repeat
            if shouldCancel() then return false end
            if (hrp.Position - reference).Magnitude > 1 then
                reference, stableSince = hrp.Position, os.clock()
            end
            if os.clock() - stableSince >= math.max(0.5, NetworkTiming.seconds() * 2) then
                NetworkTiming.RecoveryPending = false
                break
            end
            task.wait(0.05)
        until os.clock() >= deadline
        if NetworkTiming.RecoveryPending then return false end
    end
    if CONFIG.MoveMode == "Instant Teleport" and not forceVelocity and not cancelRequested and Farm.State == "Selling" then
        if (hrp.Position - targetPos).Magnitude > 10 or math.abs(hrp.Position.Y - targetPos.Y) > CONFIG.ArrivalTolerance then
            local staging = Farm.merchantStage(hrp, targetPos)
            if not staging then
                warn("[YBA Movement] No merchant staging point with ground and headroom; not teleporting onto roof")
                return false
            end
            print("[YBA Movement] Instant merchant staging=" .. tostring(staging) .. " NPC target=" .. tostring(targetPos))
            -- A non-nil cancellation predicate prevents recursion into the merchant approach.
            if not moveToTargetVelocity(hrp, staging, function() return false end) then return false end
            runtime.MerchantDeparture = {Character = hrp.Parent, Position = staging}
        end
        local owner = hrp.Parent
        local humanoid = owner and owner:FindFirstChildOfClass("Humanoid")
        if not runtime.Running or not CONFIG.Enabled or localPlayer.Character ~= owner or not humanoid or humanoid.Health <= 0 then return false end
        print("[YBA Movement] Merchant final approach: Stealth Velocity; configured mode remains Instant Teleport")
        local arrived = moveToTargetVelocity(hrp, targetPos, nil, true)
        local correctFloor = hrp.Parent ~= nil and math.abs(hrp.Position.Y - targetPos.Y) <= CONFIG.ArrivalTolerance + 1
        if not arrived or not correctFloor then
            warn("[YBA Movement] Merchant final approach did not reach the NPC floor")
            return false
        end
        return true
    end

    local flightDistance = (targetPos - hrp.Position).Magnitude
    local useInstant = CONFIG.MoveMode == "Instant Teleport" and not forceVelocity
        and flightDistance > 24 and os.clock() >= NetworkTiming.FallbackUntil
    -- Nearby targets avoid ascent/descent overhead; corrections temporarily select velocity.
    if useInstant then
        isFlying = true

        for _, obj in ipairs(hrp:GetChildren()) do
            if obj.Name == "YBA_Mover" or obj.Name == "YBA_Stabilizer" or obj.Name == "YBA_AntiFall" then
                pcall(function() obj:Destroy() end)
            end
        end
        removeStealthPlatform()

        -- Обнуление вектора скорости перед началом движения
        hrp.Velocity = Vector3.zero

        -- Делаем персонажа полностью невидимым на клиенте (защита от репортов и античета)
        local char = localPlayer.Character
        if char then
            setCharacterClientInvisibility(char, true)
        end

        -- Временное отключение гравитации и защита от падения в Kill-Zone
        local savedGravity = Workspace.Gravity
        runtime.SavedGravity = savedGravity
        Workspace.Gravity = 0

        local antiFall = Instance.new("BodyVelocity")
        antiFall.Name = "YBA_AntiFall"
        antiFall.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        antiFall.Velocity = Vector3.zero
        antiFall.Parent = hrp

        local platform = getStealthPlatform()
        local startPos = hrp.Position
        -- Reuse existing altitude instead of adding 3.5 studs above every starting point.
        local safeAirY = math.max(startPos.Y, targetPos.Y + 3.5)
        local expected = startPos
        local rotation = hrp.CFrame.Rotation
        local correctionThreshold = 6
        local function positionMatches(): boolean
            if (hrp.Position - expected).Magnitude <= correctionThreshold then return true end
            cancelled = true
            NetworkTiming.corrected()
            statusLabel.Text = "Статус: Коррекция позиции; временно Stealth Velocity"
            return false
        end
        local function advance(destination: Vector3): boolean
            while (destination - expected).Magnitude > 0.05 do
                if shouldCancel() or not positionMatches() then return false end
                local delta = destination - expected
                local segmentLength = NetworkTiming.seconds() > 0.1 and 12 or 16
                local stepDistance = math.min(segmentLength, delta.Magnitude)
                local nextPosition = expected + delta.Unit * stepDistance
                if platform and platform.Parent == Workspace then
                    platform.CFrame = CFrame.new(nextPosition - Vector3.new(0, 2.8, 0))
                end
                hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
                hrp.CFrame = CFrame.new(nextPosition) * rotation
                expected = nextPosition
                task.wait(NetworkTiming.stepDelay(stepDistance))
                -- Check the final step too; never snap to a target after cancellation/correction.
                if shouldCancel() or not positionMatches() then return false end
            end
            return not shouldCancel() and positionMatches()
        end
        local flightOk, arrived = xpcall(function(): boolean
            return advance(Vector3.new(startPos.X, safeAirY, startPos.Z))
                and advance(Vector3.new(targetPos.X, safeAirY, targetPos.Z))
                and advance(targetPos)
        end, tracebackError)
        if not flightOk then
            cancelled = true
            warn("[YBA Movement] Instant flight error: " .. tostring(arrived))
        end

        -- Восстановление гравитации и видимости
        pcall(function() antiFall:Destroy() end)
        Workspace.Gravity = (savedGravity > 0 and savedGravity) or 196.2
        runtime.SavedGravity = nil

        if char then
            setCharacterClientInvisibility(char, false)
        end

        isFlying = false
        if not cancelRequested or localPlayer.Character == moveCharacter then restoreCollisions() end
        if cancelled then
            removeStealthPlatform()
            if hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
        end
        return flightOk and arrived == true and not cancelled
    end

    -- РЕЖИМ 1: STEALTH VELOCITY
    isFlying = true

    for _, obj in ipairs(hrp:GetChildren()) do
        if obj.Name == "YBA_Mover" or obj.Name == "YBA_Stabilizer" then
            obj:Destroy()
        end
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "YBA_Mover"
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = "YBA_Stabilizer"
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.P = 10000
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    local platform = getStealthPlatform()
    local distance = (targetPos - hrp.Position).Magnitude
    local speed = NetworkTiming.speed()
    local maxFlightTime = (distance / math.max(1, speed * 0.25)) + 4.5
    local startTime = os.clock()
    local arrived = false

    local flightOk, flightError = xpcall(function()
    while (os.clock() - startTime) < maxFlightTime do
        if shouldCancel() or not hrp or not hrp.Parent or not CONFIG.Enabled or not runtime.Running then break end

        local currentPos = hrp.Position
        local delta = (targetPos - currentPos)
        local curDist = delta.Magnitude

        if curDist <= CONFIG.ArrivalTolerance then
            arrived = true
            break
        end

        local direction = delta.Unit
        speed = NetworkTiming.speed()
        bv.Velocity = direction * math.min(speed, curDist * 4)
        bg.CFrame = CFrame.new(currentPos, currentPos + Vector3.new(direction.X, 0, direction.Z))

        if platform and platform.Parent == Workspace then
            platform.CFrame = CFrame.new(currentPos.X, currentPos.Y - 2.8, currentPos.Z)
        end

        RunService.Heartbeat:Wait()
    end
    end, tracebackError)
    if not flightOk then
        cancelled = true
        warn("[YBA Movement] Velocity flight error: " .. tostring(flightError))
    end

    bv.Velocity = Vector3.zero
    if cancelRequested and not forceVelocity and not cancelled then
        RunService.Heartbeat:Wait()
    else
        task.wait(0.08)
    end

    pcall(function() bv:Destroy() end)
    pcall(function() bg:Destroy() end)
    isFlying = false

    if platform and platform.Parent == Workspace then
        platform.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - 2.8, hrp.Position.Z)
    end

    if not cancelRequested or localPlayer.Character == moveCharacter then restoreCollisions() end
    if cancelled then
        removeStealthPlatform()
        if hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
    end
    if not cancelRequested or forceVelocity then task.wait(0.2) end
    return arrived and not cancelled
end

--------------------------------------------------------------------------------
-- 9. ПРОВЕРКА ИНВЕНТАРЯ И ЭКИПИРОВКА
--------------------------------------------------------------------------------
runtime.Stop = function()
    if not runtime.Running then return end
    Settings.flush()
    runtime.Running = false
    CONFIG.Enabled = false
    if runtime.PickupCleanup then pcall(runtime.PickupCleanup) end
    if runtime.PromptRelease then pcall(runtime.PromptRelease) end
    if Farm.stopIndex then Farm.stopIndex() end
    if runtime.ClickCleanup then pcall(runtime.ClickCleanup) end
    if runtime.Cleanup then pcall(runtime.Cleanup) end
    if runtime.Thread then pcall(task.cancel, runtime.Thread) end
    if runtime.SavedGravity then
        Workspace.Gravity = runtime.SavedGravity
        runtime.SavedGravity = nil
    end
    for _, connection in ipairs(runtime.Connections) do pcall(function() connection:Disconnect() end) end
    table.clear(runtime.Connections)
    local character, root = getCharacterParts()
    if root then
        for _, child in ipairs(root:GetChildren()) do
            if child.Name == "YBA_Mover" or child.Name == "YBA_Stabilizer" or child.Name == "YBA_AntiFall" then child:Destroy() end
        end
        if not runtime.MerchantBlocked then root.Anchored = false end
    end
    removeStealthPlatform()
    if not runtime.MerchantBlocked then restoreCollisions() end
    if character then setCharacterClientInvisibility(character, false) end
    screenGui:Destroy()
end

local function getItemCount(itemName: string): number
    local canonical = Sales.Aliases[Sales.normalize(itemName)]
    if not canonical or Sales.protected(itemName) then return 0 end
    return Sales.snapshot()[canonical] or 0
end
local function getFullItemName(): string?
    if os.clock() - lastFailedSellTime < FAILED_SELL_COOLDOWN then return nil end
    local counts = Sales.snapshot()
    for _, itemName in ipairs(Sales.Order) do
        if CONFIG.SellItems[itemName] and (counts[itemName] or 0) >= CONFIG.Limits[itemName] then
            print(string.format("[YBA Inventory] Sale ready item=%s count=%d threshold=%d", itemName, counts[itemName], CONFIG.Limits[itemName]))
            return itemName
        end
    end
    return nil
end
local function equipItemToHand(itemName: string): boolean
    local char = localPlayer.Character
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local desired = Sales.Aliases[Sales.normalize(itemName)]
    if not char or not backpack or not desired or Sales.protected(itemName) then return false end
    for _, tool in ipairs(char:GetChildren()) do
        if Sales.resolve(tool) == desired then return true end
    end
    for _, tool in ipairs(backpack:GetChildren()) do
        if Sales.resolve(tool) == desired then
            tool.Parent = char
            Sales.LastScan = -math.huge
            task.wait(0.25)
            print("[YBA Inventory] Equipped actual=" .. tool.Name .. " canonical=" .. desired)
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 10. АКТИВАЦИЯ PROMPTS И ФИЛЬТРАЦИЯ ФАНТОМОВ (С ЧЕРНЫМ СПИСКОМ)
--------------------------------------------------------------------------------
local function activatePromptSafely(prompt: ProximityPrompt): boolean
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    local held = false
    local function release()
        if held then
            held = false
            if prompt.Parent then prompt:InputHoldEnd() end
        end
    end
    local ok, err = xpcall(function()
        prompt.HoldDuration = 0
        if typeof(fireproximityprompt) == "function" then
            fireproximityprompt(prompt)
        else
            runtime.PromptRelease = release
            held = true
            prompt:InputHoldBegin()
            task.wait(0.05)
            release()
        end
    end, tracebackError)
    local released, releaseError = pcall(release)
    if runtime.PromptRelease == release then runtime.PromptRelease = nil end
    if not ok or not released then
        warn("[YBA Prompt] Activation error: " .. tostring(ok and releaseError or err))
        return false
    end
    return true
end

local function findActivePrompt(instance: Instance): ProximityPrompt?
    local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then
        return prompt
    end
    return nil
end

local function getTargetBasePart(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    elseif instance:IsA("Model") then
        return instance.PrimaryPart or (instance:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
    end
    return nil
end

-- Проверка валидности предмета (не фантом, не 100% прозрачный)
local function isValidSpawnItem(item: Instance, part: BasePart?): boolean
    if itemBlacklist[item] or not part then return false end
    if part.Transparency < 0.95 then return true end
    for _, descendant in ipairs(item:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Transparency < 0.95 then return true end
    end
    -- Visibility can change after streaming; do not permanently blacklist it.
    return false
end

function Farm.disconnect(connections: {any})
    for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    table.clear(connections)
end
function Farm.setState(state: string, reason: string?)
    if Farm.State ~= state then
        print("[YBA Farm] " .. Farm.State .. " -> " .. state .. (reason and (" reason=" .. reason) or ""))
        Farm.State = state
    end
end
function Farm.normalize(name: string): string
    return string.lower(name):gsub("[^%a]", "")
end
function Farm.classify(root: Instance, part: BasePart?, prompt: ProximityPrompt?): (number, string)
    local priority, identity = 1, root.Name
    local function consider(value: any)
        if typeof(value) ~= "string" then return end
        local normalized = Farm.normalize(value)
        if (normalized == "luckyarrow" or normalized == "luckyarrowitem") and priority < 3 then
            priority, identity = 3, "Lucky Arrow"
        elseif (normalized == "luckymask" or normalized == "luckymaskitem" or normalized == "luckystonemask") and priority < 2 then
            priority, identity = 2, "Lucky Mask"
        end
    end
    local function metadata(object: Instance)
        consider(object.Name)
        for _, key in ipairs({"ItemName", "DisplayName", "Name", "ItemType"}) do consider(object:GetAttribute(key)) end
    end
    metadata(root)
    if part then metadata(part) end
    if prompt then metadata(prompt); consider(prompt.ObjectText); consider(prompt.ActionText) end
    for _, descendant in ipairs(root:GetDescendants()) do metadata(descendant) end
    if priority == 1 and not CONFIG.Limits[root.Name] and not Farm.UnknownNames[root.Name] and Farm.UnknownCount < 30 then
        Farm.UnknownNames[root.Name] = true
        Farm.UnknownCount += 1
        print("[YBA Farm] Unknown spawn identity kept ordinary: " .. root.Name)
    end
    return priority, identity
end
function Farm.remove(root: Instance)
    local old = Farm.Items[root]
    if old then Farm.disconnect(old.Connections) end
    Farm.Items[root], Farm.Dirty[root], itemBlacklist[root] = nil, nil, nil
    Farm.LastPick = -math.huge
end
function Farm.mark(root: Instance?)
    if root and root.Parent == Farm.Folder then Farm.Dirty[root] = true; Farm.LastPick = -math.huge end
end
function Farm.owner(object: Instance): Instance?
    local current: Instance? = object
    while current and current.Parent ~= Farm.Folder do current = current.Parent end
    return current
end
function Farm.stopIndex()
    Farm.disconnect(Farm.FolderConnections)
    for _, entry in pairs(Farm.Items) do Farm.disconnect(entry.Connections) end
    table.clear(Farm.Items)
    table.clear(Farm.Dirty)
    Farm.Folder, Farm.Best = nil, nil
end
function Farm.rebuild(root: Instance)
    local old = Farm.Items[root]
    if old then Farm.disconnect(old.Connections) end
    if root.Parent ~= Farm.Folder then Farm.Items[root] = nil; return end
    local part = getTargetBasePart(root)
    local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
    local priority, identity = Farm.classify(root, part, prompt)
    local entry = {Root = root, Part = part, Prompt = prompt, Priority = priority, Name = identity,
        Visible = isValidSpawnItem(root, part), Connections = {}}
    Farm.Items[root] = entry
    local function watch(signal: RBXScriptSignal)
        table.insert(entry.Connections, signal:Connect(function() Farm.mark(root) end))
    end
    watch(root:GetPropertyChangedSignal("Name"))
    watch(root.AttributeChanged)
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant ~= part and descendant ~= prompt then
            watch(descendant:GetPropertyChangedSignal("Name")); watch(descendant.AttributeChanged)
            if descendant:IsA("BasePart") then watch(descendant:GetPropertyChangedSignal("Transparency")) end
        end
    end
    if part then
        watch(part:GetPropertyChangedSignal("Name")); watch(part:GetPropertyChangedSignal("Transparency")); watch(part.AttributeChanged)
    end
    if prompt then
        watch(prompt:GetPropertyChangedSignal("Enabled")); watch(prompt:GetPropertyChangedSignal("ObjectText"))
        watch(prompt:GetPropertyChangedSignal("ActionText")); watch(prompt.AttributeChanged)
    end
end
function Farm.refresh(force: boolean?, reconcile: boolean?)
    local now = os.clock()
    if not force and now - Farm.LastRefresh < 0.1 then return end
    Farm.LastRefresh = now
    local spawns = Workspace:FindFirstChild("Item_Spawns")
    local folder = spawns and spawns:FindFirstChild("Items")
    if folder ~= Farm.Folder then
        Farm.stopIndex()
        Farm.Folder, Farm.LastPick = folder, -math.huge
        if folder then
            local function watch(signal: RBXScriptSignal, callback: any)
                table.insert(Farm.FolderConnections, signal:Connect(callback))
            end
            watch(folder.ChildAdded, function(root) Farm.mark(root) end)
            watch(folder.ChildRemoved, function(root) Farm.remove(root) end)
            watch(folder.DescendantAdded, function(object) Farm.mark(Farm.owner(object)) end)
            watch(folder.DescendantRemoving, function(object) Farm.mark(Farm.owner(object)) end)
            for _, root in ipairs(folder:GetChildren()) do Farm.mark(root) end
            print("[YBA Farm] Spawn index bound to " .. folder:GetFullName())
        end
    end
    if reconcile and Farm.Folder then
        -- Reconcile only spawn roots before patrol; do not scan all of Workspace.
        for _, root in ipairs(Farm.Folder:GetChildren()) do
            local entry = Farm.Items[root]
            if not entry or (not itemBlacklist[root] and (not entry.Part or not entry.Prompt or not entry.Visible)) then Farm.mark(root) end
        end
    end
    local dirty = Farm.Dirty
    Farm.Dirty = {}
    for root in pairs(dirty) do Farm.rebuild(root) end
end
-- An item root may itself be the BasePart hosting its prompt.
function Farm.available(entry: any): boolean
    if not entry or not Farm.Folder or entry.Root.Parent ~= Farm.Folder or itemBlacklist[entry.Root] then return false end
    local part, prompt = entry.Part, entry.Prompt
    if not part or not prompt or not prompt.Parent or not prompt.Enabled then return false end
    if not part:IsDescendantOf(Workspace) or not prompt:IsDescendantOf(entry.Root) then return false end
    if part ~= entry.Root and not part:IsDescendantOf(entry.Root) then return false end
    return entry.Visible == true
end
function Farm.best(origin: Vector3, force: boolean?): any
    Farm.refresh(force)
    if force then Farm.LastPick = -math.huge end
    local now = os.clock()
    if now - Farm.LastPick < 0.1 and (not Farm.Best or Farm.available(Farm.Best)) then return Farm.Best end
    Farm.LastPick = now
    local best, bestDistance = nil, math.huge
    for _, entry in pairs(Farm.Items) do
        if Farm.available(entry) then
            local distance = (entry.Part.Position - origin).Magnitude
            if (entry.Priority > 1 or distance <= CONFIG.Radius)
                and (not best or entry.Priority > best.Priority or (entry.Priority == best.Priority and distance < bestDistance)) then
                best, bestDistance = entry, distance
            end
        end
    end
    Farm.Best = best
    return best
end

-- Local batches are selected afresh after every pickup, not consumed from a stale queue.
function Farm.nearby(origin: Vector3): (any, number)
    Farm.refresh(true)
    local radius = math.min(CONFIG.NearbyRadius, CONFIG.Radius)
    local best, bestDistance, count = nil, math.huge, 0
    for _, entry in pairs(Farm.Items) do
        if Farm.available(entry) then
            local distance = (entry.Part.Position - origin).Magnitude
            if distance <= radius then count += 1 end
            -- Rare items retain global priority over an ordinary local batch.
            if entry.Priority > 1 or distance <= radius then
                if not best or entry.Priority > best.Priority or (entry.Priority == best.Priority and distance < bestDistance) then
                    best, bestDistance = entry, distance
                end
            end
        end
    end
    return best, count
end

-- Надежный сбор с защитой от пинга, пре-синхронизацией CFrame и античит-задержкой
local function interactWithItem(targetPart: BasePart, prompt: ProximityPrompt, itemInstance: Instance?): boolean
    local character, hrp, humanoid = getCharacterParts()
    if not character or not hrp or not humanoid then return false end
    local camera = Workspace.CurrentCamera
    local savedType = camera and camera.CameraType
    local savedFrame = camera and camera.CFrame
    local savedFocus = camera and camera.Focus
    local savedSubject = camera and camera.CameraSubject
    local aimed, cleaned = false, false
    local cameraConnection: RBXScriptConnection? = nil
    local started = os.clock()
    local function active(): boolean
        return runtime.Running and CONFIG.Enabled and localPlayer.Character == character
            and hrp.Parent == character and humanoid.Parent == character and humanoid.Health > 0
    end
    local function gone(): boolean
        return not targetPart:IsDescendantOf(Workspace) or not prompt.Parent or not prompt:IsDescendantOf(Workspace)
            or (itemInstance ~= nil and not itemInstance:IsDescendantOf(Workspace))
    end
    local function promptPosition(): Vector3
        local parent = prompt.Parent
        if parent and parent:IsA("Attachment") then return parent.WorldPosition end
        if parent and parent:IsA("BasePart") then return parent.Position end
        return targetPart.Position
    end
    local function cleanup()
        if cleaned then return end
        cleaned = true
        if cameraConnection then cameraConnection:Disconnect(); cameraConnection = nil end
        if aimed and camera and Workspace.CurrentCamera == camera and camera.CameraType == Enum.CameraType.Scriptable then
            local sameCharacter = localPlayer.Character == character and humanoid.Parent == character and humanoid.Health > 0
            if sameCharacter and camera.CameraSubject == savedSubject then
                camera.CFrame = savedFrame
                camera.Focus = savedFocus
            end
            -- Never restore the old subject/pose after a death or character replacement.
            camera.CameraType = sameCharacter and savedType or Enum.CameraType.Custom
        end
    end
    runtime.PickupCleanup = cleanup
    local ok, collected = xpcall(function(): boolean
        if not active() or gone() or not prompt.Enabled then return false end
        local function inRange(): boolean
            local distance = (hrp.Position - promptPosition()).Magnitude
            if distance > prompt.MaxActivationDistance then
                warn(string.format("[YBA Pickup] Out of range: distance=%.2f max=%.2f", distance, prompt.MaxActivationDistance))
                return false
            end
            return true
        end
        if not inRange() then return false end
        if CONFIG.AimCamera and camera then
            aimed = true
            camera.CameraType = Enum.CameraType.Scriptable
            local function lookAtTarget()
                if cleaned or not active() or gone() or Workspace.CurrentCamera ~= camera then return end
                local position = savedFrame.Position
                local target = promptPosition()
                if (position - target).Magnitude < 0.1 then position = target + Vector3.new(0, 3, 6) end
                camera.CFrame = CFrame.lookAt(position, target)
                camera.Focus = CFrame.new(target)
            end
            lookAtTarget()
            cameraConnection = RunService.RenderStepped:Connect(lookAtTarget)
            for _ = 1, 2 do
                if not active() or gone() then return false end
                RunService.RenderStepped:Wait()
            end
        end
        -- Required physics synchronization is retained, independently of camera aiming.
        local synchronizeUntil = os.clock() + math.max(0.35, NetworkTiming.seconds() * 2)
        repeat
            if not active() or gone() then return false end
            task.wait(0.01)
        until os.clock() >= synchronizeUntil
        if not inRange() then return false end
        -- One request only: a late server reply must not race retries or departure.
        for attempt = 1, 1 do
            if not active() or gone() or not prompt.Enabled or not inRange() then return false end
            runtime.PickupHold = {Character = character, Root = hrp, Humanoid = humanoid,
                Gone = gone, Started = os.clock(), LastLog = os.clock()}
            if not activatePromptSafely(prompt) then return false end
            local requestAt = os.clock()
            local deadline = requestAt + math.max(4, NetworkTiming.seconds() * 8 + NetworkTiming.Jitter * 4)
            print(string.format("[YBA Pickup] Await confirmation RTT=%.3fs timeout=%.2fs", NetworkTiming.seconds(), deadline - requestAt))
            repeat
                if not active() then return false end
                if gone() then
                    runtime.PickupHold = nil
                    STATS.Collected += 1
                    statsSubLabel.Text = string.format("Собрано: %d | Продано партий: %d", STATS.Collected, STATS.SoldBatches)
                    print(string.format("[YBA Pickup] Confirmed disappearance; elapsed=%.3fs; no post-pickup wait", os.clock() - started))
                    return true
                end
                deadline = math.min(requestAt + 30, math.max(deadline,
                    requestAt + NetworkTiming.seconds() * 8 + NetworkTiming.Jitter * 4))
                task.wait(0.025)
            until os.clock() >= deadline
        end
        statusLabel.Text = "Статус: Ожидаем подтверждение подбора; автофарм включён"
        warn(string.format("[YBA Pickup] Confirmation delayed; holding in place with autofarm enabled; RTT=%.3fs", NetworkTiming.seconds()))
        return false
    end, tracebackError)
    local cleanedOk, cleanupError = pcall(cleanup)
    if runtime.PickupCleanup == cleanup then runtime.PickupCleanup = nil end
    if not cleanedOk then warn("[YBA Pickup] Camera cleanup error: " .. tostring(cleanupError)) end
    if not ok then warn("[YBA Pickup] Error: " .. tostring(collected)); return false end
    return collected == true
end

-- A dispatched pickup owns movement until its result is known; never resend it on a timeout.
function Farm.waitForPickup(): boolean
    local hold = runtime.PickupHold
    if not hold then return false end
    Farm.setState("AwaitPickup", "awaiting delayed pickup confirmation; no movement or repeated prompt")
    local sameCharacter = localPlayer.Character == hold.Character and hold.Root.Parent == hold.Character
        and hold.Humanoid.Parent == hold.Character and hold.Humanoid.Health > 0
    if not sameCharacter then
        runtime.PickupHold = nil
        CONFIG.Enabled = false
        setFarmToggle(false)
        statusLabel.Text = "Статус: Сбор остановлен — персонаж погиб или сменился"
        return true
    end
    if hold.Gone() then
        runtime.PickupHold = nil
        STATS.Collected += 1
        statsSubLabel.Text = string.format("Собрано: %d | Продано партий: %d", STATS.Collected, STATS.SoldBatches)
        Farm.Best, Farm.LastPick = nil, -math.huge
        Farm.setState("Search", "delayed pickup confirmed -> resume farm")
        statusLabel.Text = "Статус: Подбор подтверждён; продолжаем фарм"
        print(string.format("[YBA Pickup] Delayed confirmation after %.2fs; autofarm resumes", os.clock() - hold.Started))
        return true
    end
    statusLabel.Text = "Статус: Ожидаем ответ подбора; автофарм включён (" .. math.floor(os.clock() - hold.Started) .. " с)"
    if os.clock() - hold.LastLog >= 5 then
        hold.LastLog = os.clock()
        print(string.format("[YBA Pickup] Still awaiting confirmation %.2fs RTT=%.3fs; no retry/departure",
            os.clock() - hold.Started, NetworkTiming.seconds()))
    end
    return true
end

--------------------------------------------------------------------------------
-- 11. АВТОПРОДАЖА ТОРГОВЦУ SHIFTPLOX (STAGED OPTIONS)
--------------------------------------------------------------------------------
local function getMerchantData(): (BasePart?, ProximityPrompt?)
    local dialogues = Workspace:FindFirstChild("Dialogues")
    if not dialogues then return nil, nil end

    local merchant = dialogues:FindFirstChild("ShiftPlox, The Travelling Merchant")
    if not merchant then return nil, nil end

    local prompt = merchant:FindFirstChildWhichIsA("ProximityPrompt", true)
    local part: BasePart? = nil

    -- Приоритет 1: деталь, которой непосредственно принадлежит ProximityPrompt
    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
        part = prompt.Parent :: BasePart
    -- Приоритет 2: HumanoidRootPart или Torso NPC
    elseif merchant:IsA("Model") then
        part = (merchant:FindFirstChild("HumanoidRootPart") :: BasePart?)
            or (merchant:FindFirstChild("Torso") :: BasePart?)
            or (merchant:FindFirstChild("UpperTorso") :: BasePart?)
            or merchant.PrimaryPart
            or (merchant:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
    elseif merchant:IsA("BasePart") then
        part = merchant
    end

    return part, prompt
end

-- Merchant UI is intentionally restricted to the official dialogue hierarchy.
local function isVisibleDialogueObject(object: GuiObject): boolean
    if object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then return false end
    local current: Instance? = object
    while current do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") then return current.Enabled end
        current = current.Parent
    end
    return false
end

local function getMerchantOptionContainers(): {Instance}
    local result = {}
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return result end
    -- Server-created replacements can coexist with an old same-named instance.
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui.Name == "DialogueGui" and gui:IsA("ScreenGui") and gui.Enabled then
            for _, frame in ipairs(gui:GetChildren()) do
                if frame.Name == "Frame" and frame:IsA("GuiObject") and isVisibleDialogueObject(frame) then
                    for _, options in ipairs(frame:GetChildren()) do
                        if options.Name == "Options" and options:IsA("GuiObject") and isVisibleDialogueObject(options) then
                            table.insert(result, options)
                        end
                    end
                end
            end
        end
    end
    return result
end
local function getMerchantOptions(): Instance?
    local containers = getMerchantOptionContainers()
    return containers[#containers]
end

local function normalizeDialogueText(text: string): string
    return string.lower(text:gsub("<[^>]->", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
end
local function readRenderedText(root: Instance): string
    local function orderedChildren(object: Instance): {Instance}
        local children = object:GetChildren()
        table.sort(children, function(left, right)
            local lp, ln = string.match(left.Name, "^(%a+)(%d+)$")
            local rp, rn = string.match(right.Name, "^(%a+)(%d+)$")
            if lp and rp and lp == rp then return tonumber(ln) < tonumber(rn) end
            if left:IsA("GuiObject") and right:IsA("GuiObject") and left.LayoutOrder ~= right.LayoutOrder then
                return left.LayoutOrder < right.LayoutOrder
            end
            return left.Name < right.Name
        end)
        return children
    end
    local function read(object: Instance): string
        if object:IsA("GuiObject") and not isVisibleDialogueObject(object) then return "" end
        local children, fragments = orderedChildren(object), {}
        local charSequence = false
        for _, child in ipairs(children) do
            if string.match(child.Name, "^Char%d+$") then charSequence = true end
        end
        for _, child in ipairs(children) do
            local text = read(child)
            if text ~= "" then table.insert(fragments, text) end
        end
        -- Prefer the rendered leaves to the TextLabel used as their template.
        if #fragments > 0 then return table.concat(fragments, charSequence and "" or " ") end
        if (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) and object.TextTransparency < 1 then
            local text = object.ContentText
            return text ~= "" and text or object.Text:gsub("<[^>]->", "")
        end
        return ""
    end
    return normalizeDialogueText(read(root))
end
local function getOptionText(option: Instance): string
    return readRenderedText(option)
end
local function getNamedMerchantOption(options: Instance, name: string): GuiObject?
    local candidates = {}
    for _, child in ipairs(options:GetChildren()) do
        if child.Name == name and child:IsA("GuiObject") and isVisibleDialogueObject(child) then table.insert(candidates, child) end
    end
    if #candidates == 1 then return candidates[1] end
    return nil
end
local function resolveMerchantTextButton(option: GuiObject): (TextButton?, string?)
    local candidates = {}
    if option:IsA("TextButton") and isVisibleDialogueObject(option) then table.insert(candidates, option) end
    for _, object in ipairs(option:GetDescendants()) do
        if object:IsA("TextButton") and isVisibleDialogueObject(object) then table.insert(candidates, object) end
    end
    if #candidates == 0 then return nil, "no visible TextButton in " .. option:GetFullName() end
    if #candidates ~= 1 then return nil, "ambiguous TextButton count=" .. #candidates end
    return candidates[1], nil
end

-- GUI hit-testing uses inset-relative coordinates; input uses screen coordinates.
-- Keep both values explicit. Do not send the hit-test point to the mouse API.
local function automaticMerchantPoint(button: TextButton): (Vector2?, string, Vector2?)
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    local gui = button:FindFirstAncestorWhichIsA("ScreenGui")
    local camera = Workspace.CurrentCamera
    if not playerGui or not gui or not camera then return nil, "no GUI/camera", nil end
    local inset = game:GetService("GuiService"):GetGuiInset()
    local center = button.AbsolutePosition + button.AbsoluteSize / 2
    local primaryHit = gui.IgnoreGuiInset and center - inset or center
    local alternativeHit = gui.IgnoreGuiInset and center or center - inset
    for index, candidate in ipairs({primaryHit, alternativeHit}) do
        local hitPoint = Vector2.new(math.floor(candidate.X), math.floor(candidate.Y))
        local screenPoint = hitPoint + inset
        local viewport = camera.ViewportSize
        local onScreen = screenPoint.X >= 0 and screenPoint.Y >= 0 and screenPoint.X < viewport.X and screenPoint.Y < viewport.Y
        local top = playerGui:GetGuiObjectsAtPosition(hitPoint.X, hitPoint.Y)[1]
        local covered = false
        local ok, overlays = pcall(function() return CoreGui:GetGuiObjectsAtPosition(hitPoint.X, hitPoint.Y) end)
        if ok then
            for _, overlay in ipairs(overlays) do
                if overlay:IsA("GuiButton") or overlay.Active then covered = true; break end
            end
        end
        if onScreen and top and (top == button or top:IsDescendantOf(button)) and not covered then
            local reason = string.format("%s hitGUI=%s inputScreen=%s inset=%s IgnoreGuiInset=%s viewport=%s top=%s",
                index == 1 and "primary" or "alternative", tostring(hitPoint), tostring(screenPoint), tostring(inset),
                tostring(gui.IgnoreGuiInset), tostring(viewport), top:GetFullName())
            return screenPoint, reason, hitPoint
        end
    end
    return nil, "target covered/missing or coordinate points outside viewport; close F9", nil
end
local function dumpMerchantGui()
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end
    print("[YBA Debug] GUI options begin; containers=" .. #getMerchantOptionContainers())
    local count = 0
    for _, options in ipairs(getMerchantOptionContainers()) do
        for _, option in ipairs(options:GetChildren()) do
            if option:IsA("GuiObject") and isVisibleDialogueObject(option) then
                local button, reason = resolveMerchantTextButton(option)
                if button then
                    local point, pointReason, hitPoint = automaticMerchantPoint(button)
                    local top = hitPoint and playerGui:GetGuiObjectsAtPosition(hitPoint.X, hitPoint.Y)[1]
                    print(string.format("[YBA Debug] option=%s button=%s text=%q pos=%s size=%s point=%s insetMode=%s top=%s",
                        option.Name, button:GetFullName(), getOptionText(option), tostring(button.AbsolutePosition),
                        tostring(button.AbsoluteSize), tostring(point), pointReason,
                        top and top:GetFullName() or "none"))
                else print("[YBA Debug] option=" .. option.Name .. " error=" .. tostring(reason)) end
                count += 1
                if count >= 12 then break end
            end
        end
        if count >= 12 then break end
    end
    print("[YBA Debug] GUI options end")
end

-- Snapshot visible option contents; reused Option1 instances must change text too.
local function merchantOptionsSnapshot(): string
    local options = getMerchantOptions()
    if not options then return "" end
    local entries = {}
    for _, option in ipairs(options:GetChildren()) do
        if option:IsA("GuiObject") and isVisibleDialogueObject(option) then
            table.insert(entries, option.Name .. "=" .. getOptionText(option))
        end
    end
    table.sort(entries)
    return table.concat(entries, "|")
end

local function isMerchantDialogueVisible(): boolean
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return false end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui.Name == "DialogueGui" and gui:IsA("ScreenGui") and gui.Enabled then
            for _, frame in ipairs(gui:GetChildren()) do
                if frame.Name == "Frame" and frame:IsA("GuiObject") and isVisibleDialogueObject(frame) then return true end
            end
        end
    end
    return false
end

local function findMerchantExit(): GuiObject?
    local candidates = {}
    for _, options in ipairs(getMerchantOptionContainers()) do
        for _, option in ipairs(options:GetChildren()) do
            if (option.Name == "Option1" or option.Name == "Option2") and option:IsA("GuiObject") and isVisibleDialogueObject(option) then
                local text = getOptionText(option)
                if string.find(text, "nevermind", 1, true) or string.find(text, "never mind", 1, true)
                    or string.match(text, "^%s*no[%.!]?%s*$") then table.insert(candidates, option) end
            end
        end
    end
    if #candidates == 1 then return candidates[1] end
    return nil
end

-- Dispatch one mouse click through Roblox input; never invoke Lua handlers directly.
local function waitMerchantFrames(count: number, canContinue: () -> boolean): boolean
    for _ = 1, count do
        if not canContinue() then return false end
        RunService.RenderStepped:Wait()
        if not canContinue() then return false end
    end
    return true
end

local function dispatchMerchantMouseClick(option: GuiObject, canContinue: () -> boolean): boolean
    local button: TextButton? = nil
    local observers = {}
    local observed = {}
    local automaticObserved = observed
    local manualObserved = {}
    local globalObserved = {automatic = {}, manual = {}}
    local phase = "automatic"
    local manualReleasedAt: number? = nil
    local comparisonHint: TextLabel? = nil
    local downAttempted, pressed, released, cleaned = false, false, false, false
    local x, y = 0, 0
    local path = option:GetFullName()
    local clickStart = os.clock()
    local optionName = option.Name
    local function cleanup()
        -- Release even after cancellation, callback failure or executor shutdown.
        if pressed then
            local ok, err = pcall(function()
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
            released = ok
            if ok then pressed = false else warn("[YBA Debug] Mouse release error: " .. tostring(err)) end
        end
        if runtime.MouseCleanup == cleanup and not pressed then runtime.MouseCleanup = nil end
        if cleaned then return end
        cleaned = true
        for _, connection in ipairs(observers) do pcall(function() connection:Disconnect() end) end
        table.clear(observers)
        if comparisonHint then comparisonHint:Destroy(); comparisonHint = nil end
    end
    runtime.MouseCleanup = cleanup
    local function event(name: string)
        if cleaned or observed[name] then return end
        if name ~= "MouseEnter" and not downAttempted then return end
        observed[name] = true
        print(string.format("[YBA Debug] Mouse phase=%s event=%s target=%s t=%.3f", phase, name, path, os.clock() - clickStart))
    end
    local function observe(signal: RBXScriptSignal, callback: any)
        table.insert(observers, signal:Connect(callback))
    end
    local function targetIsCurrent(): boolean
        if not canContinue() or not option.Parent or not isVisibleDialogueObject(option) then return false end
        local containers = getMerchantOptionContainers()
        if #containers ~= 1 or option.Parent ~= containers[1] then return false end
        if getNamedMerchantOption(containers[1], option.Name) ~= option then return false end
        local current = resolveMerchantTextButton(option)
        return current ~= nil and current == button
    end
    local ok, result = xpcall(function(): boolean
        if not canContinue() then return false end
        local containers = getMerchantOptionContainers()
        if #containers ~= 1 then warn("[YBA Debug] Mouse target container is ambiguous/missing"); return false end
        local freshOption = getNamedMerchantOption(containers[1], optionName)
        if not freshOption then warn("[YBA Debug] Mouse option is ambiguous/missing: " .. optionName); return false end
        option = freshOption
        local reason: string? = nil
        button, reason = resolveMerchantTextButton(option)
        if not button then warn("[YBA Debug] Mouse target error: " .. tostring(reason)); return false end
        if not targetIsCurrent() then warn("[YBA Debug] Mouse target changed before hover"); return false end
        path = button:GetFullName()
        local function globalEvent(name: string, input: InputObject, processed: boolean?)
            if cleaned then return end
            local isMouseButton = input.UserInputType == Enum.UserInputType.MouseButton1
            local isMovement = input.UserInputType == Enum.UserInputType.MouseMovement
            if not isMouseButton and not isMovement then return end
            local key = isMovement and "MouseMove" or name
            local bucket = globalObserved[phase]
            if not bucket[key] then
                bucket[key] = true
                local point = UserInputService:GetMouseLocation()
                local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
                local inset = game:GetService("GuiService"):GetGuiInset()
                local hitPoint = point - inset
                local hits = playerGui and playerGui:GetGuiObjectsAtPosition(math.floor(hitPoint.X), math.floor(hitPoint.Y)) or {}
                print(string.format("[YBA Debug] Input comparison phase=%s UIS=%s mouse=%s processed=%s top=%s currentTarget=%s",
                    phase, key, tostring(point), tostring(processed), hits[1] and hits[1]:GetFullName() or "none", tostring(targetIsCurrent())))
            end
            if phase == "manual" and isMouseButton and name == "InputEnded" then manualReleasedAt = os.clock() end
        end
        observe(UserInputService.InputBegan, function(input, processed) globalEvent("InputBegan", input, processed) end)
        observe(UserInputService.InputChanged, function(input, processed) globalEvent("InputChanged", input, processed) end)
        observe(UserInputService.InputEnded, function(input, processed) globalEvent("InputEnded", input, processed) end)
        observe(button.MouseEnter, function() event("MouseEnter") end)
        observe(button.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then event("InputBegan") end
        end)
        observe(button.MouseButton1Down, function() event("MouseButton1Down") end)
        observe(button.MouseButton1Up, function() event("MouseButton1Up") end)
        observe(button.MouseButton1Click, function() event("MouseButton1Click") end)
        observe(button.Activated, function() event("Activated") end)

        local stable = false
        local settleDeadline = os.clock() + 1
        repeat
            if not targetIsCurrent() then return false end
            local point, pointReason = automaticMerchantPoint(button)
            if not point then warn("[YBA Debug] Mouse blocked: " .. pointReason); return false end
            local position, size = button.AbsolutePosition, button.AbsoluteSize
            x, y = math.floor(point.X), math.floor(point.Y)
            VirtualInputManager:SendMouseMoveEvent(x, y, game)
            if not waitMerchantFrames(2, canContinue) then return false end
            if not targetIsCurrent() then return false end
            local currentPoint, currentReason = automaticMerchantPoint(button)
            if not currentPoint then warn("[YBA Debug] Mouse blocked after hover: " .. currentReason); return false end
            stable = (button.AbsolutePosition - position).Magnitude <= 0.5
                and (button.AbsoluteSize - size).Magnitude <= 0.5 and (currentPoint - point).Magnitude <= 0.5
            if os.clock() > settleDeadline then
                warn("[YBA Debug] Mouse target stabilization exceeded 1 second"); return false
            end
            if stable then
                print(string.format("[YBA Debug] Mouse target ready=%s point=(%d,%d) %s", path, x, y, currentReason))
                break
            end
        until os.clock() >= settleDeadline
        if not stable then warn("[YBA Debug] Mouse target did not settle within 1 second"); return false end
        if not targetIsCurrent() then return false end
        downAttempted, pressed = true, true
        print("[YBA Debug] Mouse input sent target=" .. path)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        local holdDeadline = os.clock() + 0.12
        while canContinue() and os.clock() < holdDeadline do task.wait(0.01) end
        -- Release is mandatory even when canContinue() became false during the hold.
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        pressed, released = false, true
        if not canContinue() then return false end
        local deliveryDeadline = os.clock() + 1
        repeat
            if not canContinue() then return false end
            if observed.MouseButton1Click or observed.Activated then
                print("[YBA Debug] Mouse click confirmed target=" .. path .. " event=" .. (observed.MouseButton1Click and "MouseButton1Click" or "Activated"))
                return true
            end
            task.wait(0.01)
        until os.clock() >= deliveryDeadline
        warn(string.format("[YBA Debug] Mouse input not delivered: target=%s enter=%s input=%s down=%s up=%s click=%s activated=%s",
            path, tostring(observed.MouseEnter == true), tostring(observed.InputBegan == true),
            tostring(observed.MouseButton1Down == true), tostring(observed.MouseButton1Up == true),
            tostring(observed.MouseButton1Click == true), tostring(observed.Activated == true)))
        if runtime.CompareFirstClick and not runtime.InputComparisonDone and canContinue() then
            runtime.InputComparisonDone = true
            runtime.ComparisonOccurred = true
            phase = "manual"
            observed = manualObserved
            comparisonHint = Instance.new("TextLabel")
            comparisonHint.Name = "MerchantInputComparison"
            comparisonHint.Size = UDim2.fromOffset(600, 70)
            comparisonHint.Position = UDim2.new(0.5, -300, 0, 60)
            comparisonHint.BackgroundColor3 = THEME.CardBg
            comparisonHint.TextColor3 = THEME.TextPrimary
            comparisonHint.TextSize = 15
            comparisonHint.TextWrapped = true
            comparisonHint.Text = "Программный клик не подтверждён. Нажмите ПЕРВУЮ кнопку диалога ОДИН РАЗ вручную. F9 должна быть закрыта."
            comparisonHint.Parent = screenGui
            local cancelComparison = Instance.new("TextButton")
            cancelComparison.Size = UDim2.new(1, 0, 0, 28)
            cancelComparison.Position = UDim2.new(0, 0, 1, 4)
            cancelComparison.BackgroundColor3 = THEME.Warning
            cancelComparison.Text = "Остановить сравнение"
            cancelComparison.TextSize = 14
            cancelComparison.Parent = comparisonHint
            observe(cancelComparison.MouseButton1Click, function()
                diagnostic.Failed = true
                CONFIG.Enabled = false
                setFarmToggle(false)
            end)
            statusLabel.Text = "Статус: Сравнение ввода — ожидается один ручной клик"
            print("[YBA Debug] Input comparison MANUAL READY: click the same first button once; no more synthetic clicks")
            local manualDeadline = os.clock() + 60
            while canContinue() and os.clock() < manualDeadline do
                if manualReleasedAt and os.clock() - manualReleasedAt >= 0.5 then break end
                if (manualObserved.MouseButton1Click or manualObserved.Activated) and not manualReleasedAt then
                    manualReleasedAt = os.clock()
                end
                task.wait(0.05)
            end
            local manualTarget = manualObserved.MouseButton1Click == true or manualObserved.Activated == true
            local autoGlobal = globalObserved.automatic.InputBegan == true
            local manualGlobal = globalObserved.manual.InputBegan == true
            local diagnosis: string
            if not canContinue() then
                diagnosis = "comparison cancelled or character damaged; no conclusion"
            elseif manualTarget and not autoGlobal then
                diagnosis = "manual target works; synthetic mouse not observed by UIS or target"
            elseif manualTarget then
                diagnosis = "manual target works; synthetic input does not activate this target"
            elseif manualGlobal then
                diagnosis = "manual UIS event observed but target silent; verify actual target/instance; acceptance unknown"
            else
                diagnosis = "manual input not observed; timeout/cancellation or observer unavailable; inconclusive"
            end
            runtime.ComparisonSummary = diagnosis
            print(string.format("[YBA Debug] Input comparison RESULT autoUIS=%s autoDown=%s autoClick=%s manualUIS=%s manualDown=%s manualClick=%s targetStillCurrent=%s diagnosis=%s",
                tostring(autoGlobal), tostring(automaticObserved.MouseButton1Down == true), tostring(automaticObserved.MouseButton1Click == true or automaticObserved.Activated == true),
                tostring(manualGlobal), tostring(manualObserved.MouseButton1Down == true), tostring(manualTarget), tostring(targetIsCurrent()), diagnosis))
            diagnosticLabel.Text = "Сравнение завершено. Закройте диалог вручную, остановите автофарм и сохраните строки Input comparison из F9."
        end
        return false
    end, tracebackError)
    cleanup()
    if runtime.MouseCleanup == cleanup and not pressed then runtime.MouseCleanup = nil end
    if not ok then warn("[YBA Debug] Mouse dispatcher error: " .. tostring(result)) end
    return ok and result and released and canContinue()
end

local function activateMerchantOption(option: GuiObject, canContinue: () -> boolean): boolean
    local menuVisible = mainFrame.Visible
    local function finish()
        if runtime.MouseCleanup then pcall(runtime.MouseCleanup) end
        if mainFrame.Parent then mainFrame.Visible = menuVisible end
    end
    runtime.ClickCleanup = finish
    mainFrame.Visible = false
    local ok, result = xpcall(function(): boolean
        if not waitMerchantFrames(2, canContinue) then return false end
        return dispatchMerchantMouseClick(option, canContinue)
    end, tracebackError)
    finish()
    if runtime.ClickCleanup == finish then runtime.ClickCleanup = nil end
    if not ok then warn("[YBA Debug] Merchant click error: " .. tostring(result)); return false end
    return result
end

local function executeMerchantState(itemName: string, hrp: BasePart): boolean
    local character, root, humanoid = getCharacterParts()
    if not character or not humanoid or root ~= hrp then return false end
    local originalCharacter, originalHumanoid = character, humanoid
    local beforeCount, lastHealth = getItemCount(itemName), humanoid.Health
    local startedAt = os.clock()
    local promptAt: number? = nil
    local clickAt: number? = nil
    local stage, failure = "start", nil
    local opened, saleAttempted, testPassed = false, false, false
    local saleConfirmed = false
    local requestedSale = diagnostic.SellRequested
    local recoverableReason: string? = nil
    local testMode = diagnostic.Mode == "FirstClick" or diagnostic.Mode == "Compare"
    local monitoring = {}
    diagnostic.Failed = false
    diagnostic.SellRequested = false
    runtime.CompareFirstClick = false
    runtime.ComparisonOccurred = false
    print("[YBA Debug] Merchant attempt mode=" .. diagnostic.Mode .. " item=" .. itemName)

    local function log(message: string)
        print(string.format("[YBA Debug] v=%s stage=%s t=%.2f prompt=%.2f click=%.2f health=%.2f speed=%.2f anchored=%s changed=%s %s",
            VERSION, stage, os.clock() - startedAt, promptAt and os.clock() - promptAt or -1,
            clickAt and os.clock() - clickAt or -1, originalHumanoid.Health, originalHumanoid.WalkSpeed,
            tostring(hrp.Anchored), tostring(localPlayer.Character ~= originalCharacter), message))
    end
    local function alive(): boolean
        return localPlayer.Character == originalCharacter and hrp.Parent == originalCharacter
            and originalHumanoid.Parent == originalCharacter and originalHumanoid.Health > 0
    end
    local function abort(reason: string)
        if failure then return end
        failure = reason
        log("ABORT " .. reason)
        CONFIG.Enabled = false
        setFarmToggle(false)
        statusLabel.Text = "Статус: Продажа остановлена: " .. reason
    end
    local function active(): boolean
        return runtime.Running and CONFIG.Enabled and not failure and alive() and not diagnostic.Failed
    end
    local function monitor(signal: RBXScriptSignal, callback: any)
        table.insert(monitoring, signal:Connect(callback))
    end
    local function releaseResources()
        diagnostic.Waiting = false
        for _, connection in ipairs(monitoring) do pcall(function() connection:Disconnect() end) end
        table.clear(monitoring)
        removeStealthPlatform()
        -- No Humanoid assignments, forced state changes, GUI hiding or Controls calls.
    end
    runtime.Cleanup = releaseResources
    local function pause(seconds: number): boolean
        local deadline = os.clock() + seconds
        repeat
            if not active() then return false end
            task.wait(0.05)
        until os.clock() >= deadline
        return active()
    end
    local function reportPause(reason: string)
        recoverableReason = reason
        log("PAUSE " .. reason)
        statusLabel.Text = "Статус: Пауза у торговца — " .. reason
    end
    local function waitTarget(name: string, deadline: number): GuiObject?
        local lastReason = "target missing"
        repeat
            if not active() then return nil end
            local containers = getMerchantOptionContainers()
            if #containers == 1 then
                local option = getNamedMerchantOption(containers[1], name)
                if option then
                    local button, reason = resolveMerchantTextButton(option)
                    if button then return option end
                    lastReason = reason or "TextButton unavailable"
                else lastReason = "missing or ambiguous " .. name end
            else lastReason = "visible Options count=" .. #containers end
            task.wait(0.05)
        until os.clock() >= deadline
        reportPause(name .. ": " .. lastReason)
        dumpMerchantGui()
        return nil
    end
    local function selectStage(name: string, label: string, delay: number): boolean
        local option = waitTarget(name, os.clock() + math.max(5, NetworkTiming.seconds() * 8 + 2))
        if not option or not active() then return false end
        local button, reason = resolveMerchantTextButton(option)
        if not button then reportPause(label .. ": " .. tostring(reason)); return false end
        log("step=" .. label .. " target=" .. name .. " button=" .. button:GetFullName() .. " diagnosticText=" .. getOptionText(option))
        clickAt = os.clock()
        runtime.CompareFirstClick = diagnostic.Mode == "Compare" and label == "first Option1"
        local delivered = activateMerchantOption(option, active)
        runtime.CompareFirstClick = false
        if not delivered then
            reportPause(runtime.ComparisonOccurred and "сравнение ввода завершено; сохраните F9; закройте диалог вручную" or (label .. ": ввод не доставлен или цель недоступна; повторного клика нет"))
            return false
        end
        if name == "Option6" then
            saleAttempted = true
            log("Option6 appeared and received a confirmed click")
        end
        if not pause(math.max(delay, NetworkTiming.seconds() * 2 + NetworkTiming.Jitter * 2)) then return false end
        if name ~= "Option6" then return true end
        local deadline = clickAt + math.max(5, NetworkTiming.seconds() * 8 + 2)
        local reducedAt: number? = nil
        repeat
            if not active() then return false end
            local count = getItemCount(itemName)
            if count < beforeCount then
                reducedAt = reducedAt or os.clock()
                if os.clock() - reducedAt >= 0.1 then
                    saleConfirmed = true
                    log(string.format("sale inventory confirmed item=%s before=%d after=%d", itemName, beforeCount, count))
                    return true
                end
            else reducedAt = nil end
            deadline = math.min(clickAt + 45, math.max(deadline, clickAt + NetworkTiming.seconds() * 8 + 2))
            task.wait(0.1)
        until os.clock() >= deadline
        reportPause("inventory confirmation delayed after ALL; wait for native release")
        dumpMerchantGui()
        return false
    end
    local function waitForNativeRelease(): boolean
        local releaseStarted = os.clock()
        stage = "native-dialogue-exit"
        local deadline = os.clock() + math.max(7, NetworkTiming.seconds() * 4 + 2)
        local exitClicked = false
        local stableSince: number? = nil
        local stablePosition = hrp.Position
        repeat
            if not active() then return false end
            local visible = isMerchantDialogueVisible()
            if not visible and originalHumanoid.WalkSpeed > 0 and not hrp.Anchored
                and not originalHumanoid.PlatformStand and not originalHumanoid.Sit then
                if (hrp.Position - stablePosition).Magnitude > 1 then
                    stablePosition, stableSince = hrp.Position, nil
                end
                stableSince = stableSince or os.clock()
                local settleSeconds = math.max(0.75, NetworkTiming.seconds() * 3)
                if os.clock() - stableSince >= settleSeconds then
                    runtime.MerchantBlocked = false
                    log(string.format("native release confirmed elapsed=%.3fs; no character state was forced", os.clock() - releaseStarted))
                    return true
                end
            else
                stableSince = nil
                stablePosition = hrp.Position
            end
            -- Give a completed transaction 0.3 seconds to close the GUI naturally.
            if visible and not exitClicked and os.clock() - releaseStarted >= 0.3 then
                local exit: GuiObject? = nil
                if saleConfirmed then
                    local containers = getMerchantOptionContainers()
                    if #containers == 1 then exit = getNamedMerchantOption(containers[1], "Option1") end
                elseif testMode and testPassed then
                    exit = findMerchantExit()
                end
                if exit then
                    exitClicked = true
                    clickAt = os.clock()
                    log("native exit button=" .. exit.Name .. " text=" .. getOptionText(exit))
                    if not activateMerchantOption(exit, active) then return false end
                end
            end
            task.wait(0.05)
        until os.clock() >= deadline
        log(string.format("native release timeout elapsed=%.3fs; close dialogue manually; no forced recovery", os.clock() - releaseStarted))
        return false
    end
    local ok, result = xpcall(function(): boolean
        monitor(originalHumanoid.HealthChanged, function(health)
            log(string.format("HealthChanged %.2f -> %.2f", lastHealth, health))
            if health < lastHealth then abort("health decreased") end
            lastHealth = health
        end)
        monitor(originalHumanoid.StateChanged, function(old, new)
            log("Humanoid state " .. tostring(old) .. " -> " .. tostring(new))
        end)
        monitor(originalHumanoid:GetPropertyChangedSignal("WalkSpeed"), function()
            log("game/external WalkSpeed change observed")
        end)
        monitor(originalHumanoid.Died, function() abort("Humanoid.Died") end)
        monitor(originalCharacter.DescendantRemoving, function(part)
            if part:IsA("BasePart") and not part:FindFirstAncestorWhichIsA("Tool")
                and not part:FindFirstAncestorWhichIsA("Accessory") then abort("body part removed: " .. part.Name) end
        end)
        monitor(localPlayer.CharacterRemoving, function(removed)
            if removed == originalCharacter then abort("CharacterRemoving") end
        end)
        monitor(localPlayer.CharacterAdded, function(added)
            if added ~= originalCharacter then abort("CharacterAdded") end
        end)
        if not active() then return false end
        if isMerchantDialogueVisible() then log("close existing dialogue manually first"); return false end
        if runtime.MerchantBlocked and (originalHumanoid.WalkSpeed <= 0 or hrp.Anchored) then
            log("previous dialogue has not released character; movement blocked"); return false
        end
        runtime.MerchantBlocked = false
        local merchPart, merchPrompt = getMerchantData()
        if not merchPart or not merchPrompt then return false end
        stage = "equip"
        if not equipItemToHand(itemName) or not pause(0.2) then return false end
        stage = "travel"
        statusLabel.Text = "Статус: Подлет к ShiftPlox..."
        local look = merchPart.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        flat = flat.Magnitude > 0.01 and flat.Unit * 3.5 or Vector3.new(0, 0, 3.5)
        if not moveToTargetVelocity(hrp, merchPart.Position + flat) or not active() then return false end
        stage = "settle"
        for _, child in ipairs(hrp:GetChildren()) do
            if child.Name == "YBA_Mover" or child.Name == "YBA_Stabilizer" or child.Name == "YBA_AntiFall" then child:Destroy() end
        end
        hrp.Anchored = false
        hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        removeStealthPlatform()
        local deadline = os.clock() + 3
        local stableSince, stablePosition = os.clock(), hrp.Position
        while active() do
            if hrp.Anchored or hrp:FindFirstChild("YBA_Mover") or hrp:FindFirstChild("YBA_Stabilizer") or hrp:FindFirstChild("YBA_AntiFall") then return false end
            if (hrp.Position - stablePosition).Magnitude > 1 or hrp.AssemblyLinearVelocity.Magnitude > 1 then
                stableSince, stablePosition = os.clock(), hrp.Position
            elseif os.clock() - stableSince >= 0.35 then break end
            if os.clock() >= deadline then log("settling timeout"); return false end
            task.wait(0.05)
        end
        if not active() then return false end
        log("position stable")
        stage = "open"
        statusLabel.Text = "Статус: Открытие диалога..."
        opened, promptAt, runtime.MerchantBlocked = true, os.clock(), true
        activatePromptSafely(merchPrompt)
        if not pause(1) then return false end
        diagnostic.Waiting = testMode
        stage = "offer"
        if not selectStage("Option1", "first Option1", 0.8) then return false end
        if testMode then
            testPassed = true
            log("first click dispatched; no text-based transition confirmation; test stops here")
            return true
        end
        stage = "deal"
        if not selectStage("Option1", "second Option1", 0.8) then return false end
        stage = "all"
        if not selectStage("Option6", "Option6 ALL", 1.5) then return false end
        return active() and saleAttempted and getItemCount(itemName) < beforeCount
    end, tracebackError)
    if not ok then warn("[YBA Debug] Merchant error: " .. tostring(result)) end
    local attemptFailed = not ok or not result
    local attemptStage = stage
    local released = not runtime.MerchantBlocked
    if opened and active() then
        local exitOk, exitResult = xpcall(waitForNativeRelease, tracebackError)
        released = exitOk and exitResult
        if not exitOk then warn("[YBA Debug] Native exit error: " .. tostring(exitResult)) end
        if not released and not failure then reportPause((recoverableReason and (recoverableReason .. "; ") or ("stage " .. attemptStage .. "; ")) .. "native exit unconfirmed; close manually") end
    end
    stage = "post-exit-observation"
    local observationSeconds = saleConfirmed and released and ok and result and 0.5 or 5
    log("observation begin: " .. observationSeconds .. " seconds")
    local observationStarted = os.clock()
    local deadline = observationStarted + observationSeconds
    while runtime.Running and os.clock() < deadline do
        if not alive() and not failure then abort("character lost after attempt") end
        -- Keep monitoring after health drops so delayed death is also recorded.
        task.wait(0.05)
    end
    log(string.format("observation end elapsed=%.3fs", os.clock() - observationStarted))
    local afterCount = alive() and getItemCount(itemName) or beforeCount
    local survived = alive() and not failure
    local success = ok and result and active() and survived and released and saleAttempted and afterCount < beforeCount
    local testSuccess = ok and testPassed and active() and survived and released
    local outcome = success and "automatic-sale-confirmed" or (testSuccess and "first-click-and-native-exit-passed"
        or (failure or ((not CONFIG.Enabled or not runtime.Running) and "cancelled-by-user" or (recoverableReason or "not-confirmed"))))
    log(string.format("finished before=%d after=%d released=%s outcome=%s", beforeCount, afterCount, tostring(released), outcome))
    releaseResources()
    if runtime.Cleanup == releaseResources then runtime.Cleanup = nil end
    if not runtime.Running then return false end
    if testMode and testSuccess then
        CONFIG.Enabled = false
        setFarmToggle(false)
        diagnostic.Mode = "Full"
        diagnostic.SellRequested = true
        diagnosticLabel.Text = "Первый клик и выход проверены. Выбрана полная последовательность: включите автофарм ещё раз. Закройте F9."
        statusLabel.Text = "Статус: Проверка пройдена"
        return false
    end
    if success then
        diagnosticLabel.Text = "Полная продажа подтверждена. Автофарм продолжен; следующие продажи — по лимитам."
        STATS.SoldBatches += 1
        statsSubLabel.Text = string.format("Собрано: %d | Продано партий: %d", STATS.Collected, STATS.SoldBatches)
        return true
    end
    lastFailedSellTime = os.clock()
    if not failure and runtime.Running and CONFIG.Enabled and alive() and not diagnostic.Failed then
        runtime.MerchantBlocked = true
        runtime.MerchantHold = {Character = originalCharacter, Humanoid = originalHumanoid, Root = hrp,
            Health = originalHumanoid.Health, Reason = recoverableReason or "sale not confirmed", ReadySince = nil,
            ReleasedAt = nil, RequestedSale = requestedSale, ComparisonPause = runtime.ComparisonOccurred == true,
            PendingItem = saleAttempted and not saleConfirmed and itemName or nil, BeforeCount = beforeCount}
        diagnosticLabel.Text = "Пауза у торговца. Закройте диалог вручную, если он открыт; затем дождитесь кулдауна. Повторных кликов нет."
        statusLabel.Text = "Статус: Пауза у торговца — " .. runtime.MerchantHold.Reason
        log("merchant hold entered; autofarm remains enabled")
    end
    return false
end

--------------------------------------------------------------------------------
-- 12. ГЛАВНЫЙ ЦИКЛ STATE MACHINE & PATROL LOOP
--------------------------------------------------------------------------------
local patrolIndex = 1

runtime.Thread = task.spawn(function()
    while runtime.Running do
        if Farm.LastEnabled ~= CONFIG.Enabled then
            print("[YBA Farm] Enabled=" .. tostring(CONFIG.Enabled) .. " userRevision=" .. Farm.UserRevision .. " state=" .. Farm.State)
            Farm.LastEnabled = CONFIG.Enabled
        end
        if not CONFIG.Enabled then
            Farm.setState("Stopped", "disabled by user or safety condition; not automatically re-enabled")
            removeStealthPlatform()
            if not runtime.MerchantBlocked then restoreCollisions() end
            task.wait(0.5)
            continue
        end

        local loopSuccess, loopError = pcall(function()
            local character, hrp, humanoid = getCharacterParts()
            if Farm.waitForPickup() then return end

            -- No patrol, prompts, tool equips or retries while a merchant hold exists.
            if runtime.MerchantBlocked and not runtime.MerchantHold and hrp and humanoid then
                if isMerchantDialogueVisible() or humanoid.WalkSpeed <= 0 or hrp.Anchored or humanoid.PlatformStand or humanoid.Sit then
                    runtime.MerchantHold = {Character = character, Humanoid = humanoid, Root = hrp, Health = humanoid.Health,
                        Reason = "previous dialogue unresolved", ReadySince = nil, ReleasedAt = nil, RequestedSale = false}
                else runtime.MerchantBlocked = false end
            end
            local hold = runtime.MerchantHold
            if hold then
                Farm.setState("AwaitRelease", hold.Reason)
                local invalid = character ~= hold.Character or hrp ~= hold.Root or humanoid ~= hold.Humanoid
                    or not hrp or not humanoid or hrp.Parent ~= hold.Character or humanoid.Health <= 0
                local damaged = not invalid and humanoid.Health < hold.Health - 0.001
                if invalid or damaged then
                    CONFIG.Enabled = false
                    setFarmToggle(false)
                    statusLabel.Text = "Статус: Автофарм остановлен — повреждение или смена персонажа на паузе"
                    warn("[YBA Debug] Merchant hold stopped: " .. (invalid and "character lost/changed" or "health decreased"))
                    runtime.MerchantHold = nil
                    runtime.MerchantBlocked = isMerchantDialogueVisible()
                    return
                end
                hold.Health = humanoid.Health
                if hold.PendingItem then
                    local count = getItemCount(hold.PendingItem)
                    if count >= hold.BeforeCount then
                        statusLabel.Text = "Статус: Ожидаем списание после продажи; автофарм включён"
                        return
                    end
                    print(string.format("[YBA Merchant] Delayed sale confirmed item=%s before=%d after=%d",
                        hold.PendingItem, hold.BeforeCount, count))
                    hold.PendingItem = nil
                    STATS.SoldBatches += 1
                    statsSubLabel.Text = string.format("Собрано: %d | Продано партий: %d", STATS.Collected, STATS.SoldBatches)
                end
                if hold.ComparisonPause then
                    statusLabel.Text = "Статус: Пауза — сравнение завершено; остановите автофарм и сохраните F9"
                    task.wait(0.2)
                    return
                end
                local ready = not isMerchantDialogueVisible() and humanoid.WalkSpeed > 0 and not hrp.Anchored
                    and not humanoid.PlatformStand and not humanoid.Sit
                if ready then
                    hold.ReadySince = hold.ReadySince or os.clock()
                    if os.clock() - hold.ReadySince >= 0.35 then
                        if not hold.ReleasedAt then
                            hold.ReleasedAt = os.clock()
                            lastFailedSellTime = hold.ReleasedAt
                            print("[YBA Debug] Merchant hold: native release observed; cooldown=" .. FAILED_SELL_COOLDOWN)
                        end
                        local remaining = FAILED_SELL_COOLDOWN - (os.clock() - hold.ReleasedAt)
                        if remaining <= 0 then
                            runtime.MerchantHold = nil
                            runtime.MerchantBlocked = false
                            diagnostic.SellRequested = hold.RequestedSale
                            statusLabel.Text = "Статус: Пауза завершена; автофарм продолжен"
                            print("[YBA Debug] Merchant hold cleared after native release and cooldown")
                            return
                        end
                        statusLabel.Text = "Статус: Пауза у торговца — кулдаун " .. math.ceil(remaining) .. " с"
                    end
                else
                    hold.ReadySince, hold.ReleasedAt = nil, nil
                    statusLabel.Text = "Статус: Пауза у торговца — закройте диалог вручную; ожидаем управление"
                end
                task.wait(0.2)
                return
            end

            if not hrp or not humanoid or humanoid.Health <= 0 then
                Farm.setState("AwaitCharacter", "character unavailable")
                statusLabel.Text = "Статус: Ожидание возрождения..."
                statusLabel.TextColor3 = THEME.TextSecondary
                removeStealthPlatform()
                restoreCollisions()
                task.wait(1)
                return
            end


            Farm.setState("Search")
            local target, nearbyCount = Farm.nearby(hrp.Position)
            target = target or Farm.best(hrp.Position, true)
            -- A loaded rare item wins before starting a new merchant trip.
            -- Once a sale starts, no farm cancellation callback is supplied to it.
            if not target or target.Priority <= 1 then
                local itemToSell = getFullItemName()
                if diagnostic.Mode ~= "Full" or diagnostic.SellRequested then
                    itemToSell = nil
                    for name, allowed in pairs(CONFIG.SellItems) do
                        if allowed and getItemCount(name) > 0 then itemToSell = name; break end
                    end
                end
                if itemToSell then
                    Farm.setState("Selling", itemToSell)
                    statusLabel.Text = "Лимит " .. itemToSell .. "! Продажа..."
                    statusLabel.TextColor3 = THEME.Warning
                    local revision = Farm.UserRevision
                    local wasFullSale = diagnostic.Mode == "Full"
                    local sold = executeMerchantState(itemToSell, hrp)
                    if sold and wasFullSale and CONFIG.Enabled and runtime.Running
                        and localPlayer.Character == character and humanoid.Health > 0 and not runtime.MerchantBlocked then
                        -- Retrace the final approach before any Instant ascent inside the building.
                        local departure = runtime.MerchantDeparture
                        if CONFIG.MoveMode == "Instant Teleport" and not getFullItemName() then
                            local outside = departure and departure.Character == character and departure.Position
                                or Farm.merchantStage(hrp, hrp.Position)
                            local function cancelDeparture(): boolean
                                return localPlayer.Character ~= character or humanoid.Health <= 0 or isMerchantDialogueVisible()
                                    or humanoid.WalkSpeed <= 0
                            end
                            if not outside or not moveToTargetVelocity(hrp, outside, cancelDeparture, true) then
                                if CONFIG.Enabled and runtime.Running and localPlayer.Character == character and humanoid.Health > 0 then
                                    runtime.MerchantBlocked = true
                                    runtime.MerchantHold = {Character = character, Humanoid = humanoid, Root = hrp,
                                        Health = humanoid.Health, Reason = "выход от торговца задержан", ReadySince = nil,
                                        ReleasedAt = nil, RequestedSale = false}
                                    statusLabel.Text = "Статус: Пауза у торговца; автофарм включён"
                                end
                                warn("[YBA Movement] Merchant departure pending; no toggle change or Instant flight")
                                return
                            end
                            runtime.MerchantDeparture = nil
                            print("[YBA Movement] Merchant departure complete; Instant travel may resume")
                        end
                        Farm.Best, Farm.LastPick = nil, -math.huge
                        Farm.setState("Search", "sale completed -> fresh scan; next full inventory batch remains eligible")
                        statusLabel.Text = "Статус: Продажа завершена; поиск предметов..."
                        statusLabel.TextColor3 = THEME.Accent
                    elseif not CONFIG.Enabled then
                        local reason = Farm.UserRevision ~= revision and "user switched off during sale"
                            or "sale safety/diagnostic stop; see merchant log"
                        Farm.setState("Stopped", reason)
                    elseif runtime.MerchantBlocked or runtime.MerchantHold then
                        Farm.setState("AwaitRelease", "merchant pause preserved")
                    else
                        Farm.setState("Search", "sale attempt ended without an unresolved dialogue")
                    end
                    return
                end
            end

            if not target or not Farm.available(target) then
                -- A fresh index check is mandatory before committing to a patrol flight.
                Farm.refresh(true, true)
                target, nearbyCount = Farm.nearby(hrp.Position)
                target = target or Farm.best(hrp.Position, true)
            end
            if not target or not Farm.available(target) then
                local index = patrolIndex
                local patrolTarget = CONFIG.PatrolPoints[index]
                Farm.setState("Patrol", tostring(index) .. "/" .. #CONFIG.PatrolPoints)
                statusLabel.Text = string.format("Статус: Патруль точки %d/%d...", index, #CONFIG.PatrolPoints)
                statusLabel.TextColor3 = THEME.TextSecondary
                local interrupted = false
                local arrived = moveToTargetVelocity(hrp, patrolTarget, function()
                    local found = Farm.best(hrp.Position)
                    if found then interrupted = true; return true end
                    return false
                end)
                if arrived or not interrupted then patrolIndex = (index % #CONFIG.PatrolPoints) + 1 end
                Farm.setState("Search", interrupted and "item detected during patrol" or "patrol step finished")
                task.wait(CONFIG.ScanDelay)
                return
            end

            local priority = target.Priority
            Farm.setState("FlightItem", target.Name .. " priority=" .. priority)
            statusLabel.Text = nearbyCount > 1
                and ("Статус: Сбор группы рядом (" .. nearbyCount .. ") — " .. target.Name)
                or ("Статус: Подлет к " .. target.Name .. "...")
            statusLabel.TextColor3 = priority > 1 and THEME.Warning or THEME.AccentHover
            local function cancelItemFlight(): boolean
                if not Farm.available(target) then return true end
                local best = Farm.best(hrp.Position)
                if best and best.Priority > priority then
                    print("[YBA Farm] Preempt " .. target.Name .. " -> " .. best.Name)
                    return true
                end
                return false
            end
            local arrived = moveToTargetVelocity(hrp, target.Part.Position + Vector3.new(1.8, 0, 0), cancelItemFlight)
            if not CONFIG.Enabled or not runtime.Running then return end
            if not arrived or not Farm.available(target) then Farm.setState("Search", "flight interrupted/target removed"); return end
            local best = Farm.best(hrp.Position)
            if best and best.Priority > priority then Farm.setState("Search", "rare item detected before collection"); return end
            Farm.setState("Collect", target.Name)
            statusLabel.Text = "Статус: Сбор " .. target.Name .. "..."
            statusLabel.TextColor3 = THEME.Success
            -- Preserve the complete pickup transaction, including the 0.35s physics delay.
            interactWithItem(target.Part, target.Prompt, target.Root)
            if runtime.PickupHold or not CONFIG.Enabled then return end
            Farm.Best, Farm.LastPick = nil, -math.huge
            local nextTarget, remaining = Farm.nearby(hrp.Position)
            if nextTarget then
                print("[YBA Farm] Pickup complete; local remaining=" .. remaining .. " next=" .. nextTarget.Name .. "; patrol skipped")
                statusLabel.Text = "Статус: Продолжаем сбор рядом — " .. nextTarget.Name
            end
            Farm.setState("Search", nextTarget and "continue item batch; fresh target next tick" or "pickup finished; recheck before patrol")

        end)

        if not loopSuccess then
            warn("[Stealth Engine Loop Error]:", loopError)
            task.wait(0.5)
        end

        task.wait(0.1)
    end
end)
