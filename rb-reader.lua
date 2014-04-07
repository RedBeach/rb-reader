-------------------------------------------------------------------------------------------------------------------------
-- Red Beach Library - https://bitbucket.org/redbeach                                                                                                   
-- Library: Display                                                                                                   
-- v 0.01                                                                                                     
-- Dependencies: None                                                                                                  
--                                                                                                                     
--
-- 
-- This library is open source under the MIT licensed (see http://opensource.org/licenses/MIT)
-- Feel free to use, modify, distribute and mainly contribute with improvements
-- 
-- Improvements needed
-- 1) Be able to read the bar code from up-side down
-- 2) Add support to the zero-suppressed UPC bar code (6-8 digits instead of 12)
-- 3) Add reading on the fly
-- 4) Test if using some kind of filter improves the reading
-- 5) Add support to QR Code
-- 6) Add support to other bar code formats
--
--
-- Useful Links about Bar Code
-- http://electronics.howstuffworks.com/gadgets/high-tech-gadgets/upc1.htm
-- http://en.wikipedia.org/wiki/Universal_Product_Code
-- 
--
-------------------------------------------------------------------------------------------------------------------------





local rb = {}

rb.numOfReads = 10  
rb.cameraShape = nil -- will store the display object that we will use to show the camera
rb.readerLine = nil

local readingInProgress = false

------------------------
-- Private Functions

local function updateCamera()
    rb.cameraShape.fill = { type="camera" }
end
local function startWorkAroundToKeepCameraRefreshing()    
    Runtime:addEventListener("enterFrame", updateCamera)
end
local function stopWorkAroundToKeepCameraRefreshing()    
    Runtime:removeEventListener("enterFrame", updateCamera)
end


-- shows the reader on screen
local function showReader(params)
        
    local cameraShapeW = params.width
    local cameraShapeH = params.height
    local cameraShape
    local shapeRotation = 0
    
    local isLandscape = display.contentWidth > display.contentHeight    
    if isLandscape and params.fill.type == "camera" then -- Corona has a bug that the camera fill does not work correclty on Landscape. This is a work-around for that
        local t = cameraShapeW
        cameraShapeW = cameraShapeH
        cameraShapeH = t    
        shapeRotation = -90
    end    
    cameraShape = display.newRect(params.x, params.y, cameraShapeW, cameraShapeH )
    cameraShape.anchorX = 0.5
    cameraShape.fill = params.fill
    cameraShape.rotation = shapeRotation

    --cameraShape.fill.effect = "filter.duotone"
    --cameraShape.fill.effect.darkColor = { 0, 0, 0, 1 }
    --cameraShape.fill.effect.lightColor = { 1, 1, 1, 1 }
    

    rb.cameraShape = cameraShape
    if params.fill.type == "camera" then
        startWorkAroundToKeepCameraRefreshing()
    end
    
        
  

    local readerWidth = cameraShape.contentWidth * 0.9
    local readerLine = display.newLine(0,0,readerWidth,0)
    readerLine:setStrokeColor(1,0,0)
    readerLine.x,readerLine.y = cameraShape.x - readerWidth*0.5, cameraShape.y
    rb.readerLine = readerLine
end

local function updateLineWidth(newWidth)
    local formerLine = rb.readerLine
    local newGuideLine = display.newLine(0,0,newWidth,0)
    newGuideLine.x,newGuideLine.y = rb.cameraShape.x - newWidth*0.5, rb.cameraShape.y
    newGuideLine:setStrokeColor(1,0,0)
    display.remove(formerLine)
    rb.readerLine = newGuideLine
end

