--[[
    mpX PROBE - FTF Recon (v1.0)
    Script separado so para DESCOBRIR o que o servidor do FTF aceita.
    Objetivo: achar as funcoes "apelonas" (Slow Beast, Untie, Anti Seer, etc.)
    que nao da para fazer mexendo em propriedade do cliente.

    COMO USAR (dentro do FTF, como survivor OU como beast):
      loadstring(game:HttpGet("https://raw.githubusercontent.com/paulo123ld/mpX-Publics/main/probe.lua"))()

    COMO LER O RESULTADO:
      - O painel mostra "DIFERENCA" quando algum input mudou algo de verdade
        (velocidade da fera, animacao, estado, poder, etc).
      - Copie e cole a parte do console aqui no chat que eu transformo em funcao
        no mpX-Hub.

    IMPORTANTE: isso so DESCUBRE. Nao executa nada perigoso, so dispara os
    inputs que o jogo ja usa e mede a diferenca.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local LP = Players.LocalPlayer
local out = {}

local function log(msg)
    msg = tostring(msg)
    table.insert(out, msg)
    print("[PROBE] " .. msg)
end

-- =====================================================================
-- 1) DESCOBERTA: remotes disponiveis
-- =====================================================================
local remotes = {}
local function scanRemotes()
    table.clear(remotes)
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            table.insert(remotes, obj)
        end
    end
    return remotes
end

local function remoteNames()
    local n = {}
    for _, r in ipairs(remotes) do table.insert(n, r.Name .. " (" .. r.ClassName .. ")") end
    table.sort(n)
    return table.concat(n, ", ")
end

-- =====================================================================
-- 2) MEDICAO: estado do mundo antes e depois de um input
-- =====================================================================
local function getStats(plr)
    local m = plr and plr:FindFirstChild("TempPlayerStatsModule")
    if not m then return nil end
    local t = {}
    for _, c in ipairs(m:GetChildren()) do
        if c:IsA("BoolValue") or c:IsA("StringValue") or c:IsA("IntValue") or c:IsA("NumberValue") then
            t[c.Name] = tostring(c.Value)
        end
    end
    return t
end

local function getChar(plr)
    return plr and plr.Character
end

local function humWS(plr)
    local c = getChar(plr)
    local h = c and c:FindFirstChild("Humanoid")
    return h and math.floor(h.WalkSpeed) or -1
end

local function beastPlr()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local s = getStats(p)
            if s and s.IsBeast == "true" then return p end
        end
    end
    return nil
end

local function snapshot()
    local self = getStats(LP)
    local b = beastPlr()
    return {
        selfWS = humWS(LP),
        selfRag = self and self.Ragdoll or "?",
        selfCrawl = self and self.IsCrawling or "?",
        selfAnim = self and self.CurrentAnimation or "?",
        beastName = b and (b.DisplayName or b.Name) or "-",
        beastWS = b and humWS(b) or -1,
        beastRag = b and (getStats(b) and getStats(b).Ragdoll) or "?",
        power = (function()
            local v = RS:FindFirstChild("CurrentPower")
            return v and tostring(v.Value) or "-"
        end)(),
    }
end

local function diff(a, b)
    local d = {}
    for k, v in pairs(a) do
        if tostring(b[k]) ~= tostring(v) then
            table.insert(d, string.format("%s: %s -> %s", k, tostring(v), tostring(b[k])))
        end
    end
    return table.concat(d, " | ")
end

-- =====================================================================
-- 3) TESTE: dispara um input e ve se mudou algo
-- =====================================================================
local function fireInput(remoteName, a, b)
    for _, r in ipairs(remotes) do
        if r.Name == remoteName then
            pcall(function()
                if b ~= nil then
                    r:FireServer(a, b)
                elseif a ~= nil then
                    r:FireServer(a)
                else
                    r:FireServer()
                end
            end)
            return true
        end
    end
    return false
end

-- A lista de candidatos e so o que o JOGO usa + palpites. O teste mede.
local CANDIDATOS = {
    { name = "Input", args = { "Action", true },   label = "Action" },
    { name = "Input", args = { "Crawl", true },    label = "Crawl" },
    { name = "Input", args = { "Stun", true },    label = "Stun" },
    { name = "Input", args = { "Slow", true },    label = "Slow" },
    { name = "Input", args = { "Roar", true },    label = "Roar" },
    { name = "Input", args = { "Untie", true },   label = "Untie" },
    { name = "Input", args = { "Freeze", true },  label = "Freeze" },
    { name = "Input", args = { "Revive", true },  label = "Revive" },
    { name = "Input", args = { "Heal", true },    label = "Heal" },
    { name = "Input", args = { "Seer", true },    label = "Seer" },
    { name = "Input", args = { "Invisible", true }, label = "Invisible" },
    { name = "Input", args = { "SlowAll", true }, label = "SlowAll" },
    { name = "Input", args = { "Speed", true },   label = "Speed" },
    { name = "SetPlayerMinigameResult", args = { true }, label = "MinigameResult" },
}

