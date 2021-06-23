#include "scripts/desintegrator.lua"
#include "scripts/utility.lua"


-- db = false
db = true


function init()
    initDesintegrator()
    initSounds()

    globalBody = FindBodies('', true)[1]
end


function tick()

    shootDesintegrator()
    desintegrateShapes()

    desin.manageMode()
    if db then DebugWatch('Desin mode', desin.mode) end

    desin.manageIsDesintegrating()
    if db then DebugWatch('desin.isDesintegrating', desin.isDesintegrating) end

    desin.manageColor()

    desin.manageOutline()

end


function initDesintegrator()

    desin = {}

    desin.setup = {
        name = 'desintegrator',
        title = 'Desintegrator',
        voxPath = 'MOD/vox/desintegrator.vox',
    }

    desin.active = function()
        return GetString('game.player.tool') == desin.setup.name and GetPlayerVehicle() == 0
    end

    desin.input = {
        didSelect = function() return InputPressed('lmb') and desin.active() end,
        didToggleDesintegrate = function() return InputPressed('rmb') and desin.active() end,
        didReset = function() return InputPressed('r') and desin.active() end,
        didChangeMode = function() return InputPressed('c') and desin.active() end,
    }

    desin.initTool = function(enabled)
        RegisterTool(desin.setup.name, desin.setup.title, desin.setup.voxPath)
        SetBool('game.tool.'..desin.setup.name..'.enabled', enabled or true)
    end

    -- Init
    desin.initTool()



    desin.objects = {}
    desinObjectMetatable = buildDesinObject(nil)



    desin.isDesintegrating = false

    desin.manageIsDesintegrating = function()
        if desin.input.didToggleDesintegrate() then
            desin.isDesintegrating = not desin.isDesintegrating

            if desin.isDesintegrating then
                PlaySound(sounds.b6, GetPlayerTransform().pos, 0.75)
            else
                PlaySound(sounds.b5, GetPlayerTransform().pos, 0.75)
            end

        end
    end



    desin.colors = {
        desintegrating = Vec(0,1,0.6),
        notDesintegrating = Vec(0.6,1,0)
    }

    desin.color = desin.colors.notDesintegrating

    desin.manageColor = function()
        if desin.isDesintegrating then
            desin.color = desin.colors.desintegrating
            return
        end
        desin.color = desin.colors.notDesintegrating
    end



    desin.manageOutline = function()
        local c = desin.color
        for i = 1, #desin.objects do
            DrawShapeOutline(desin.objects[i].shape, c[1], c[2], c[3], 1)
        end
    end



    desin.modes = {
        specific = 'specific', -- shapes
        general = 'general', -- bodies
        -- autoSpread = 'autoSpread', -- bodies
    }

    desin.mode = desin.modes.specific

    desin.manageMode = function()
        if desin.input.didChangeMode() then
            beep()
            if desin.mode == desin.modes.specific then
                desin.mode = desin.modes.general
            else
                desin.mode = desin.modes.specific
            end
        end
    end



    desin.insert = {}

    desin.insert.shape = function(shape)
        local desinObject = buildDesinObject(shape) -- Insert valid desin object.
        setmetatable(desinObject, desinObjectMetatable)
        table.insert(desin.objects, desinObject)
        if db then DebugPrint('Shape added ' .. sfnTime()) end
    end

    desin.insert.processShape = function(shape)

        local shapeIsValid = true -- Choose whether to add raycasted object to desin.objects.

        for i = 1, #desin.objects do -- Check if shape is already in desin.objects.

            if shape == desin.objects[i].shape then

                shapeIsValid = false
                desin.remove.shape(desin.objects[i].shape) -- Remove shape.

                PlaySound(sounds.b5, GetPlayerTransform().pos)

                if db then DebugPrint('Shape invalid' .. sfnTime()) end
                break -- Reject invalid desin object.
            end

        end

        if shapeIsValid then
            desin.insert.shape(shape)
            PlaySound(sounds.b1, GetPlayerTransform().pos)
        end
    end

    desin.insert.body = function(shape, body)
        local bodyIsValid = body ~= globalBody

        if bodyIsValid then

            local bodyShapes = GetBodyShapes(body)
            for i = 1, #bodyShapes do
                desin.insert.processShape(bodyShapes[i])
            end

        else
            desin.insert.processShape(shape) -- Insert hit shape by default regardless of body shapes.
        end
    end


    desin.remove = {}
    desin.remove.shape = function(shape)
        for i = 1, #desin.objects do
            if desin.objects[i].shape == shape then
                table.remove(desin.objects, i)
            end
        end
    end

