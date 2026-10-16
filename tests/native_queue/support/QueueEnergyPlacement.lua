return function(player)
    local origin=player:getCurrentSquare()
    for radius=2,12 do
        for dx=-radius,radius do for dy=-radius,radius do
            if math.abs(dx)==radius or math.abs(dy)==radius then
                local x,y,z=origin:getX()+dx,origin:getY()+dy,origin:getZ()
                local clear=true
                for a=-1,1 do for b=-1,1 do
                    local sq=getCell():getGridSquare(x+a,y+b,z)
                    if not sq or not sq:isFree(false) or sq:getRoom() or sq:getObjects():size()>1 then clear=false end
                end end
                if clear then
                    player:teleportTo(x+0.5,y+0.5,z)
                    print('[QUEUE_TEST] ENERGY_PLACEMENT '..x..','..y..','..z)
                    return getCell():getGridSquare(x,y,z)
                end
            end
        end end
    end
    error('No clear loaded 3x3 native energy fixture area')
end
