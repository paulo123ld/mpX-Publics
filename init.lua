-- [[ mpX Hub - Loader Principal (Protegido) ]]
local JSONBIN_ID   = "6a735f7eda38895dfebda63a"
local GITHUB_USER  = "paulo123ld"
local GITHUB_REPO  = "mpX-Hub"
local HUB_VERSION  = "6.15"

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

if not httpRequest then
    warn("[mpX Hub] Executor nÃ£o suporta HTTP.")
    return
end

-- Puxa o token do JSONBin
local function getToken()
    local url = "https://api.jsonbin.io/v3/b/" .. JSONBIN_ID .. "/latest"

    local response = httpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "RobloxHost"
        }
    })

    if response.StatusCode ~= 200 then
        return nil
    end

    local HttpService = game:GetService("HttpService")
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not ok or not decoded then return nil end

    -- JSONBin retorna { record = { token = "..." } }
    if decoded.record and decoded.record.token then
        return decoded.record.token
    end

    return nil
end

local GITHUB_TOKEN = getToken()

if not GITHUB_TOKEN then
    warn("[mpX Hub] Falha ao obter token de acesso!")
    return
end

local function fetchGitHubFile(path)
    local url = string.format(
        "https://api.github.com/repos/%s/%s/contents/%s",
        GITHUB_USER, GITHUB_REPO, path
    )
    local response = httpRequest({
        Url     = url,
        Method  = "GET",
        Headers = {
            ["Authorization"] = "token " .. GITHUB_TOKEN,
            ["Accept"]        = "application/vnd.github.v3.raw",
            ["User-Agent"]    = "RobloxHost"
        }
    })
    if response.StatusCode == 200 then
        return response.Body
    end
    return nil
end

local function loadModule()
    local placeId = tostring(game.PlaceId)

    print("[mpX Hub] Carregando v" .. HUB_VERSION .. "...")

    if getgenv()._mpX_Version ~= HUB_VERSION then
        getgenv()._mpX_Obsidian = nil
        getgenv()._mpX_Core     = nil
        getgenv()._mpX_WindUI   = nil
        getgenv()._mpX_Version  = HUB_VERSION
    end

    if not getgenv()._mpX_Obsidian then
        local obsidianCode = fetchGitHubFile("Libs/Obsidian.lua")

        if not obsidianCode then
            warn("[mpX Hub] Falha ao baixar Obsidian!")
            return
        end

        local fn, err = loadstring(obsidianCode)
        if not fn then
            warn("[mpX Hub] Erro compilando Obsidian: " .. tostring(err))
            return
        end

        local ok, result = pcall(fn)
        if not ok or type(result) ~= "table" then
            warn("[mpX Hub] Erro executando Obsidian: " .. tostring(result))
            return
        end

        getgenv()._mpX_Obsidian = result
    end

    if not getgenv()._mpX_Obsidian then
        warn("[mpX Hub] Obsidian nÃ£o estÃ¡ no cache!")
        return
    end

    if not getgenv()._mpX_Core then
        local coreCode = fetchGitHubFile("Libs/Core.lua")

        if coreCode then
            local fn, err = loadstring(coreCode)
            if not fn then
                warn("[mpX Hub] Erro compilando Core: " .. tostring(err))
            else
                local ok, result = pcall(fn)
                if ok and type(result) == "table" then
                    getgenv()._mpX_Core = result
                else
                    warn("[mpX Hub] Erro executando Core: " .. tostring(result))
                end
            end
        else
            warn("[mpX Hub] Falha ao baixar Core â recursos extras desativados.")
        end
    end

    if getgenv()._mpX_Core then
        print("[mpX Hub] Core v" .. HUB_VERSION .. " carregado!")
    end

    local universalCode = fetchGitHubFile("Games/Universal.lua")
    local gameCode      = fetchGitHubFile("Games/" .. placeId .. ".lua")

    local function runCode(code, label)
        if not code then return false end
        local fn, err = loadstring(code)
        if not fn then
            warn("[mpX Hub] Erro ao compilar " .. label .. ": " .. tostring(err))
            return false
        end
        local ok, e2 = pcall(fn)
        if not ok then warn("[mpX Hub] Erro ao rodar " .. label .. ": " .. tostring(e2)) end
        return ok
    end

    -- arquivo de jogo marcado com --[[mpX_ADDON]] roda POR CIMA do Universal
    if gameCode and gameCode:find("%-%-%[%[mpX_ADDON%]%]") then
        print("[mpX Hub] Universal + addon do jogo")
        runCode(universalCode, "Universal")
        runCode(gameCode, "addon do jogo")
    else
        runCode(gameCode or universalCode, "script do jogo")
    end
end

loadModule()

