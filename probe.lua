--[[
    mpX PROBE v2 - FTF Recon
    Descobre o que o servidor do FTF aceita (Slow Beast, Untie, Anti Seer...).

    USAR (dentro do FTF, no executor):
      loadstring(game:HttpGet("https://raw.githubusercontent.com/paulo123ld/mpX-Publics/main/probe.lua"))()

    O QUE MUDOU NA v2:
      - O remote real se chama "RemoteEvent"; "Input" e o PRIMEIRO ARGUMENTO
        (RemoteEvent:FireServer("Input", "Action", true)). A v2 procurava um
        remote chamado "Input" e por isso nao achava nada.
      - Monitor: loga TODA mudanca de estado de qualquer jogador
        (Beast/Idle/None/Typing/Carry, Ragdoll, IsCrawling, WalkSpeed).
        Se voce clicar num teste e aparecer uma linha nova aqui, achou.
      - Testa tambem os outros remotes do jogo (Status/SystemMessage/etc).
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local out = {}
local function log(msg)
    msg = tostring(msg)
    table.insert(out, msg)
    print("[PROBE] " .. msg)
end

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "mpX Probe",
            Text = tostring(msg),
            Duration = 4,
        })
    end)
end

-- =====================================================================
-- REMOTES
-- =====================================================================
local function scanRemotes()
    local list = {}
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            table.insert(list, obj)
        end
    end
    return list
end

local remotes = scanRemotes()

local function remoteByName(nome)
    for _, r in ipairs(remotes) do
        if r.Name == nome then return r end
    end
    return nil
end

local RE = remoteByName("RemoteEvent") -- remote principal do FTF

-- =====================================================================
-- LEITURA DE ESTADO (o que o jogo prints no console: Beast/Idle/None...)
-- =====================================================================
local VALS = {
    BoolValue = true, StringValue = true, IntValue = true, NumberValue = true,
}

local function statsOf(plr)
    local m = plr and plr:FindFirstChild("TempPlayerStatsModule")
    if not m then return {} end
    local t = {}
    for _, c in ipairs(m:GetChildren()) do
        if VALS[c.ClassName] then t[c.Name] = tostring(c.Value) end
    end
    return t
end

local function wsOf(plr)
    local ch = plr and plr.Character
    local h = ch and ch:FindFirstChild("Humanoid")
    return h and math.floor(h.WalkSpeed) or -1
end

-- assinatura curta de um jogador (o que muda quando algo acontece)
-- ATENCAO: CurrentAnimation fica oscilando (Typing <-> vazio) quando OUTRO
-- jogador digita no PC. Isso gera falso positivo. Por isso aqui a gente
-- ignora CurrentAnimation e foca nos campos que o servidor controla de verdade:
-- NormalWalkSpeed (velocidade oficial), ActionProgress, IsBeast, IsCrawling.
local function sigOf(plr)
    local s = statsOf(plr)
    local parts = {
        s.Beast or s.IsBeast or "?",
        "nws" .. tostring(s.NormalWalkSpeed or "?"),
        "ap" .. tostring(s.ActionProgress or "?"),
        "ai" .. tostring(s.ActionInput or "?"),
        s.Capture or s.Captured or "?",
        s.Rag or s.Ragdoll or "?",
        s.Crawl or s.IsCrawling or "?",
        s.WasHitDownOnce or "?",
        s.Escaped or "?",
        "ws" .. tostring(wsOf(plr)),
    }
    return table.concat(parts, "/")
end

local function sigDeTodos()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(t, p.Name .. "=" .. sigOf(p))
    end
    table.sort(t)
    return table.concat(t, "  ")
end

-- =====================================================================
-- MONITOR: loga qualquer mudanca de estado (o detector mais importante)
-- =====================================================================
local monitorOn = false
local ultimo = {}

