function math.Clamp(inval, minval, maxval)
	if (inval < minval) then return minval end
	if (inval > maxval) then return maxval end
	return inval
end

do

    local math_random = math.random
    local table_GetKeys = table.GetKeys
    function table.Random( tab, issequential )
        local keys = issequential and tab or table_GetKeys(tab)
        local rand = keys[math_random(1, #keys)]
        return tab[rand], rand
    end

end

MsgN( "Random Patches - Game Patched!" )