-- [[ mpX Hub - Loader Principal (Protegido) ]]
local JSONBIN_ID   = "6a735f7eda38895dfebda63a"
local GITHUB_USER  = "paulo123ld"
local GITHUB_REPO  = "mpX-Hub"
local HUB_VERSION  = "6.27"

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

if not httpRequest then
    warn("[mpX Hub] Executor não suporta HTTP.")
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
        local body = response.Body or ""
        if not string.find(body, "too_large", 1, true) then
            return body
        end
    end
    -- Arquivo grande (a contents API so devolve texto ate 1MB): pega o sha
    -- e usa o blob API, que aguenta ate 100MB.
    local meta = httpRequest({
        Url     = url,
        Method  = "GET",
        Headers = {
            ["Authorization"] = "token " .. GITHUB_TOKEN,
            ["Accept"]        = "application/vnd.github+json",
            ["User-Agent"]    = "RobloxHost"
        }
    })
    if meta.StatusCode ~= 200 then
        return nil
    end
    local okMeta, dec = pcall(function()
        return game:GetService("HttpService"):JSONDecode(meta.Body)
    end)
    if not okMeta or type(dec) ~= "table" or not dec.sha then
        return nil
    end
    local blob = httpRequest({
        Url     = string.format(
            "https://api.github.com/repos/%s/%s/git/blobs/%s",
            GITHUB_USER, GITHUB_REPO, dec.sha
        ),
        Method  = "GET",
        Headers = {
            ["Authorization"] = "token " .. GITHUB_TOKEN,
            ["Accept"]        = "application/vnd.github+json",
            ["User-Agent"]    = "RobloxHost"
        }
    })
    if blob.StatusCode ~= 200 then
        return nil
    end
    local okBlob, b = pcall(function()
        return game:GetService("HttpService"):JSONDecode(blob.Body)
    end)
    if not okBlob or type(b) ~= "table" or not b.content then
        return nil
    end
    local content = string.gsub(b.content, "\n", "")
    if b.encoding == "base64" then
        local okDec, text = pcall(function() return game:Base64Decode(content) end)
        if not okDec then
            return nil
        end
        return text
    end
    return content
end

local function loadModule()
    local placeId = tostring(game.PlaceId)

    print("[mpX Hub] Carregando v" .. HUB_VERSION .. "...")

    if getgenv()._mpX_Version ~= HUB_VERSION then
        getgenv()._mpX_Obsidian = nil
        getgenv()._mpX_Corvus   = nil
        getgenv()._mpX_Core     = nil
        getgenv()._mpX_WindUI   = nil
        getgenv()._mpX_Version  = HUB_VERSION
    end

    -- UI: biblioteca Corvus (Obsidian + camada visual do Corvus: starfield,
    -- aurora, glass, cometa, cursor light, widgets Professional).
    -- A mesma lib atende os jogos antigos (API Obsidian) e o shim WindUI
    -- atende os scripts que falavam WindUI (Universal, Marretao, addons).
    if not getgenv()._mpX_Corvus then
        local corvusCode = fetchGitHubFile("Libs/CorvusUI.lua")

        if corvusCode then
            local fn, err = loadstring(corvusCode)
            if not fn then
                warn("[mpX Hub] Erro compilando CorvusUI: " .. tostring(err))
            else
                local ok, result = pcall(fn)
                if ok and type(result) == "table" then
                    getgenv()._mpX_Corvus = result
                    getgenv()._mpX_Obsidian = result
                    print("[mpX Hub] CorvusUI carregado!")
                else
                    warn("[mpX Hub] Erro executando CorvusUI: " .. tostring(result))
                end
            end
        else
            warn("[mpX Hub] Falha ao baixar CorvusUI (seguindo no WindUI antigo).")
        end
    end

    if getgenv()._mpX_Corvus and not getgenv()._mpX_WindUI then
        local shimCode = fetchGitHubFile("Libs/WindUIShim.lua")
        if shimCode then
            local fn = loadstring(shimCode)
            local ok, result = pcall(fn)
            if ok and type(result) == "table" then
                getgenv()._mpX_WindUI = result
                print("[mpX Hub] Shim WindUI pronto!")
            else
                warn("[mpX Hub] Erro no shim WindUI: " .. tostring(result))
            end
        else
            warn("[mpX Hub] Falha ao baixar o shim WindUI.")
        end
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
        warn("[mpX Hub] Obsidian não está no cache!")
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
            warn("[mpX Hub] Falha ao baixar Core — recursos extras desativados.")
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