local function ligarMonitor()
    if monitorOn then return end
    monitorOn = true
    log(">>> MONITOR LIGADO (mudancas de estado vao aparecer aqui)")
    task.spawn(function()
        while monitorOn do
            local mudou = false
            for _, p in ipairs(Players:GetPlayers()) do
                local s = sigOf(p)
                if ultimo[p.Name] and ultimo[p.Name] ~= s then
                    log("MUDOU " .. p.Name .. ": " .. ultimo[p.Name] .. "  ->  " .. s)
                    mudou = true
                end
                ultimo[p.Name] = s
            end
            task.wait(0.25)
        end
        log(">>> MONITOR DESLIGADO")
    end)
end

local function desligarMonitor()
    monitorOn = false
    ultimo = {}
end

-- =====================================================================
-- TESTES
-- =====================================================================
local function estadoAntes()
    return sigDeTodos()
end

local function testar(nome, fn)
    if not RE then
        log("Sem o remote principal (RemoteEvent).")
        return
    end
    local antes = estadoAntes()
    log("---- TESTANDO: " .. nome)
    local ok = pcall(fn)
    if not ok then
        log("   (falhou ao disparar: " .. nome .. ")")
        return
    end
    task.wait(1.6)
    local depois = estadoAntes()
    if antes ~= depois then
        log(">>> ACHOU! " .. nome .. " mudou o estado:")
        log("    antes : " .. antes)
        log("    depois: " .. depois)
    else
        log("    sem diferenca: " .. nome)
    end
end

-- Comandos que a gente suspeita (o jogo usa "Action", "Crawl", "Trigger"...)
local COMANDOS = {
    "Stun", "Slow", "SlowBeast", "SlowAll", "Roar", "Untie", "UntieAll",
    "Freeze", "Revive", "Heal", "Seer", "Invisible", "Hide", "Speed",
    "Grab", "Throw", "Charge", "Dash", "Lunge", "Hypnosis", "Trap",
    "Sprint", "Teleport", "Kill", "Damage", "Confuse", "Blind", "Drain",
}

