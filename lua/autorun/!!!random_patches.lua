function math.Clamp(inval, minval, maxval)
	if (inval < minval) then return minval end
	if (inval > maxval) then return maxval end
	return inval
end