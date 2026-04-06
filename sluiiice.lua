-- sluiiice - a waterfall for iii grids
-- by duncan geere (@radioedit)
-- 
-- turn your grid so that the usb port faces upward
-- press grid keys to add walls
-- the top row constantly pours fluid in
-- the bottom row drains fluid out
-- the fluid will find its way down and around the walls, pooling where it can
--
-- adjust the musical variables below to change the harmonic behaviour of the script
-- adjust the simulation variables to change the behaviour of the fluid simulation
--
-- use update_scale(new_root, new_scale) to change the scale and root note: e.g. update_scale("C3", "minor")
-- use update_bpm(new_bpm) to change the bpm: e.g. update_bpm(90)


-- musical variables
bpm = 240 -- bpm you want the clock to run at, this will affect the speed of the simulation
root = "C3" -- root note of the scale, as a string
scale = "major" -- choose between "major" or "minor" scales
midi_channel = 1 -- which MIDI channel to send note on/off messages to (1-16)

-- custom harmonic tables - feel free to edit these to create your own scales and tunings
root_notes = {["F#2"]=42, ["G2"]=43, ["G#2"]=44, ["A2"]=45, ["A#2"]=46, ["B2"]=47, ["C3"]=48, ["C#3"]=49, ["D3"]=50, ["D#3"]=51, ["E3"]=52, ["F3"]=53, ["F#3"]=54}
bottom_major_8 = {0, 7, 12, 16, 21, 26, 31, 36}
bottom_major_16 = {-24, -17, -12, -5, 0, 7, 12, 16, 21, 26, 31, 36, 40, 45, 48, 55}
bottom_minor_8 = {0, 7, 12, 15, 20, 25, 31, 36}
bottom_minor_16 = {-24, -17, -12, -5, 0, 7, 12, 15, 20, 25, 31, 36, 39, 44, 48, 55}

-- these variables are set by the update_scale function
root_note = 0
intervals = {} -- this will hold the intervals for the bottom row based on the selected scale and grid size

-- simulation variables
refreshrate = 60 / bpm -- in seconds, how often the grid should update
pour_rate = 6 -- how much maximum mass to add when pouring
drain_rate = 15 -- how much maximum mass to remove when draining
diagonal_weight = 2 -- how much to weight diagonal movement compared to lateral movement
shimmer = false -- whether to add a small random flicker to the brightness of the LEDs, to make it look more fluid

-- clear the grid before we begin
grid_led_all(0)
grid_refresh()

-- create a table to hold the status of each cell in the grid
status = {}
for i = 1, grid_size_x()+1 do
    status[i] = {}
    if i > 1 then
        for j = 1, grid_size_y() do
            status[i][j] = {type = "fluid", mass=0}
        end
    else -- the top row starts off blocked
        for j = 1, grid_size_y() do
            status[i][j] = {type = "wall", mass=0}
        end
    end
end

-- event handler for grid key presses
function event_grid(x,y,z)

    -- if key is pressed
    if z==1 then 
        if status[x][y].type == "fluid" then
            status[x][y].type = "wall"
            status[x][y].mass = 0 -- reset mass when changing to wall
            grid_led(x,y,15)
        else
            status[x][y].type = "fluid"
            grid_led(x,y,15)
        end
    elseif z==0 then
        update_led(x,y)
    end

    -- refresh the grid
    grid_refresh()

end

-- main loop, runs every tick
function tick()

    -- previous midi notes off
    notes_off()

    -- drain the row below the bottom
    for j = 1, grid_size_y() do
        drain(grid_size_x()+1,j)
    end

    -- tick over every *visible* cell in the grid
    -- starting from the bottom row and moving up
    for i = grid_size_x(), 1, -1 do
        -- starting from the leftmost column and moving right
        for j = grid_size_y(), 1, -1 do

            -- if it's a fluid cell, update its mass
            if status[i][j].type == "fluid" then

                -- if we're in the top row, pour fluid
                if i == 1 then
                    pour(i,j)
                end

                -- then update the LEDs for this cell
                update_led(i,j)
                
                -- and play the bottom row as notes
                if i == grid_size_x() then play_note(i,j) end

                -- if the cell is a fluid then update its mass
                if i < grid_size_x()+1 then
                    trickle(i,j)
                end

                -- make sure mass stays between 0 and 15
                if status[i][j].mass < 0 then
                    status[i][j].mass = 0
                elseif status[i][j].mass > 15 then
                    status[i][j].mass = 15  
                end
            end
        end
    end

    -- refresh the grid
    grid_refresh()
end

-- add a random amount of mass to the cell, between 0 and pour_rate
function pour(x,y)
    status[x][y].mass = status[x][y].mass + math.random(0,pour_rate)
end

-- remove a random amount of mass from the cell, between 0 and drain_rate
function drain(x,y)
    status[x][y].mass = status[x][y].mass - math.random(0,drain_rate)
end

