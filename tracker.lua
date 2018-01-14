-- Copyright (c) Joep Vanlier 2018
--
--    Permission is hereby granted, free of charge, to any person obtaining
--    a copy of this software and associated documentation files (the "Software"),
--    to deal in the Software without restriction, including without limitation
--    the rights to use, copy, modify, merge, publish, distribute, sublicense,
--    and/or sell copies of the Software, and to permit persons to whom the Software
--    is furnished to do so, subject to the following conditions:
--
--    The above copyright notice and this permission notice shall be included in
--    all copies or substantial portions of the Software.
--
--    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
--    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
--    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
--    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
--    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
--    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
--    OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
--    A lightweight LUA tracker for REAPER
--
--    Simply highlight a MIDI item and start the script.
--    This will bring up the MIDI item as a tracked sequence.
--
--    Work in progress. Input not yet implemented.
--

tracker = {}
tracker.eps = 1e-3
tracker.fov = {}
tracker.fov.scrollx = 0
tracker.fov.scrolly = 0
tracker.fov.width = 15
tracker.fov.height = 16

tracker.preserveOff = 1
tracker.xpos = 1
tracker.ypos = 1
tracker.xint = 0
tracker.page = 4
tracker.channels = 16 -- Max channel (0 is not shown)
tracker.displaychannels = 15
tracker.colors = {}
tracker.colors.selectcolor = {.7, 0, .5, 1}
tracker.colors.textcolor = {.7, .8, .8, 1}
tracker.colors.headercolor = {.5, .5, .8, 1}
tracker.colors.linecolor = {.1, .0, .4, .4}
tracker.colors.linecolor2 = {.3, .0, .6, .4}
tracker.colors.linecolor3 = {.4, .1, 1, 1}
tracker.colors.linecolor4 = {.2, .0, 1, .5}
tracker.hash = 0

local function print(...)
  if ( not ... ) then
    reaper.ShowConsoleMsg("nil value\n")
    return
  end
  reaper.ShowConsoleMsg(...)
  reaper.ShowConsoleMsg("\n")
end

function alpha(color, a)
  return { color[1], color[2], color[3], color[4] * a }
end

function tracker:initColors()
  tracker.colors.linecolors  = alpha( tracker.colors.linecolor, 1.3 )
  tracker.colors.linecolor2s = alpha( tracker.colors.linecolor2, 1.3 )
  tracker.colors.linecolor3s = alpha( tracker.colors.linecolor3, 0.5 )    
end

------------------------------
-- Pitch => note
------------------------------
function tracker:generatePitches()
  local notes = { 'C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-' }
  local pitches = {}
  j = 0
  for i = 0,10 do
    for k,v in pairs(notes) do
      pitches[j] = v..i
      j = j + 1
    end
  end
  self.pitchTable = pitches
end