end


function shootDesintegrator()

    if desin.input.didSelect() then -- desin shoot

        local camTr = GetCameraTransform()
        local hit, hitPos, hitShape, hitBody = RaycastFromTransform(camTr, 200)
        if hit then

            if desin.mode == desin.modes.specific then

                desin.insert.processShape(hitShape)

            elseif desin.mode == desin.modes.general then

                desin.insert.body(hitShape, hitBody)

            -- elseif desin.mode == desin.modes.autoSpread then
            end

        end

    elseif desin.input.didReset() then -- desin reset

        desin.objects = {}
        desin.isDesintegrating = false
        PlaySound(sounds.b3, GetPlayerTransform().pos, 1)
        if db then DebugWatch('Desin objects reset', sfnTime()) end

    end

end


function initSounds()
    sounds = {
        zaps = {
            LoadSound("snd/zap1.ogg"),
            LoadSound("snd/zap2.ogg"),
            LoadSound("snd/zap3.ogg"),
            LoadSound("snd/zap4.ogg"),
            LoadSound("snd/zap5.ogg"),
            LoadSound("snd/zap6.ogg"),
            LoadSound("snd/zap7.ogg"),
        },
        s1 = LoadSound("snd/positive1.ogg"),
        s2 = LoadSound("snd/positive2.ogg"),
        s3 = LoadSound("snd/end.ogg"),
        s4 = LoadSound("snd/complete.ogg"),

        b1 = LoadSound("snd/b1.ogg"),
        b2 = LoadSound("snd/b2.ogg"),
        b3 = LoadSound("snd/b3.ogg"),
        b4 = LoadSound("snd/b4.ogg"),
        b5 = LoadSound("snd/b5.ogg"),
        b6 = LoadSound("snd/b6.ogg"),
        b7 = LoadSound("snd/b7.ogg"),

    }

    loops = {
        desinLoop = LoadLoop("snd/desinLoop.ogg"),
    }

    sounds.play = {
        zap = function (pos, vol)
            sounds.playRandom(sounds.zaps, pos, vol or 1)
        end,
    }

    sounds.playRandom = function(soundsTable, pos, vol)
        local sound = math.floor(soundsTable[rdm(1, #soundsTable)])
        PlaySound(sound, pos, vol or 1)
    end
end


function draw()

    -- Draw dots at hit positions.
    if desin.isDesintegrating then
        for i = 1, #desin.objects do
            for j = 1, #desin.objects[i].hit.positions do
                DrawDot(
                    desin.objects[i].hit.positions[j],
                    math.random()/5,
                    math.random()/5,
                    desin.colors.desintegrating[1],
                    desin.colors.desintegrating[2],
                    desin.colors.desintegrating[3],
                    math.random()/2 + 0.4
                )
            end
        end
    end

    -- Draw desin.mode text
    if desin.active() then
        UiPush()
            UiTranslate(UiCenter(), UiMiddle() + 450)
            UiColor(1,1,1,1)
            UiFont('bold.ttf', 32)
            UiAlign('center middle')
            -- UiText('Mode: ' .. desin.mode)
            UiTextShadow(0,0,0,0.8,2,0.2)
            UiText('Mode: ' .. desin.mode)
        UiPop()
    end

end