-- reads the pixels along (near) the guide line
local function readPixels(readerYposition, onComplete)
    local readerLine = rb.readerLine
    local readerInitialX = readerLine.contentBounds.xMin
    local readerFinalX = readerLine.contentBounds.xMax
    
    print("readerInitialX=", readerInitialX); print("readerFinalX=", readerFinalX); print("readerY=", readerYposition)
    local count = 0
    
    local pixelList = {}
    local pixelListSum = 0
    local function onColorSample( event )
        count = count + 1
        --print( "(" .. event.x .. "," .. event.y .. ")= ", event.r, event.g, event.b,"  -  sum[".. event.x - readerInitialX + 1 .. "]=",  event.r + event.g + event.b)  
        pixelList[event.x - readerInitialX + 1] = event.r + event.g + event.b
        pixelListSum = pixelListSum + event.r + event.g + event.b
        if count == (readerFinalX - readerInitialX + 1) then
            onComplete(pixelList, pixelListSum)
        end
     end
    
    for i=readerInitialX,readerFinalX do
        display.colorSample( i, readerYposition, onColorSample )
    end
        
end

-- gets a table of pixels and returns a discreted list based on the threshold passed
local function convertPixelListToBinary(pixelList, thresholdLine)
    
    local pixelListDiscreted = {}
    
    -- converting to binary values
    for i=1, #pixelList do
        if pixelList[i] > thresholdLine then
            pixelListDiscreted[i] = 1
        else
            pixelListDiscreted[i] = 0
        end        
    end    
    
    return pixelListDiscreted
end

