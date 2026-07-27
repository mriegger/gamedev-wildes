# Task 002 - Day and Night Cycle w/ Real-Time Shadows

Add a repeating day/night cycle with ten minutes of daylight and ten minutes of night. Sun and moon lighting, sky, subtle ambient color, brightness, and real-time shadow direction must move continuously through sunrise, noon, sunset, and midnight.

This is the schedule:
7PM - 6AM = Night
6AM - 8AM = Sunrise
8AM - 5PM = Daytime
5PM - 7PM = Sundown

Alongside the day and night cycle, we need to add realtime directional shadows that move continuously through sunrise, noon, sunset, and midnight. The shadows should be casted by the sun and the moon and should be soft and smooth but visible. There should be no hard edges or discontinuities in the shadows. Shadows should affect both the player and blocks.

Nights remain playable, with a cool low light instead of black terrain. The clock advances only during active play. A new world starts at sunrise.

Mining and placement immediately use the current lighting. Keep ambient occlusion and existing ganmeplay unchanged, avoid lighting jumps, double shadows, flicker, washed colors, or visible cycle seams.

For development reasons, add a debug panel that can be opened with the key press "=" that adds a slider to controls the time.

When finished, make sure the game runs and there are no errors or warnings.