local function testOne(cand)
    local before = snapshot()
    local ok = false
    if #cand.args == 1 then
        ok = fireInput(cand.name, cand.args[1])
    elseif #cand.args == 2 then
        ok = fireInput(cand.name, cand.args[1], cand.args[2])
    end
    if not ok then
        return false, "remote '" .. cand.name .. "' nao encontrado"
    end
    task.wait(1.4)
    local after = snapshot()
    local d = diff(before, after)
    if d ~= "" then
        return true, cand.label .. " -> MUDOU: " .. d
    end
    return false, cand.label .. " -> sem diferenca visivel"
end

local function runAllTests()
    scanRemotes()
    log("=== REMOTES: " .. remoteNames() .. " ===")
    log("=== TESTANDO CANDIDATOS (voce e " .. (getStats(LP) and getStats(LP).IsBeast or "?") .. ") ===")
    for _, cand in ipairs(CANDIDATOS) do
        local mudou, msg = testOne(cand)
        if mudou then
            log(">>> ACHOU! " .. msg)
        else
            log("    " .. msg)
        end
    end
    log("=== FIM ===")
    log("Copie as linhas '>>> ACHOU!' e me mande no chat.")
end

-- =====================================================================
-- 4) PAINEL SIMPLES NA TELA
-- =====================================================================
local function buildGui()
    local screen = Instance.new("ScreenGui")
    screen.Name = "mpX_Probe"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() screen.Parent = LP:WaitForChild("PlayerGui") end)

    local function mkFrame(size, pos)
        local f = Instance.new("Frame")
        f.Size = size
        f.Position = pos
        f.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
        f.BackgroundTransparency = 0.15
        f.BorderSizePixel = 0
        f.Parent = screen
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = f
        return f
    end

    local main = mkFrame(UDim2.fromOffset(360, 300), UDim2.fromOffset(10, 60))

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0), UDim2.fromOffset(0, 26)
    title.Position = UDim2.fromOffset(0, 4)
    title.BackgroundTransparency = 1
    title.Text = "PROBE FTF - achando funcoes do servidor"
    title.TextColor3 = Color3.fromRGB(255, 220, 90)
    title.TextSize = 15
    title.Font = Enum.Font.GothamBold
    title.Parent = main

    local box = Instance.new("ScrollingFrame")
    box.Size = UDim2.new(1, -16, 1, -74)
    box.Position = UDim2.fromOffset(8, 34)
    box.BackgroundTransparency = 1
    box.ScrollBarThickness = 4
    box.CanvasSize = UDim2.new(0, 0)
    box.AutomaticCanvasSize = Enum.AutomaticSize.Y
    box.Parent = main

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.Parent = box

    local function addButton(text, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 30)
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 240)
        b.TextSize = 14
        b.Font = Enum.Font.Gotham
        b.Parent = box
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = b
        b.MouseButton1Click:Connect(function() cb() end)
        return b
    end

    addButton("1) Escanear remotes", function()
        scanRemotes()
        log("Remotes: " .. remoteNames())
    end)

    addButton("2) Testar TODOS candidatos", function()
        runAllTests()
    end)

    addButton("3) Sou beast agora? (checa)", function()
        local s = getStats(LP)
        log("Voce IsBeast=" .. tostring(s and s.IsBeast) .. " Poder=" .. tostring(s and s.Power))
    end)

    addButton("4) Copiar log (print)", function()
        print(table.concat(out, "\n"))
        Notify("Log impresso no console (F9). Copie e cole aqui.")
    end)

    addButton("Fechar painel", function() screen:Destroy() end)

    log("Painel aberto. Clique em 2) Testar TODOS candidatos.")
    Notify("PROBE pronto! Clique em 'Testar TODOS candidatos'.")
end

local function Notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "mpX Probe",
            Text = msg,
            Duration = 4,
        })
    end)
end

-- =====================================================================
-- 5) INICIO
-- =====================================================================
scanRemotes()
buildGui()
log("Remotes inicial: " .. remoteNames())