-- calculates the UPC Bar Code from a table of discreted data
local function calculateUPCbarCode(pixelListDiscreted)
    
    local upcCodeToValue = {}
    upcCodeToValue["3-2-1-1"] = 0
    upcCodeToValue["2-2-2-1"] = 1
    upcCodeToValue["2-1-2-2"] = 2
    upcCodeToValue["1-4-1-1"] = 3
    upcCodeToValue["1-1-3-2"] = 4
    upcCodeToValue["1-2-3-1"] = 5
    upcCodeToValue["1-1-1-4"] = 6
    upcCodeToValue["1-3-1-2"] = 7
    upcCodeToValue["1-2-1-3"] = 8
    upcCodeToValue["3-1-1-2"] = 9
    
    -- finding the initial 1-1-1 (bar-space-bar)
    local initialIndex
    local lastValue = pixelListDiscreted[1]
    for i=2, #pixelListDiscreted do
        if pixelListDiscreted[i] ~= lastValue then
            initialIndex = i
            break
        end
    end
    
    if initialIndex == nil then
        print("Bar code not recognized!")
        --updateText("Bar code not recognized!")
        return
    end
    
    -- creating a table with the index of the each signal inversion
    local tableSignalInverted = {}
    tableSignalInverted[1] = initialIndex
    lastValue = pixelListDiscreted[initialIndex]
    for i=initialIndex+1, #pixelListDiscreted do 
        if pixelListDiscreted[i] ~= lastValue then
            tableSignalInverted[#tableSignalInverted+1] = i
            lastValue = pixelListDiscreted[i]
        end
    end
    
        
     --checking if the first 3 signal match the bar-space-bar 
    if tableSignalInverted[1] == tableSignalInverted[2] or tableSignalInverted[2] == tableSignalInverted[3] then
        print("1-1-1 verification failed! This is not an UPC code")                
        return
    end
    
    
   local function readUPCblock(blockNumber)
       
       local blockIndex = blockNumber*4
       
       if blockNumber >= 7 then
           blockIndex = blockIndex + 5 -- this is to jump the middle control bars
       end
       
       if blockIndex + 4 > #tableSignalInverted then
           -- block does not exist
           return false
       end
                       
        --print("blockNumber=", blockNumber, "  -  blockIndex=", blockIndex)
        local pixelIndex = {}
        for i=1,5 do
            --print("tableSignalInverted[" .. blockIndex + (i-1) .. "]=", tableSignalInverted[blockIndex + (i-1)])
            pixelIndex[i] = tableSignalInverted[blockIndex + (i-1)]
        end
        
        local size = {}
        local totalSize = 0
        for i=1,4 do
            --print("pixelIndex[".. i+1 .."]=", pixelIndex[i+1],  "   -  pixelIndex[" .. i .."]=", pixelIndex[i])
            size[i] = pixelIndex[i+1] - pixelIndex[i]
            totalSize = totalSize + size[i]
        end
    
        local barUnitSize  = math.round(totalSize / 7)

        local value = {}
        local totalValue = 0
        for i=1,4 do
            value[i] = math.round(size[i]/barUnitSize)
            totalValue = totalValue + value[i]
        end

        if totalValue ~= 7 then     -- upc blocks needs to sum 7
            --print("Block " .. blockNumber .. " not read correclty - sum = ".. totalValue ..  "(~= 7) - trying to fix it")
            
            local remainders = {}
            for i=1,4 do
                remainders[i] = math.fmod(size[i], barUnitSize)
            end
            
            local possibleValues = {}
            for i=1, 4 do
                if remainders[i] ~= 0 then
                    possibleValues[i] = {math.ceil(size[i]/barUnitSize), math.floor(size[i]/barUnitSize)}                    
                else
                    possibleValues[i] = {value[i]}
                end
            end
            local sum = 0
            local index = 1
            
            local probableValues = {}
            for a=1,#possibleValues[1] do
                for b=1,#possibleValues[2] do
                    for c=1,#possibleValues[3] do
                        for d=1,#possibleValues[4] do
                            sum = possibleValues[1][a] + possibleValues[2][b] + possibleValues[3][c] + possibleValues[4][d]
                            if sum == 7 then
                                probableValues[index] = {}
                                probableValues[index] = {possibleValues[1][a],possibleValues[2][b],possibleValues[3][c],possibleValues[4][d] }
                                index = index + 1
                            end
                        end  
                    end    
                end
            end
            
            for i=#probableValues,1, -1 do                
                local code = probableValues[i][1] .. "-" .. probableValues[i][2] .. "-" .. probableValues[i][3] .. "-" .. probableValues[i][4]
                if upcCodeToValue[code] == nil then
                    probableValues[i] = nil
                end
            end
            
            if probableValues[1] then
                for i=1, 4 do
                    value[i] = probableValues[1][i]
                end                        
            else                
                --print("fixing block read failed")
                return 
            end
                                   
        end

        return value[1] .. "-" .. value[2] .. "-" .. value[3] .. "-" .. value[4]

    end
      

    local barCodeValue = {}
    local barCodeComplete = ""
    local barCodeCompleteTable = {}
    local numCharsNotIndentified = 0
    for i=1,12 do
        barCodeValue[i] = readUPCblock(i)
        print("barCodeValue["..i.."]=", barCodeValue[i], "   =   ", upcCodeToValue[barCodeValue[i]])
        if barCodeValue[i] == false then
            -- no more code to read
            break
        end
        if upcCodeToValue[barCodeValue[i]] then
            barCodeComplete = barCodeComplete  .. upcCodeToValue[barCodeValue[i]]
            barCodeCompleteTable[#barCodeCompleteTable+1] = upcCodeToValue[barCodeValue[i]]
        else
            barCodeComplete = barCodeComplete .. "X"
            barCodeCompleteTable[#barCodeCompleteTable+1] = "X"             
            numCharsNotIndentified = numCharsNotIndentified + 1
        end        
    end
    
    local barCodeLength = barCodeComplete:len()
    if numCharsNotIndentified == barCodeLength or barCodeLength ~= 12 then
        -- code was translated to entire XX...XX or has size ~= 12, meaning that this is not a UPC-12 bar code
        barCodeComplete = nil
        numCharsNotIndentified = 0
        barCodeCompleteTable = nil
    end
    
    print("BarCode = ", barCodeComplete,  " -- numCharsNotIndentified=", numCharsNotIndentified)
    
    return barCodeCompleteTable, numCharsNotIndentified, barCodeComplete
    
end

-- checks if upc bar code is valid by checking the first 11 digits with the check digit
local function validateUPCcode(barCode)
            
    local oddSum = barCode[1] +  barCode[3] +  barCode[5] +  barCode[7] +  barCode[9] +  barCode[11]
    local evenSum = barCode[2] +  barCode[4] +  barCode[6] +  barCode[8] +  barCode[10]
    
    local validationDigit = 10 - math.fmod((oddSum*3 + evenSum),10)
    if validationDigit == 10 then validationDigit = 0; end
    
    if barCode[12] == validationDigit then
        return true
    else
        return false, validationDigit
    end    
end

-- finds the missing code on a upc bar code
local function guessUPCcharNotIdentified(barCodeTable,charNotIdentifiedIndex)
    
   
    if charNotIdentifiedIndex == 12 then
        -- the missing digit is the validation code
        local trash, validitionDigit = validateUPCcode(barCodeTable)
        barCodeTable[12] = validitionDigit
    else
        -- lets "brute force" the missing digit
        for i=0,9 do
            barCodeTable[charNotIdentifiedIndex] = i
            if validateUPCcode(barCodeTable) then
                break                    
            end
        end            
    end
        
    
    return barCodeTable
    
end

-- merge several codes into one, considering the frequency of the chars to replace the unidentified chars
local function mergeReads(codesRead)
    
    if #codesRead == 0 then return end
    
    --local barCodeLength = string.len(codesRead[1].code)
    local barCodeLength = #(codesRead[1].codeTable) -- using the size of the first code read as the default size for all codes
    local indexWithCharsNotIndentified = {}
    local frequencyChar = {}
    
    local barCodeTable
    local value
    for i=1,barCodeLength do
        frequencyChar[i] = {}
        for j=1,#codesRead do
            barCodeTable = codesRead[j].codeTable
            value = barCodeTable[i]
            if value ~= "X" then
                frequencyChar[i][value] = (frequencyChar[i][value] and frequencyChar[i][value] + 1 ) or 1        
            end            
        end        
    end
    
    local function getHigherFrequencyKey(frequencyTable)        
        local lastValue = 0 
        local lastValueKey = nil
        for k,v in pairs(frequencyTable) do
                if v > lastValue then
                    lastValueKey = k
                    lastValue = v
                end
        end
        return lastValueKey
    end
    
    
            
    local newBarCodeTable = {}
    local newValue
    local numCharsNotIndentified = 0
    local charNotIndentifiedIndex = nil
    for i=1,barCodeLength do
        newValue = getHigherFrequencyKey(frequencyChar[i])
        if newValue == nil then
            newValue = "X"; numCharsNotIndentified = numCharsNotIndentified+1     
            charNotIndentifiedIndex= i
        end
        newBarCodeTable[i] = newValue
    end    
    
        
    return newBarCodeTable, numCharsNotIndentified, charNotIndentifiedIndex
    
end

-- get the next Y position to be read
local function getNextReadPosition(readNumber)
    
    local nextYposition
    local readerLine = rb.readerLine
    if math.fmod(readNumber,2) == 0 then
        -- lets read above guideline
        nextYposition = readerLine.contentBounds.yMin - 5*(readNumber/2)
    else
        -- lets read below guideline
        nextYposition = readerLine.contentBounds.yMax + 5*((readNumber+1)/2)
    end
    
    return nextYposition
end

-- reads the bar code
local function readCode(params)

    readingInProgress = true 
    
    local numberOfReadsToBeMade = params.readCount
    local numberOfReadsMade = 0
    
    local codesRead = {} --  will store all codes read
        
    rb.capturedScreen = display.captureScreen(false)
    rb.capturedScreen.x = rb.cameraShape.x
    rb.capturedScreen.y = rb.cameraShape.y
    
    local function finish(result, code)
        readingInProgress = false
        if params.onComplete then
            params.onComplete({result=result, code=code})
        end
    end
    
    
    local function onComplete(pixelList, pixelListSum)        
        
        --updateText("PROCESSING...")
        numberOfReadsMade = numberOfReadsMade + 1
        timer.performWithDelay(10, function()             
            
            local pixelListDiscreted = convertPixelListToBinary(pixelList, pixelListSum/#pixelList)

            local upcBarCodeTable, numCharsNotIndentified = calculateUPCbarCode(pixelListDiscreted)
                                    
            if upcBarCodeTable ~= nil and #upcBarCodeTable > 0 then
                if numCharsNotIndentified == 0 then
                    local result = validateUPCcode(upcBarCodeTable)
                    if result then
                        display.remove(rb.capturedScreen)
                        local upcBarCode = table.concat(upcBarCodeTable, "")
                        print("Bar Code found = ", upcBarCode)
                        finish(true, upcBarCode)
                        return
                    end
                end
                
                codesRead[#codesRead+1] = {}
                codesRead[#codesRead].codeTable = upcBarCodeTable
                codesRead[#codesRead].numCharsNotIndentified = numCharsNotIndentified
                
            end                        
            if numberOfReadsMade < numberOfReadsToBeMade then
                --updateText("READING #".. numberOfReadsMade + 1 .. "...")
                print(" = = = =  READING #".. numberOfReadsMade + 1 .. "...  = = = =")
                timer.performWithDelay(10, function()
                    
                    local readerYposition = getNextReadPosition(numberOfReadsMade+1)
                    readPixels(readerYposition - 30, onComplete)
                    
                end)
            else
                -- finished reading
                display.remove(rb.capturedScreen)
                if #codesRead == 0 then
                    print("No Bar Code Found!")
                    finish(false, nil)
                    return 
                end
                
                -- merging all reads into one, using frequency count to fill the not identified chars                   
                local mergedCodeTable, numXchars, charNotIndentifiedIndex = mergeReads(codesRead)                                
                
                if numXchars > 1 then
                    local mergedCode = table.concat(mergedCodeTable, "")
                    print("Finished - not possible to read the code. Best combined =",mergedCode )
                    finish(false, nil)
                    return  
                    
                elseif numXchars == 1 then
                    
                    -- if there is only 1 digit not identified, we can find it by brute force
                    mergedCodeTable = guessUPCcharNotIdentified(mergedCodeTable, charNotIndentifiedIndex)
                end
                
                local mergedCode = table.concat(mergedCodeTable, "")
                                                                                  
                if validateUPCcode(mergedCodeTable) then
                    print("Bar Code found")
                    finish(true, mergedCode)
                else
                    finish(false, nil)
                end
                
                return
            end
                                            
        end)
    end
    
    timer.performWithDelay(10, function()
        print(" = = = =  READING #".. numberOfReadsMade + 1 .. "...  = = = =")
        local readerYposition = getNextReadPosition(#codesRead+1)        
        readPixels(readerYposition, onComplete)
        
    end)
    
end




------------------------
-- Public Functions

-- shows the bar code reader on screen. The bar code reader is a guide line and a rect using Camera as texture and 
rb.show = function(params)
    
    -- possible params and their default values
    params = params or {}
    params.x = params.x or display.contentCenterX
    params.y = params.y or display.contentCenterY
    params.width = params.cameraWidth or display.contentWidth * 0.94
    params.height = params.cameraHeight or display.contentHeight * 0.5 
    params.fill = params.fill or {type = "camera"}
        
    -- showing reader on screen
    showReader(params)
end

-- function that reades the bar code 
rb.read = function(params)
    
    if readingInProgress then return end;
    
    -- possible params and their default values
    params = params or {}
    params.readCount = params.readCount or 3
    params.onComplete = params.onComplete
    
    
    -- start reading
    readCode(params)
    
end

-- function to be called when the reader is not more necessary. This is optional, but it is recommended due to performance. When Corona fixes the bug of the camera feed, this function will not be necessary anymore
rb.close = function()
    stopWorkAroundToKeepCameraRefreshing()
end

-- 
rb.setReaderWidth = function(self, newWidth)
    updateLineWidth(newWidth)
end

rb.getReaderWidth = function(self)
    return (rb.readerLine.contentBounds.xMax - rb.readerLine.contentBounds.xMin)
end

return rb