-- update mass of a cell, runs every tick
function trickle(x,y)

    -- if the cell below is a fluid, transfer mass downwards
    if status[x+1][y].type == "fluid" then

        -- GRAVITY DUMP
        -- calculate how much mass can be transferred
        -- minimum of mass in the current cell and capacity in cell below
        local transfer = math.min(status[x][y].mass, 15 - status[x+1][y].mass)

        status[x][y].mass = status[x][y].mass - transfer
        status[x+1][y].mass = status[x+1][y].mass + transfer
    end

    -- if not, or if it's full
    if status[x+1][y].type ~= "fluid" or status[x+1][y].mass >= 15 then

        -- set up an options table to hold weights for each possible movement direction
        local options = {left=0, right=0, down_left=0, down_right=0}

        -- assign weights to each option based on whether it's a valid move and how much capacity it has
        if y > 1 and status[x][y-1].type == "fluid" and status[x][y-1].mass < 15 then
            options.left = 1 * (math.random(80,120) / 100) --  standard weight for horizontal movement
        end
        if y < grid_size_y() and status[x][y+1].type == "fluid" and status[x][y+1].mass < 15 then
            options.right = 1 * (math.random(80,120) / 100) -- standard weight for horizontal movement
        end
        if x < grid_size_x()+1 and y > 1 and status[x+1][y-1].type == "fluid" and status[x+1][y-1].mass < 15 then
            options.down_left = diagonal_weight * (math.random(80,120) / 100) -- higher weight to prefer downwards movement
        end
        if x < grid_size_x()+1 and y < grid_size_y() and status[x+1][y+1].type == "fluid" and status[x+1][y+1].mass < 15 then
            options.down_right = diagonal_weight * (math.random(80,120) / 100) -- higher weight to prefer downwards movement
        end

        -- sum the total weight of all options
        total = options.left + options.right + options.down_left + options.down_right

        -- normalise the options to get fractional weights for each direction
        if total > 0 then
            options.left = options.left / total
            options.right = options.right / total
            options.down_left = options.down_left / total
            options.down_right = options.down_right / total
        end

        -- calculate fractional trickle according to the normalised weights
        local transfer_left = status[x][y].mass * options.left
        local transfer_right = status[x][y].mass * options.right
        local transfer_down_left = status[x][y].mass * options.down_left
        local transfer_down_right = status[x][y].mass * options.down_right

        -- remove the transferred mass from the current cell
        status[x][y].mass = status[x][y].mass - (transfer_left + transfer_right + transfer_down_left + transfer_down_right)

        -- add the transferred mass to the target cells
        if y > 1 then status[x][y-1].mass = status[x][y-1].mass + transfer_left end
        if y < grid_size_y() then status[x][y+1].mass = status[x][y+1].mass + transfer_right end
        if y > 1 then status[x+1][y-1].mass = status[x+1][y-1].mass + transfer_down_left end
        if y < grid_size_y() then status[x+1][y+1].mass = status[x+1][y+1].mass + transfer_down_right end
    end
end

-- update the leds, runs every tick after mass is updated
function update_led(x,y)

    -- handle fluid cells
    if status[x][y].type == "fluid" then
        local brightness = math.ceil(status[x][y].mass) -- round mass to nearest integer
        if brightness > 0 and shimmer == true then
            brightness = brightness + math.random(-1,1) -- add a small random flicker to the brightness
        end
        brightness = math.max(0, math.min(15, brightness)) -- ensure brightness stays between 0 and 15
        grid_led(x,y,brightness) -- use the rounded brightness value for the led

    -- handle wall cells    
    elseif status[x][y].type == "wall" then
        grid_led(x,y,0)
    end
end

function strum(notes)
    strumclock = metro.init(strum, refreshrate/#notes) -- adjust the time value to change the speed of the strum
    for i, note in ipairs(notes) do
        play_note(16, note.y)
    end
    metro.free(strumclock) -- free the metro after the strum is done
end

-- play a note! woo! 
function play_note(x,y)
    if status[x][y].type == "fluid" and status[x][y].mass >= 1 then
        local note = root_note + intervals[y] -- calculate MIDI note based on root note and interval for this row
        local velocity = math.min(127, math.ceil((status[x][y].mass * 8)-1)) -- velocity based on mass, scaled to max 127
        midi_note_on(note, velocity, midi_channel) -- send MIDI note on message
    end
end

-- stop the note!
function notes_off()
    for i = 1, #intervals do
        local note = root_note + intervals[i]
        midi_note_off(note, 0, midi_channel) -- send MIDI note off message with velocity 0
     end
end

-- Function to update the bpm
function update_bpm(new_bpm)
    bpm = new_bpm
    refreshrate = 60 / bpm
    m.time = refreshrate -- update the metro time to match the new refresh rate
end

-- Function to update the scale and root note
-- Tip: try calling this function from diii...
function update_scale(new_root, new_scale)
    
    -- Check if the root note is valid and get its MIDI number
    if root_notes[new_root] then
        root_note = root_notes[new_root]
    else
        print("Error: Invalid root note. Please choose from: F#2, G2, G#2, A2, A#2, B2, C3, C#3, D3, D#3, E3, F3, F#3")
    end

    -- Check grid size and scale and get the relevant intervals
    if grid_size_y() == 8 then
        if new_scale == "major" then
            intervals = bottom_major_8
        elseif new_scale == "minor" then
            intervals = bottom_minor_8
        else
            print("Error: Invalid scale. Please choose 'major' or 'minor'.")
        end
    elseif grid_size_y() == 16 then
        if new_scale == "major" then
            intervals = bottom_major_16
        elseif new_scale == "minor" then
            intervals = bottom_minor_16
        else
            print("Error: Invalid scale. Please choose 'major' or 'minor'.")
        end
    else
        print("Error: Unsupported grid size. You'll need to tweak the script to use a grid with a different number of rows, or create your own harmonic tables for the bottom row.")
    end

    -- flip the order of intervals to low notes are on the left
    table.sort(intervals, function(a, b) return a > b end)
end

-- set up a metro to run the tick function every refreshrate seconds
m = metro.init(tick, refreshrate)

-- set the initial scale and root note
update_scale(root, scale)

-- start the metro to run the tick function every refreshrate seconds
-- lets gooooooooooo
m:start()

-- need to stop? type m:stop() in the console