local function testesAutomaticos()
    log("=== RODANDO " .. #COMANDOS .. " COMANDOS (voce e " .. tostring((statsOf(LocalPlayer).Beast or statsOf(LocalPlayer).IsBeast)) .. ") ===")
    ligarMonitor()
    task.wait(1)
    for _, cmd in ipairs(COMANDOS) do
        testar("Input/" .. cmd, function()
            RE:FireServer("Input", cmd, true)
        end)
    end
    log("=== FIM. Se aparecer '>>> ACHOU!' ou 'MUDOU', copie e mande. ===")
end

local function testesComArgumentos()
    -- alguns comandos podem querer numero/jogador, nao so true
    log("=== TESTANDO COM NUMEROS ===")
    ligarMonitor()
    for _, cmd in ipairs({ "Stun", "Slow", "Untie", "Revive", "Heal" }) do
        for _, v in ipairs({ 1, 5, 10 }) do
            testar(string.format("Input/%s=%d", cmd, v), function()
                RE:FireServer("Input", cmd, v)
            end)
        end
    end
    log("=== FIM ===")
end

local function testesOutrosRemotes()
    log("=== TESTANDO OUTROS REMOTES ===")
    for _, r in ipairs(remotes) do
        if r.Name ~= "RemoteEvent" then
            testar(r.Name .. " (string)", function()
                r:FireServer("mpX")
            end)
        end
    end
    log("=== FIM ===")
end

-- funcao beast mais proximo (para盯着 NormalWalkSpeed, que e o campo do servidor)
local function beastAlvo()
    local best, bd
    local meu = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    for _, p in ipairs(Players:GetPlayers()) do
        local s = statsOf(p)
        local ehBeast = (s.Beast == "true") or (s.IsBeast == "true")
        if ehBeast and p ~= LocalPlayer then
            local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if r and meu then
                local d = (r.Position - meu.Position).Magnitude
                if not bd or d < bd then best, bd = p, d end
            elseif not best then
                best = p
            end
        end
    end
    return best
end

local function nwsDe(plr)
    return tostring(statsOf(plr).NormalWalkSpeed or "?")
end

-- TESTE DIRETO DO "SLOW BEAST": manda comandos com o nome/objeto do jogador
local function testeSlowBeast()
    local alvo = beastAlvo()
    if not alvo then log("Nenhuma beast encontrada agora ( rode quando ela existir )") return end
    log("Alvo: " .. alvo.Name .. " | NormalWalkSpeed agora = " .. nwsDe(alvo))
    local nome = alvo.Name
    local display = alvo.DisplayName

    local testes = {
        { rot = "Input/Slow + true",      fn = function() RE:FireServer("Input", "Slow", true) end },
        { rot = "Input/Slow + nome",      fn = function() RE:FireServer("Input", "Slow", nome) end },
        { rot = "Input/Slow + display",   fn = function() RE:FireServer("Input", "Slow", display) end },
        { rot = "Input/SlowBeast + nome", fn = function() RE:FireServer("Input", "SlowBeast", nome) end },
        { rot = "Input/SlowPlayer + nome",fn = function() RE:FireServer("Input", "SlowPlayer", nome) end },
        { rot = "Input/SetSpeed + 5",     fn = function() RE:FireServer("Input", "SetSpeed", 5) end },
        { rot = "Input/SlowDown + nome",  fn = function() RE:FireServer("Input", "SlowDown", nome) end },
        { rot = "Input/Freeze + nome",    fn = function() RE:FireServer("Input", "Freeze", nome) end },
        { rot = "Input/Stun + nome",      fn = function() RE:FireServer("Input", "Stun", nome) end },
        { rot = "Input/Untie + nome",     fn = function() RE:FireServer("Input", "Untie", nome) end },
        { rot = "Input/Revive + nome",    fn = function() RE:FireServer("Input", "Revive", nome) end },
        { rot = "Input/Seer + true",      fn = function() RE:FireServer("Input", "Seer", true) end },
    }

    for _, t in ipairs(testes) do
        local antes = nwsDe(alvo)
        pcall(t.fn)
        task.wait(1.5)
        local depois = nwsDe(alvo)
        if antes ~= depois then
            log(">>> ACHOU! " .. t.rot .. " -> NormalWalkSpeed " .. antes .. " -> " .. depois)
        else
            log("    sem efeito: " .. t.rot .. " (nws " .. antes .. ")")
        end
    end
    log("=== FIM DO TESTE SLOW BEAST ===")
end

-- testa os outros remotes do jogo com payloads diferentes
local function testeOutrosRemotes()
    local payloads = {
        { "Slow", true }, { "Stun", true }, { "Kill", true }, { "SlowBeast", true },
    }
    for _, r in ipairs(remotes) do
        if r.Name ~= "RemoteEvent" then
            for _, pl in ipairs(payloads) do
                local ok = pcall(function() r:FireServer(pl[1], pl[2]) end)
                if ok then task.wait(0.4) end
            end
            log("disparado: " .. r.Name)
        end
    end
    log("=== FIM OUTROS REMOTES ===")
end
-- LEITOR DE TIMING: ficar olhando os campos do minigame enquanto hackeia.
-- Se TimingGoalPosition/TimingPinPosition preencherem, achamos o "acerto perfeito".
local function lerTiming()
    local s = statsOf(LocalPlayer)
    log(string.format("TIMING goal=%s pin=%s prog=%s input=%s pct=%s mini=%s anim=%s",
        tostring(s.TimingGoalPosition), tostring(s.TimingPinPosition),
        tostring(s.ActionProgress), tostring(s.ActionInput),
        tostring(s.ShowActionPercent), tostring(s.MinigameResult),
        tostring(s.CurrentAnimation)))
end

local function monitorTiming(segundos)
    local fim = os.clock() + (segundos or 20)
    local n, comDados = 0, 0
    log("=== MONITOR DE TIMING por " .. tostring(segundos or 20) .. "s (hackeia um PC agora) ===")
    while os.clock() < fim do
        local s = statsOf(LocalPlayer)
        local g = tonumber(s.TimingGoalPosition) or 0
        local p = tonumber(s.TimingPinPosition) or 0
        if g ~= 0 or p ~= 0 then
            comDados = comDados + 1
            log(string.format("  DADOS! goal=%s pin=%s prog=%s input=%s", tostring(g), tostring(p), tostring(s.ActionProgress), tostring(s.ActionInput)))
        end
        n = n + 1
        task.wait(0.05)
    end
    log("=== FIM: " .. n .. " amostras, " .. comDados .. " com timing preenchido ===")
    if comDados == 0 then
        log("O servidor NAO preenche TimingGoalPosition/TimingPinPosition (ficam 0).")
        log("Se Their were 0 o tempo todo, o timing so existe dentro do cliente do jogo.")
    end
end
-- ATAQUE DE TIMING: o servidor manda TimingGoalPosition (o alvo) e espera o
-- cliente reportar TimingPinPosition (a agulha). O pin fica 0 -> o hack trava
-- em ~90%. Aqui a gente tenta descobrir QUAL payload faz o servidor aceitar.
local function timingState()
    local s = statsOf(LocalPlayer)
    return {
        goal = tonumber(s.TimingGoalPosition) or 0,
        pin = tonumber(s.TimingPinPosition) or 0,
        prog = tonumber(s.ActionProgress) or 0,
        mini = tostring(s.MinigameResult),
        pct = tostring(s.ShowActionPercent),
    }
end

local function ataqueTiming(esperarSegundos)
    log("=== ESPERANDO O MINIGAME COMECAR (ate " .. tostring(esperarSegundos or 30) .. "s) ===")
    log("Voce precisa estar hackeando um PC. Deixa o hack rolando sozinho.")
    local fim = os.clock() + (esperarSegundos or 30)
    local achou = false
    while os.clock() < fim do
        local st = timingState()
        if st.goal ~= 0 then
            achou = true
            log(">>> MINIGAME ATIVO! goal=" .. tostring(st.goal) .. " pin=" .. tostring(st.pin) .. " prog=" .. tostring(st.prog))
            break
        end
        task.wait(0.05)
    end
    if not achou then
        log("O minigame nao ativou (goal ficou 0). Tenta de novo com o Auto Hack ligado.")
        return
    end

    -- payload = { rotulo, funcao que dispara }
    local payloads = {
        { rot = "SetPlayerMinigameResult(goal)",   fn = function(g) RE:FireServer("SetPlayerMinigameResult", g) end },
        { rot = "SetPlayerMinigameResult(true,g)",fn = function(g) RE:FireServer("SetPlayerMinigameResult", true, g) end },
        { rot = "SetPlayerMinigameResult(true,g,g)", fn = function(g) RE:FireServer("SetPlayerMinigameResult", true, g, g) end },
        { rot = "SetPlayerTiming(g)",             fn = function(g) RE:FireServer("SetPlayerTiming", g) end },
        { rot = "SetPlayerPin(g)",                fn = function(g) RE:FireServer("SetPlayerPin", g) end },
        { rot = "SetTiming(g,g)",                  fn = function(g) RE:FireServer("SetTiming", g, g) end },
        { rot = "Input/Timing(g)",                fn = function(g) RE:FireServer("Input", "Timing", g) end },
        { rot = "SetPlayerTimingPin(g)",          fn = function(g) RE:FireServer("SetPlayerTimingPin", g) end },
    }

    for _, p in ipairs(payloads) do
        local st0 = timingState()
        local g = st0.goal
        if g == 0 then g = 1 end
        local ok = pcall(p.fn, g)
        task.wait(0.5)
        local st1 = timingState()
        local mudou = (st1.pin ~= st0.pin) or (st1.mini ~= st0.mini) or (st1.prog > st0.prog + 0.01)
        log(string.format("   %s -> pin %s->%s | prog %s->%s | mini %s->%s %s",
            p.rot, tostring(st0.pin), tostring(st1.pin),
            tostring(st0.prog), tostring(st1.prog),
            st0.mini, st1.mini, mudou and "  <<< MUDOU!" or ""))
        if st1.pin ~= 0 then
            log(">>> ACHOU! O payload '" .. p.rot .. "' fez o servidor aceitar o pin!")
        end
    end
    log("=== FIM DO ATAQUE DE TIMING ===")
end
local function mostrarRemotes()
    local nomes = {}
    for _, r in ipairs(remotes) do
        table.insert(nomes, r.Name .. " (" .. r.ClassName .. ")")
    end
    table.sort(nomes)
    log("REMOTES: " .. table.concat(nomes, ", "))
    notify("Remotes listados no console")
end

local function espelharEstado()
    log("ESTADO AGORA:")
    for _, p in ipairs(Players:GetPlayers()) do
        local s = statsOf(p)
        local linhas = {}
        for k, v in pairs(s) do table.insert(linhas, k .. "=" .. v) end
        table.sort(linhas)
        log("  " .. p.Name .. " | ws=" .. tostring(wsOf(p)) .. " | " .. table.concat(linhas, " "))
    end
end

-- =====================================================================
-- PAINEL
-- =====================================================================
local function buildGui()
    local screen = Instance.new("ScreenGui")
    screen.Name = "mpX_Probe"
    screen.ResetOnSpawn = false
    pcall(function() screen.Parent = LocalPlayer:WaitForChild("PlayerGui") end)

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(340, 430)
    main.Position = UDim2.fromOffset(10, 50)
    main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    main.BackgroundTransparency = 0.1
    main.BorderSizePixel = 0
    main.Parent = screen
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 26)
    title.BackgroundTransparency = 1
    title.Text = "PROBE v2 - funcoes do servidor"
    title.TextColor3 = Color3.fromRGB(255, 215, 80)
    title.TextSize = 15
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = main

    local box = Instance.new("ScrollingFrame")
    box.Size = UDim2.new(1, -14, 1, -70)
    box.Position = UDim2.fromOffset(7, 30)
    box.BackgroundTransparency = 1
    box.ScrollBarThickness = 4
    box.AutomaticCanvasSize = Enum.AutomaticSize.Y
    box.Parent = main
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 4)
    lay.Parent = box

    local function botao(text, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 30)
        b.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 240)
        b.TextSize = 13
        b.Font = Enum.Font.Gotham
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Parent = box
        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(0, 6)
        cc.Parent = b
        b.MouseButton1Click:Connect(function()
            pcall(function() cb() end)
        end)
        return b
    end

    botao("1) Listar remotes", mostrarRemotes)
    botao("2) LIGAR MONITOR (recomendado)", ligarMonitor)
    botao("3) Rodar todos os comandos", testesAutomaticos)
    botao("4) Testar com numeros", testesComArgumentos)
    botao("5) Testar outros remotes", testesOutrosRemotes)
    botao("8) TESTE DIRETO: Slow Beast", testeSlowBeast)
    botao("C) ATAQUE DE TIMING (testa payloads)", function() ataqueTiming(40) end)
    botao("A) Ler timing agora (1x)", lerTiming)
    botao("B) Monitorar timing 20s", function() monitorTiming(20) end)
    botao("6) Mostrar estado de todos", espelharEstado)
    botao("9) Disparar outros remotes", testeOutrosRemotes)
    botao("7) Imprimir log no console", function()
        print("[PROBE-LOG]\n" .. table.concat(out, "\n"))
        notify("Log impresso (F9)")
    end)
    botao("Fechar", function() screen:Destroy() end)

    log("Painel v2 pronto. Comece por 1) e 2), depois 3).")
    notify("PROBE v2 pronto! Faca 1), 2) e 3).")
end

buildGui()
mostrarRemotes()