------------------------------
-- Link GUI grid to data
------------------------------
function tracker:linkData()
  -- Here is where the linkage between the display and the actual data fields in "tracker" is made
  -- TO DO: This probably doesn't need to be done upon scrolling.
  local colsizes = {}
  local datafield = {}
  local idx = {}
  local padsizes = {}  
  local headers = {}
  
  datafield[#datafield+1] = 'legato'
  idx[#idx+1] = 1
  colsizes[#colsizes+1] = 1
  padsizes[#padsizes+1] = 1
  headers[#headers+1] = string.format( 'L' )
  
  for j = 1,self.displaychannels do
    -- Link up the note fields
    datafield[#datafield+1] = 'text'
    idx[#idx+1] = j
    colsizes[#colsizes + 1] = 3
    padsizes[#padsizes + 1] = 1
    headers[#headers + 1] = string.format(' Ch%2d', j)
    
    -- Link up the velocity fields
    datafield[#datafield+1] = 'vel'
    idx[#idx+1] = j
    colsizes[#colsizes + 1] = 2
    padsizes[#padsizes + 1] = 2   
    headers[#headers + 1] = ''     
  end
  local link = {}
  link.datafields = datafield
  link.headers    = headers
  link.padsizes   = padsizes
  link.colsizes   = colsizes
  link.idxfields  = idx
  self.link = link
end

function tracker:grabLinkage()
  local link = self.link
  return link.datafields, link.padsizes, link.colsizes, link.idxfields, link.headers
end

------------------------------
-- Establish what is plotted
------------------------------
function tracker:updatePlotLink()
  local plotData = {}
  local originx = 45
  local originy = 45
  local dx = 8
  local dy = 20
  plotData.barpad = 10
  plotData.itempadx = 5
  plotData.itempady = 3
  -- How far are the row indicators from the notes?
  plotData.indicatorShiftX = 3 * dx + 2 * plotData.itempadx
  plotData.indicatorShiftY = dy + plotData.itempady

  self.extracols = {}
  local datafields, padsizes, colsizes, idxfields, headers = self:grabLinkage()
  self.max_xpos = #headers
  self.max_ypos = self.rows
  
  -- Generate x locations for the columns
  local fov = self.fov
  local xloc = {}
  local xwidth = {}
  local xlink = {}
  local dlink = {}
  local header = {}
  local x = originx
  for j = fov.scrollx+1,math.min(#colsizes,fov.width+fov.scrollx) do
    xloc[#xloc + 1] = x
    xwidth[#xwidth + 1] = colsizes[j] * dx + padsizes[j]
    xlink[#xlink + 1] = idxfields[j]
    dlink[#dlink + 1] = datafields[j]
    header[#header + 1] = headers[j]
    x = x + colsizes[j] * dx + padsizes[j] * dx
  end
  plotData.xloc = xloc
  plotData.xwidth = xwidth
  plotData.totalwidth = x - padsizes[#padsizes] * dx - colsizes[#colsizes]*dx
  plotData.xstart = originx
  -- Variable dlink indicates what field the data can be found
  -- Variable xlink indicates the index that is being displayed
  plotData.dlink = dlink
  plotData.xlink = xlink
  plotData.headers = header
  
  -- Generate y locations for the columns
  local yloc = {}
  local yheight = {}
  local y = originy
  for j = 0,math.min(self.rows-1, fov.height-1) do
    yloc[#yloc + 1] = y
    yheight[#yheight + 1] = 0.7 * dy
    y = y + dy
  end
  plotData.yloc = yloc
  plotData.yheight = yheight
  plotData.yshift = 0.2 * dy
  plotData.totalheight = y - originy
  plotData.ystart = originy
  
  self.plotData = plotData
end

------------------------------
-- Cursor and play position
------------------------------
function tracker:normalizePositionToSelf(cpos)
  local loc = reaper.GetMediaItemInfo_Value(self.item, "D_POSITION")
  local loc2 = reaper.GetMediaItemInfo_Value(self.item, "D_LENGTH") 
  local row = ( cpos - loc ) * self.rowPerSec
  row = row - self.fov.scrolly
  local norm =  row / math.min(self.rows, self.fov.height)
  
  return norm
end

function tracker:getCursorLocation()
  return self:normalizePositionToSelf( reaper.GetCursorPosition() )
end

function tracker:getPlayLocation()
  if ( reaper.GetPlayState() == 0 ) then
    return self:getCursorLocation()
  else
    return self:normalizePositionToSelf( reaper.GetPlayPosition() )
  end
end

local function triangle( xc, yc, size, ori )
    local gfx = gfx
    ori = ori or 1
    gfx.line(xc-size,yc-ori*size,xc,yc+ori*size)
    gfx.line(xc,yc+ori*size,xc+size,yc-ori*size)
    gfx.line(xc+size,yc-ori*size,xc-size,yc-ori*size)
end

------------------------------
-- Draw the GUI
------------------------------
function tracker:printGrid()
  local tracker   = tracker
  local colors    = tracker.colors
  local gfx       = gfx
  local channels  = self.displaychannels
  local rows      = self.rows
  local text      = self.text
  local vel       = self.vel
  local fov       = self.fov
  
  local plotData  = self.plotData
  local xloc      = plotData.xloc
  local xwidth    = plotData.xwidth
  local yloc      = plotData.yloc
  local yheight   = plotData.yheight
  
  local relx = tracker.xpos-fov.scrollx
  local rely = tracker.ypos-fov.scrolly
  
  gfx.set(table.unpack(colors.selectcolor))
  gfx.rect(xloc[relx], yloc[rely]-plotData.yshift, xwidth[relx], yheight[rely])
  
  local dlink     = plotData.dlink
  local xlink     = plotData.xlink
  local headers   = plotData.headers
  local tw        = plotData.totalwidth
  local th        = plotData.totalheight
  local itempadx  = plotData.itempadx
  local itempady  = plotData.itempady
  local scrolly   = fov.scrolly
  
  -- Render in relative FOV coordinates
  local data      = self.data
  for y=1,#yloc do
    gfx.y = yloc[y]
    gfx.x = xloc[1] - plotData.indicatorShiftX
    local absy = y + scrolly
    gfx.set(table.unpack(colors.headercolor))    
    gfx.printf("%3d", absy)
    local c1, c2
    if ( (((absy-1)/4) - math.floor((absy-1)/4)) == 0 ) then
      c1 = colors.linecolor2
      c2 = colors.linecolor2s
    else
      c1 = colors.linecolor
      c2 = colors.linecolors
    end
    gfx.set(table.unpack(c1))
    gfx.rect(xloc[1] - itempadx, yloc[y] - plotData.yshift, tw, yheight[1] + itempady)
    gfx.set(table.unpack(c2))
    gfx.rect(xloc[1] - itempadx, yloc[y] - plotData.yshift, tw, 1)
    gfx.rect(xloc[1] - itempadx, yloc[y] - plotData.yshift, 1, yheight[y])
    gfx.rect(xloc[1] - itempadx + tw + 0, yloc[y] - plotData.yshift, 1, yheight[y] + itempady)    
    for x=1,#xloc do
      gfx.x = xloc[x]
      gfx.set(table.unpack(colors.textcolor))
      gfx.printf("%s", data[dlink[x]][rows*xlink[x]+absy-1])
    end
  end
  
  -- Draw the headers so we don't get lost :)
  gfx.set(table.unpack(colors.headercolor))
  gfx.y = yloc[1] - plotData.indicatorShiftY

  for x=1,#xloc do
    gfx.x = xloc[x]
    gfx.printf("%s", headers[x])
  end
 
  local playLoc = self:getPlayLocation()
  local xc = xloc[1] - .5 * plotData.indicatorShiftX
  local yc = yloc[1] - .8 * plotData.indicatorShiftY  
  if ( playLoc < 0 ) then   
      gfx.set(table.unpack(colors.linecolor3s))     
      triangle(xc, yc+1, 3, -1)        
      gfx.set(table.unpack(colors.linecolor3))
      triangle(xc, yc, 5, -1)
  else
    if ( playLoc > 1 ) then
      gfx.set(table.unpack(colors.linecolor3s))
      triangle(xc, yc-1, 3, 1)           
      gfx.set(table.unpack(colors.linecolor3))
      triangle(xc, yc, 5, 1)    
    else
      gfx.rect(plotData.xstart - itempadx, plotData.ystart + plotData.totalheight * playLoc - itempady - 1, tw, 1)
    end
  end
  local markerLoc = self:getCursorLocation()
  if ( markerLoc > 0 and markerLoc < 1 ) then
    gfx.set(table.unpack(colors.linecolor4))
    gfx.rect(plotData.xstart - itempadx, plotData.ystart + plotData.totalheight * self:getCursorLocation() - itempady - 1, tw, 1)
  end
end

-- Returns fieldtype, channel and row
function tracker:getLocation()
  local plotData  = self.plotData
  local dlink     = plotData.dlink
  local xlink     = plotData.xlink
  local relx      = tracker.xpos - tracker.fov.scrollx
  
  return dlink[relx], xlink[relx], tracker.ypos - 1
end

function tracker:placeOff()
  local rows      = self.rows
  local notes     = self.notes
  local data      = self.data
  local noteGrid  = data.note
  local noteStart = data.noteStart 
  
  -- Determine fieldtype, channel and row
  local ftype, chan, row = self:getLocation()
  
  -- Note off is only sensible for note fields
  local idx = chan*rows+row
  local note = noteGrid[idx]
  local start = noteStart[idx]
  if ( ( ftype == 'text' ) or ( ftype == 'vel' ) ) then  
    -- If there is no note here add a marker for the note off event
    if ( not note ) then
      ppq = self:rowToPpq(row)
      self:addNoteOFF(ppq, chan)
      return
    elseif ( start > -1 ) then
      -- If it was the start of a note, this note requires deletion and the previous note may have to be extended
      
    end
  end
  
end

---------------------
-- Check whether the previous note can grow if this one would be gone
-- Shift indicates that the fields downwards of row will go up
---------------------
function tracker:checkNoteGrow(notes, noteGrid, rows, chan, row, singlerow, noteToDelete, shift)
  local modify = 0
  local offset = shift or 0
  if ( row > 1 ) then
    local noteToResize = noteGrid[rows*chan+row - 1]
          
    if ( noteToResize ) then
      local k = row+1
      while( k < rows ) do
        if ( noteGrid[rows*chan+k] and ( not ( noteGrid[rows*chan+k] == noteToDelete ) ) ) then
          break;
        end
        k = k + 1
      end
      local resize = k-row
      
      -- If we are the last note, then it may go to the end of the track, hence only subtract
      -- the shift offset if we are not the last note in the pattern
      if ( k < rows-1 ) then
        resize = resize - offset
      end
      local pitch, vel, startppqpos, endppqpos = table.unpack( notes[noteToResize] )
      modify = 1
      reaper.MIDI_SetNote(self.take, noteToResize, nil, nil, startppqpos, self:clampPpq( endppqpos + singlerow * resize ), nil, nil, nil, true)
    end
  end
  return modify
end

---------------------
-- Backspace
---------------------
function tracker:backspace()
  local data      = self.data
  local rows      = self.rows
  local notes     = self.notes
  local singlerow = self:rowToPpq(1)

  -- Determine fieldtype, channel and row
  local ftype, chan, row = self:getLocation()
  
   -- What are we manipulating here?
  if ( ( ftype == 'text' ) or ( ftype == 'vel' ) ) then
    local noteGrid = data.note
    local noteStart = data.noteStart      
    
    reaper.Undo_OnStateChange2(0, "Tracker: Delete note (Backspace)")
    reaper.MarkProjectDirty(0)          
    
    local lastnote
    local note = noteGrid[rows*chan+row]
    local noteToDelete = noteStart[rows*chan+row]    
    -- Are we on the start of a note or an OFF symbol?
    if ( noteToDelete or ( note and note == -1 ) ) then
      -- Check whether there is a note before this, and elongate it until the next blockade
      self:checkNoteGrow(notes, noteGrid, rows, chan, row, singlerow, noteStart[rows*chan+row], 1)
    
    elseif ( note and ( note > -1 ) ) then
      local pitch, vel, startppqpos, endppqpos = table.unpack( notes[note] )
      reaper.MIDI_SetNote(self.take, note, nil, nil, startppqpos, endppqpos - singlerow, nil, nil, nil, true)
      lastnote = note
    end         
          
    -- Everything below this note has to shift one up
    for i = row,rows-1 do
      local note = noteGrid[rows*chan+i]
      if ( note ~= lastnote ) then
        if ( note and ( note > -1 ) ) then
          local pitch, vel, startppqpos, endppqpos = table.unpack( notes[note] )
          reaper.MIDI_SetNote(self.take, note, nil, nil, startppqpos - singlerow,endppqpos - singlerow, nil, nil, nil, true)
        end
      end
      lastnote = note
    end
    
    -- Were we on a note start? ==> Kill it
    if ( noteToDelete ) then
      self:deleteNote(chan, row)
    end
    
    reaper.MIDI_Sort(self.take)
    
  elseif ( ftype == 'legato' ) then
  else
    print( "FATAL ERROR IN TRACKER.LUA: unknown field?" )
    return
  end
end

---------------------
-- Add OFF flag
---------------------
function tracker:addNoteOFF(ppq, channel)
  reaper.MIDI_InsertTextSysexEvt(self.take, false, false, ppq, 1, string.format('OFF%2d', channel))
end

---------------------
-- Delete note
---------------------
function tracker:deleteNote(channel, row)
  local rows      = self.rows
  local notes     = self.notes
  local noteGrid  = self.data.note

  -- Deleting note requires some care, in some cases, there may be an OFF trigger which needs to be stored separately
  -- since we don't want them disappearing with the notes.
  noteToDelete = noteGrid[rows*channel+row]
  if ( tracker.preserveOff == 1 ) then
      local k = row+1
      while( k < rows ) do
        if ( noteGrid[rows*channel+k] ) then
          if ( ( noteGrid[rows*channel+k] > -1 ) and ( noteGrid[rows*channel+k] ~= noteToDelete) ) then
            -- It's another note, we're cool. Don't need explicit OFF symbol
            break;
          else
            -- It's an off symbol, we need to store it separately
            local pitch, vel, startppqpos, endppqpos = table.unpack( notes[noteToDelete] )
            tracker:addNoteOFF(endppqpos, channel)            
            reaper.MIDI_DeleteNote(self.take, noteToDelete)
            break;
          end
        end
      end   
  else
    -- No off preservation, just delete it.
    reaper.MIDI_DeleteNote(self.take, noteToDelete)
  end
end


---------------------
-- Delete
---------------------
function tracker:delete()
  local data      = self.data
  local rows      = self.rows
  local notes     = self.notes
  local singlerow = self:rowToPpq(1)
  local modify    = 0

  reaper.Undo_OnStateChange2(0, "Tracker: Delete (Del)")

  -- Determine fieldtype, channel and row
  local ftype, chan, row = self:getLocation()
  
  -- What are we manipulating here?
  if ( ( ftype == 'text' ) or ( ftype == 'vel' ) ) then
    local noteGrid = data.note
    local noteStart = data.noteStart
       
    -- OFF marker
    if ( noteGrid[rows*chan+row] == -1 ) then
      -- Check whether the previous note can grow now that this one is gone
      tracker:checkNoteGrow(notes, noteGrid, rows, chan, row, singlerow)
    end
    
    -- Note
    local noteToDelete = noteStart[rows*chan+row]
    if ( noteToDelete ) then
      modify = 1
      reaper.MarkProjectDirty(0)      
      self:checkNoteGrow(notes, noteGrid, rows, chan, row, singlerow, noteToDelete)
      self:deleteNote(chan, row)
    end
    
  elseif ( ftype == 'legato' ) then
  else
    print( "FATAL ERROR IN TRACKER.LUA: unknown field?" )
    return
  end
  if ( modify == 1 ) then
    reaper.MIDI_Sort(self.take)
  end
end

function tracker:clampPpq(ppq)
  if ( ppq > self.maxppq ) then
    return self.maxppq
  elseif ( ppq < self.minppq ) then
    return self.minppq
  else
    return ppq
  end
end

---------------------
-- Insert
---------------------
function tracker:insert()
  local data      = self.data
  local singlerow = self:rowToPpq(1)
  
  -- Determine fieldtype, channel and row
  local ftype, chan, row = self:getLocation()  
  
  -- What are we manipulating here?
  if ( ( ftype == 'text' ) or ( ftype == 'vel' ) ) then
    local noteGrid = data.note
    local noteStart= data.noteStart    
    local text     = data.text
    local vel      = data.vel
    local rows     = self.rows
    local notes    = self.notes

    reaper.Undo_OnStateChange2(0, "Tracker: Insert")
    reaper.MarkProjectDirty(0)
    
    local elongate
    -- Are we inside a note? ==> It needs to be elongated!    
    if ( not noteStart[rows*chan+row] ) then
      elongate = noteGrid[rows*chan+row]
      if ( elongate ) then
        -- An OFF leads to an elongation of the previous note
        if ( elongate == -1 ) then
          if ( row > 0 ) then
            elongate = noteGrid[rows*chan+row - 1]
          end
        end
        
        -- Let's elongate the note by a row!
        local pitch, vel, startppqpos, endppqpos = table.unpack( notes[elongate] )
        reaper.MIDI_SetNote(self.take, elongate, nil, nil, nil, self:clampPpq(endppqpos + singlerow), nil, nil, nil, true)
      end
    else
      -- We are at a note start... maybe there is a previous note who wants to be elongated?
      if ( row > 1 ) then
        local note = noteGrid[rows*chan+row-1]
        if ( note and ( note > -1 ) ) then
          -- Yup
          local pitch, vel, startppqpos, endppqpos = table.unpack( notes[note] )
          reaper.MIDI_SetNote(self.take, note, nil, nil, nil, self:clampPpq(endppqpos + singlerow), nil, nil, nil, true)          
        end
      end
    end

    -- Everything below this note has to go one shift down
    local lastnote = elongate
    for i = row,rows-1 do
      local note = noteGrid[rows*chan+i]
      if ( note ~= lastnote ) then
        if ( note and ( note > -1 ) ) then
          local pitch, vel, startppqpos, endppqpos = table.unpack( notes[note] )
          if ( i < rows-1 ) then
            reaper.MIDI_SetNote(self.take, note, nil, nil, self:clampPpq(startppqpos + singlerow), self:clampPpq(endppqpos + singlerow), nil, nil, nil, true)
          else
            self:deleteNote(chan, i)
          end
        end
      end
      lastnote = note
    end
    reaper.MIDI_Sort(self.take)
  elseif ( ftype == 'legato' ) then

  else
    print( "FATAL ERROR IN TRACKER.LUA: unknown field?" )
    return
  end
end


------------------------------
-- Force selector in range
------------------------------
function tracker:forceCursorInRange()
  local fov = self.fov
  if ( self.xpos < 1 ) then
    self.xpos = 1
  end
  if ( self.ypos < 1 ) then
    self.ypos = 1
  end
  if ( self.xpos > self.max_xpos ) then
    self.xpos = math.floor( self.max_xpos )
  end
  if ( self.ypos > self.max_ypos ) then
    self.ypos = math.floor( self.max_ypos )
  end
  -- Is the cursor off fov?
  if ( ( self.ypos - fov.scrolly ) > self.fov.height ) then
    self.fov.scrolly = self.ypos - self.fov.height
  end
  if ( ( self.ypos - fov.scrolly ) < 1 ) then
    self.fov.scrolly = self.ypos - 1
  end
  -- Is the cursor off fov?
  if ( ( self.xpos - fov.scrollx ) > self.fov.width ) then
    self.fov.scrollx = self.xpos - self.fov.width
    self:updatePlotLink()
  end
  if ( ( self.xpos - fov.scrollx ) < 1 ) then
    self.fov.scrollx = self.xpos - 1
    self:updatePlotLink()
  end    
end

function tracker:toSeconds(seconds)
  return seconds / self.rowPerSec
end

function tracker:rowToPpq(row)
  return row * self.ppqPerRow
end

function tracker:rowToAbsPpq(row)
  return row * self.ppqPerRow + self.minppq
end

function tracker:toQn(seconds)
  return self.rowPerQn * seconds / self.rowPerSec
end

------------------------------
-- Determine timing info
-- returns true if something changed
------------------------------
function tracker:getRowInfo()
    -- How many rows do we need?
    local ppqPerQn = reaper.MIDI_GetPPQPosFromProjQN(self.take, 1) - reaper.MIDI_GetPPQPosFromProjQN(self.take, 0)
    local ppqPerSec = 1.0 / ( reaper.MIDI_GetProjTimeFromPPQPos(self.take, 1) - reaper.MIDI_GetProjTimeFromPPQPos(self.take, 0) )
    local mediaLength = reaper.GetMediaItemInfo_Value(self.item, "D_LENGTH")
    
    self.maxppq = ppqPerSec * reaper.GetMediaItemInfo_Value(self.item, "D_LENGTH")
    self.minppq = ppqPerSec * reaper.GetMediaItemInfo_Value(self.item, "D_POSITION")
    
    self.qnCount = mediaLength * ppqPerSec / ppqPerQn
    self.rowPerQn = 4
    self.rowPerPpq = self.rowPerQn / ppqPerQn
    self.ppqPerRow = 1 / self.rowPerPpq
    self.rowPerSec = ppqPerSec * self.rowPerQn / ppqPerQn
    local rows = self.rowPerQn * self.qnCount
    
    -- Do not allow zero rows in the tracker!
    if ( rows < self.eps ) then
      reaper.SetMediaItemInfo_Value(self.item, "D_LENGTH", self:toSeconds(1) )
      rows = 1
    end
    
    if ( ( self.rows ~= rows ) or ( self.ppqPerQn ~= ppqPerQn ) ) then
      self.rows = rows
      self.qnPerPpq = 1 / ppqPerQn      
      self.ppqPerQn = ppqPerQn
      return true
    else
      return false
    end
end

------------------------------
-- MIDI => Tracking
------------------------------
-- Check if a space in the column is already occupied
function tracker:isFree(channel, y1, y2, treatOffAsFree)
  local rows = self.rows
  local notes = self.data.note
  local offFree = treatOffAsFree or 0
  for y=y1,y2 do
    -- Occupied
    if ( notes[rows*channel+y] ) then
      if ( offFree == 1 ) then
        -- -1 indicates an OFF, which is considered free when treatOffAsFree is on :)
        if ( notes[rows*channel+y] > -1 ) then
          return false
        end
      else
        offFree = 0
      end
    end
  end
  return true
end

-- Assign off locations
function tracker:assignOFF(channel, idx)
  local data = self.data
  local rows = self.rows
  local offList = self.offList
  
  local ppq = table.unpack( offList[idx] )
  local row = math.floor( ppq * self.rowPerPpq )
  data.text[rows*channel + row] = 'OFF'
  data.note[rows*channel + row] = -idx - 1
end

-- Assign a note that is already in the MIDI data
function tracker:assignFromMIDI(channel, idx)
  local pitchTable = self.pitchTable
  local rows = self.rows
  
  local notes = self.notes
  local starts = self.noteStarts
  local pitch, vel, startppqpos, endppqpos = table.unpack( notes[idx] ) 
  local ystart = math.floor( startppqpos * self.rowPerPpq + self.eps )
  local yend = math.floor( endppqpos * self.rowPerPpq - self.eps )
  
  -- This note is not actually present
  if ( ystart > self.rows-1 ) then
    return true
  end
  if ( ystart < -self.eps ) then
    return true
  end
  if ( yend > self.rows - 1 ) then
    yend = self.rows
  end
  
  -- Add the note if there is space on this channel, otherwise return false
  local data = self.data
  if ( self:isFree( channel, ystart, yend ) ) then
    data.text[rows*channel+ystart]      = pitchTable[pitch]
    data.vel[rows*channel+ystart]       = string.format('%2d', vel )  
    data.noteStart[rows*channel+ystart] = idx
    for y = ystart,yend,1 do      
      data.note[rows*channel+y] = idx
    end
    if ( yend+1 < rows ) then
      if ( self:isFree( channel, yend+1, yend+1, 1 ) ) then
        data.text[rows*channel+yend+1] = 'OFF'
        data.note[rows*channel+yend+1] = -1
      end
    end
    --print("NOTE "..self.pitchTable[pitch] .. " on channel " .. channel .. " from " .. ystart .. " to " .. yend)    
    return true
  else
    return false
  end  
end

------------------------------
-- Internal data initialisation
-----------------------------
function tracker:initializeGrid()
  local x, y
  local data = {}
  data.noteStart = {}
  data.note = {}
  data.text = {}
  data.vel = {}
  data.legato = {}
  data.offs = {}
  local channels = self.channels
  local rows = self.rows
  for x=0,channels-1 do
    for y=0,rows-1 do
      data.note[rows*x+y] = nil
      data.text[rows*x+y] = '...'
      data.vel[rows*x+y] = '..'
    end
  end
  
  for y=0,rows-1 do
    data.legato[y] = 0
  end
  
  self.data = data
end

------------------------------
-- Update function
-- heavy-ish, avoid calling too often
-----------------------------
function tracker:update()
  local reaper = reaper
  if ( self.take and self.item ) then
    self:getRowInfo()
    self:linkData()
    self:updatePlotLink()
    self:initializeGrid()
    
    -- Grab the notes and store them in channels
    local retval, notecntOut, ccevtcntOut, textsyxevtcntOut = reaper.MIDI_CountEvts(self.take)
    local i
    if ( retval > 0 ) then
      -- Find the 'offs' and place them first. They could have only come from the tracker sytem
      -- so don't worry too much.
      local offs = {}
      self.offList = offs
      for i=0,textsyxevtcntOut do
        local _, _, _, ppqpos, typeidx, msg = reaper.MIDI_GetTextSysexEvt(self.take, i, nil, nil, 1, 0, "")
        if ( typeidx == 1 ) then
          if ( string.sub(msg,1,3) == 'OFF' ) then
            -- If it crashes here, OFF-like events with invalid data were added by something
            local substr = string.sub(msg,4,5)
            local channel = tonumber( substr )
            offs[i] = {ppqpos}
            self:assignOFF(channel, i)
          end
        end
      end
    
      local channels = {}
      channels[0] = {}
      local notes = {}
      for i=0,notecntOut do
        local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(self.take, i)
        if ( retval == true ) then
          if ( not channels[chan] ) then
            channels[chan] = {}
          end
          notes[i] = {pitch, vel, startppqpos, endppqpos}
          channels[chan][#(channels[chan])+1] = i
        end
      end
      self.notes = notes
    
      -- Assign the tracker assigned channels first
      local failures = {}
      for channel=1,self.channels do
        if ( channels[channel] ) then
          for i,note in pairs( channels[channel] ) do
            if ( self:assignFromMIDI(channel,note) == false ) then
              -- Did we fail? Store the note for a second attempt at placement later
              failures[#failures + 1] = note
            end
          end
        end
      end
      
      -- Things in channel zero are new and need to be reassigned!
      for i,note in pairs( channels[0] ) do
        failures[#failures + 1] = note
      end
      
      if ( #failures > 0 ) then
        -- We are going to be changing the data, so add an undo point
        reaper.Undo_OnStateChange2(0, "Tracker: Channel reassignment")
        reaper.MarkProjectDirty(0)
      end
      
      -- Attempt to find a channel for them
      local ok = 0
      local maxChannel = self.channels
      for i,note in pairs(failures) do
        local targetChannel = 1
        local done = false
        while( done == false ) do
          if ( self:assignFromMIDI(targetChannel,note) == true ) then
            reaper.MIDI_SetNote(self.take, note, nil, nil, nil, nil, targetChannel, nil, nil, true)
            done = true
            ok = ok + 1
          else
            targetChannel = targetChannel + 1
            if ( targetChannel > maxChannel ) then 
              done = true
            end
          end
        end
      end

      -- Failed to place some notes
      if ( ok < #failures ) then
        print( "WARNING: FAILED TO PLACE SOME OF THE NOTES IN THE TRACKER" )
      end
      
      if ( channels[0] ) then
        reaper.MIDI_Sort(self.take)
      end
    end
  end
  local pitchSymbol = self.pitchTable[pitchOut]
end

------------------------------
-- Selection management
-----------------------------
function tracker:setItem( item )
  self.item = item
end

function tracker:setTake( take )
  -- Only switch if we're actually changing take
  if ( self.take ~= take ) then
    if ( reaper.TakeIsMIDI( take ) == true ) then
      self.take = take
      -- Store note hash (second arg = notes only)
      self.hash = reaper.MIDI_GetHash( self.take, true, "?" )
      self:update()
      return true
    end
  end
  return false
end

-- I wish I knew of a cleaner way to do this. This hack tests
-- whether the mediaItem still exists by calling it in a protected call
-- if GetActiveTake fails, the user deleted the mediaItem and we must
-- close the tracker window.
function tracker:testGetTake()
  reaper.GetActiveTake(tracker.item)
end

------------------------------
-- Check for note changes
-----------------------------
function tracker:checkChange()
  local take
  if not pcall( self.testGetTake ) then
    return false
  end
  take = reaper.GetActiveTake(self.item)
  if ( not take ) then
    return false
  end
  if ( reaper.TakeIsMIDI( take ) == true ) then
    if ( tracker:setTake( take ) == false ) then
      -- Take did not change, but did the note data?
      local retval, currentHash = reaper.MIDI_GetHash( self.take, true, "?" )
      if ( retval == true ) then
        if ( currentHash ~= self.hash ) then
          self.hash = currentHash
          self:update()
        end
      end
    end
  else
    return false
  end
  
  return true
end

local function togglePlayPause()
  local reaper = reaper
  local state = 0
  local HasState = reaper.HasExtState("PlayPauseToggle", "ToggleValue")

  if HasState == 1 then
    state = reaperGetExtState("PlayPauseToggle", "ToggleValue")
  end
    
  if ( state == 0 ) then
    reaper.Main_OnCommand(40044, 0)
  else
    reaper.Main_OnCommand(40073, 0)
  end
end

------------------------------
-- Main update loop
-----------------------------
local function updateLoop()
  local tracker = tracker

  -- Check if the note data or take changed, if so, update the note contents
  if ( not tracker:checkChange() ) then
    gfx.quit()
    return
  end

  -- Maintain the loop until the window is closed or escape is pressed
  local char = gfx.getchar()
  
  -- Check if the length changed, if so, update the time data
  if ( tracker:getRowInfo() == true ) then
    tracker:update()
  end  

--[[--
if ( char ~= 0 ) then
  print(char)
end
 --]]--
 
  if char == 1818584692 then
    tracker.xpos = tracker.xpos - 1
  elseif char == 45 then
    tracker:placeOff()
  elseif char == 1919379572 then
    tracker.xpos = tracker.xpos + 1
  elseif char == 30064 then
    tracker.ypos = tracker.ypos - 1
  elseif char == 1685026670 then
    tracker.ypos = tracker.ypos + 1
  elseif char == 6579564 then 
    -- Delete
    tracker:delete()
  elseif char == 1752132965 then
    -- Home
    tracker.ypos = 0
  elseif char == 6647396 then
    -- End
    tracker.ypos = tracker.rows
  elseif char == 32 then
    -- Space
    togglePlayPause()
  elseif char == 13 then
    -- Enter
    local mpos = reaper.GetMediaItemInfo_Value(tracker.item, "D_POSITION")
    local loc = reaper.AddProjectMarker(0, 0, tracker:toSeconds(tracker.ypos-1), 0, "", -1)
    reaper.GoToMarker(0, loc, 0)
    reaper.DeleteProjectMarker(0, loc, 0)
    togglePlayPause()
  elseif char == 6909555 then
    -- Insert
    tracker:insert()
  elseif char == 8 then
    -- Backspace
    tracker:backspace()
  elseif char == 1885828464 then
    -- Pg Up
    tracker.ypos = tracker.ypos - tracker.page
  elseif char == 1885824110 then
    -- Pg Down
    tracker.ypos = tracker.ypos + tracker.page    
  end
  
  tracker:forceCursorInRange()
  tracker:printGrid()
  gfx.update()
   
  if char ~= 27 and char ~= -1 then
    reaper.defer(updateLoop)
  else
    gfx.quit()
  end
end

local function Main()
  local tracker = tracker
  tracker.tick = 0
  tracker:generatePitches()
  tracker:initColors()
  gfx.init("Hackey Trackey v0.3", 640, 480, 0, 200, 200)
  
  local reaper = reaper
  if ( reaper.CountSelectedMediaItems(0) > 0 ) then
    local item = reaper.GetSelectedMediaItem(0, 0)
    local take = reaper.GetActiveTake(item)
    if ( reaper.TakeIsMIDI( take ) == true ) then
      tracker:setItem( item )
      tracker:setTake( take )
      reaper.defer(updateLoop)
    end
  end
end

Main()