#include "scripts/desintegrator.lua"
#include "scripts/utility.lua"
#include "scripts/info.lua"


-- (Debug mode)
db = false
db = true
dbw = function(name, value) if db then DebugWatch(name, value) end end
dbp = function(str) if db then DebugPrint(str) end end


function init()
    initDesintegrator()
    initSounds()
    initInfo()

    updateGameTable()
    globalBody = FindBodies('', true)[1]
end


function tick()

    if GetBool('savegame.mod.info.neverShow') or info.closed then -- info.lua

        updateGameTable()

        shootDesintegrator()
        desintegrateShapes()

        desin.manageMode()
        dbw('Desin mode', desin.mode)

        desin.manageIsDesintegrating()
        dbw('desin.isDesintegrating', desin.isDesintegrating)

        desin.manageObjectRemoval()

        desin.manageColor()
        desin.manageOutline()
        desin.manageToolAnimation()

    end

end


function initDesintegrator()

    desin = {}

    desin.setup = {
        name = 'desintegrator',
        title = 'Desintegrator',
        voxPath = 'MOD/vox/desintegrator.vox',
    }

    desin.active = function(includeVehicle) -- Player is wielding the desintegrator.
        return GetString('game.player.tool') == desin.setup.name 
            and (GetPlayerVehicle() == 0 and (includeVehicle or true))
    end

    desin.input = {
        didSelect = function() return InputPressed('lmb') and desin.active() end,
        didToggleDesintegrate = function() return InputPressed('rmb') and desin.active() end,
        didReset = function() return InputPressed('r') and desin.active() end,
        didChangeMode = function() return InputPressed('c') and desin.active() end,
        didUndo = function() return InputPressed('z') and desin.active() end,
    }

    desin.initTool = function(enabled)
        RegisterTool(desin.setup.name, desin.setup.title, desin.setup.voxPath)
        SetBool('game.tool.'..desin.setup.name..'.enabled', enabled or true)
    end

    -- Init
    desin.initTool()



    desin.objects = {}
    desinObjectMetatable = buildDesinObject(nil)


    desin.properties = {
        maxShapeVoxels = 50000,
    }


    desin.isDesintegrating = false
    desin.manageIsDesintegrating = function()
        if desin.input.didToggleDesintegrate() then
            desin.isDesintegrating = not desin.isDesintegrating

            if desin.isDesintegrating then
                sound.ui.activate()
            else
                sound.ui.deactivate()
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

        local isDesin = desin.isDesintegrating

        local c = desin.color
        local a = 1
        if isDesin then a = 0.5 end

        for i = 1, #desin.objects do
            local shape = desin.objects[i].shape
            DrawShapeOutline(shape, c[1], c[2], c[3], a)
        end
    end



    desin.modes = {
        specific = 'specific', -- shapes
        general = 'general', -- bodies
        -- autoSpread = 'autoSpread', -- bodies
    }
    desin.mode = desin.modes.general
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
        dbp('Shape added ' .. sfnTime())
    end



    desin.insert.processShape = function(shape)

        local shapeBody = GetShapeBody(shape)
        local shapeWillInsert = true

        for i = 1, #desin.objects do

            if shape == desin.objects[i].shape then -- Check if shape is in desin.objects.

                shapeWillInsert = false -- Remove shape that's already in desin.objects.

                if desin.mode == desin.modes.general then -- Desin mode general. Remove all shapes in body.

                    -- if shapeBody == globalBody then -- Not global body.
                    --     desin.setObjectToBeRemoved(desin.objects[i])
                    -- else
                        local bodyShapes = GetBodyShapes(shapeBody)
                        dbp('#bodyShapes ' .. #bodyShapes)

                        for j = 1, #bodyShapes do
                            for k = 1, #desin.objects do -- Compare body shapes to desin.objects shapes.

                                if bodyShapes[j] == desin.objects[k].shape then -- Body shape is in desin.objects.
                                    desin.setObjectToBeRemoved(desin.objects[k]) -- Mark shape for removal
                                    dbp('Man removed body shape ' .. sfnTime())
                                end

                            end
                        end
                    -- end

                elseif desin.mode == desin.modes.specific then -- Remove single shape.

                    desin.setObjectToBeRemoved(desin.objects[i])
                    dbp('Man removed shape ' .. sfnTime())

                end

            end

        end


        -- Check shape not oversized.
        if GetShapeVoxelCount(shape) > desin.properties.maxShapeVoxels then

            shapeWillInsert = false

            local message = "Object too large! (likely merged with the whole map)"
            desin.message.insert(message, colors.red)

            sound.ui.invalid()
            dbp("Oversized shape rejected. Voxels: " .. GetShapeVoxelCount(shape) .. " ... " .. sfnTime())

        end


        -- Insert valid shape 
        if shapeWillInsert then
            desin.insert.shape(shape)
            sound.ui.insert()
        else
            sound.ui.removeShape()
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


    desin.manageObjectRemoval = function()

        local removeIndexes = {} -- Remove specified desin objects.

        for i = 1, #desin.objects do

            local removeShape = false

            local smallShape = desin.objects[i].functions.isShapeTooSmall()
            local desintegrating = desin.isDesintegrating

            if smallShape and desintegrating then -- Small shape to remove.

                removeShape = true
                desin.objects[i].done = true
                MakeHole(AabbGetShapeCenterPos(desin.objects[i].shape), 0.2, 0.2 ,0.2 ,0.2)
                -- sound.desintegrate.done(AabbGetShapeCenterPos(desin.objects[i].shape))
                dbp('Small shape set for removal ' .. sfnTime())

            end

            if desin.objects[i].remove then -- Cancelled shape to remove.
                removeShape = true
            end

            if removeShape then
                table.insert(removeIndexes, i)
            end

        end

        for i = 1, #removeIndexes do

            local desinObjIndex = removeIndexes[i]
            table.remove(desin.objects, desinObjIndex)

        end

    end
    -- Mark object for removal. Removed in desin.manageObjectRemoval()
    desin.setObjectToBeRemoved = function(desinObject)
        desinObject.remove = true
    end



    desin.undo = function ()

        local lastIndex = #desin.objects
        local lastShape = desin.objects[lastIndex].shape

        if desin.mode == desin.modes.specific then

            desin.setObjectToBeRemoved(desin.objects[lastIndex]) -- Remove last object entry

        elseif desin.mode == desin.modes.general then

            local bodyShapes = GetBodyShapes(GetShapeBody(lastShape))

            for i = 1, #bodyShapes do -- All body shapes.
                for j = 1, #desin.objects do -- Check all body shapes with desin.objects shapes.

                    if bodyShapes[i] == desin.objects[j].shape then -- Body shape is in desin.objects.
                        desin.setObjectToBeRemoved(desin.objects[j]) -- Mark shape for removal
                    end

                end
            end

        end

        sound.ui.removeShape()
    end



    desin.manageToolAnimation = function()

        if desin.active() then

            local toolShapes = GetBodyShapes(GetToolBody())
            local toolPos = Vec(0.6,-0.5,-0.4) -- Base tool pos

            dbw('#toolShapes', #toolShapes)


            local toolUsing = nil
            local toolNotUsing = nil

            if desin.isDesintegrating then 
                toolUsing = toolShapes[1]
                toolNotUsing = toolShapes[2]
            else
                toolUsing = toolShapes[2]
                toolNotUsing = toolShapes[1]
            end


            -- Set tool transforms
            local toolRot = GetShapeLocalTransform(toolShapes[1]).rot

            local toolTr = Transform(toolPos, toolRot)
            SetShapeLocalTransform(toolUsing, toolTr)

            local toolTr = Transform(Vec(0,1000,0), toolRot)
            SetShapeLocalTransform(toolNotUsing, toolTr)

        end

    end



    desin.message = {}

    desin.message.message = nil
    desin.message.color = colors.white
    desin.message.cancelCount = 0

    desin.message.timer = {
        time = 0,
        timeDefault = (60 * GetTimeStep()) * 4, -- * seconds
    }

    desin.message.insert = function(message, color)

        desin.message.timer.time = desin.message.timer.timeDefault -- Reset message timer.
        desin.message.color = color
        desin.message.message = message
        desin.message.cancelCount = 0 -- Reset cancel flag.

    end

    desin.message.drawText = function ()
        UiPush()
            local c = desin.message.color
            UiColor(c[1], c[2], c[3], 1)

            UiTranslate(UiCenter(), UiMiddle()+400)
            UiFont('bold.ttf', 32)
            UiAlign('center middle')
            UiTextShadow(0,0,0,0.8,2,0.2)
            UiText(desin.message.message)
        UiPop()
    end

    desin.message.draw = function()

        if desin.input.didSelect() then
            desin.message.cancelCount = desin.message.cancelCount + 1
        end

        if desin.message.timer.time >= 0 then
            desin.message.timer.time = desin.message.timer.time - GetTimeStep()

            if desin.message.cancelCount > 1 then -- Check if message has been cancelled.

                desin.message.timer.time = 0 -- Remove message if player shoots again.

            else

                desin.message.drawText()

            end
        end

        dbw('desin.message.timer.time', desin.message.timer.time)
    end

end


function shootDesintegrator()

    if desin.input.didSelect() then -- Shoot desin

        local camTr = GetCameraTransform()
        local hit, hitPos, hitShape, hitBody = RaycastFromTransform(camTr)
        if hit then

            local maxVoxels = desin.properties.maxShapeVoxels

            if desin.mode == desin.modes.specific and GetShapeVoxelCount(hitShape) < maxVoxels then

                desin.insert.processShape(hitShape)

            elseif desin.mode == desin.modes.general then

                desin.insert.body(hitShape, hitBody)

            end

        end

    elseif desin.input.didReset() then -- Reset desin

        desin.objects = {}
        desin.isDesintegrating = false

        sound.ui.reset()

        dbw('Desin objects reset', sfnTime())

    elseif desin.input.didUndo() and #desin.objects >= 1 then -- Undo last object insertion (body or shapes)

        desin.undo()

    end

end


function initSounds()
    sounds = {
        insertShape = LoadSound("snd/insertShape.ogg"),
        removeShape = LoadSound("snd/removeShape.ogg"),

        start = LoadSound("snd/start.ogg"),
        cancel = LoadSound("snd/cancel.ogg"),
        reset = LoadSound("snd/reset.ogg"),

        desinEnd = LoadSound("snd/desinEnd.ogg"),

        invalid = LoadSound("snd/invalid.ogg"),
    }

    loops = {
        desinLoop = LoadLoop("snd/desinLoop.ogg"),
    }

    sound = {

        desintegrate = {

            loop = function(pos)
                PlayLoop(loops.desinLoop, pos, 0.6) -- Desintigrate sound.
                PlayLoop(loops.desinLoop, game.ppos, 0.1)
            end,

            done = function(pos)
                PlaySound(sounds.desinEnd, pos, 0.5)
            end,

        },

        ui = {

            insert = function()
                PlaySound(sounds.insertShape, game.ppos, 0.8)
            end,

            removeShape = function()
                PlaySound(sounds.removeShape, game.ppos, 0.9)
            end,

            reset = function ()
                PlaySound(sounds.reset, game.ppos, 1)
            end,

            activate = function ()
                PlaySound(sounds.cancel, game.ppos, 0.25)
            end,

            deactivate = function ()
                PlaySound(sounds.start, game.ppos, 0.2)
            end,

            invalid = function ()
                PlaySound(sounds.invalid, game.ppos, 1)
            end,

        }

    }

end


function draw()

    manageInfoUi()

    desin.message.draw()

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
                    math.random()/2 + 0.3
                )
            end
        end
    end

    -- Draw desin.mode text
    if desin.active() then
        UiPush()
            UiTranslate(UiCenter(), UiMiddle() + 460)
            UiColor(1,1,1,1)
            UiFont('bold.ttf', 32)
            UiAlign('center middle')
            -- UiText('Mode: ' .. desin.mode)
            UiTextShadow(0,0,0,0.8,2,0.2)
            UiText('mode: ' .. desin.mode .. ' (c) ')
        UiPop()
    end

end

function updateGameTable()
    game = { ppos = GetPlayerTransform().pos }
end