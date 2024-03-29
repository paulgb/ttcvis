
{Dictionary, PriorityQueue, defaultCompare} = require('../lib/buckets.js')
{kdTree} = require('../lib/kdTree.js')

lowFirst = ([a,], [b,]) -> defaultCompare(b, a)

interpolate = (start, end, fraction) ->
    start + (end - start) * fraction

interpolatePair = ([start1, start2], [end1, end2], fraction) ->
    [interpolate(start1, end1, fraction),
     interpolate(start2, end2, fraction)]

pointDist = (pt1, pt2) ->
    midLat = (pt1.lat + pt2.lat) / 2
    lonFactor = Math.pow(Math.cos(midLat * (Math.PI / 180)), 2)
    dist = Math.sqrt(Math.pow(pt2.lat - pt1.lat, 2) + Math.pow(lonFactor * (pt2.lon - pt1.lon), 2))
    return dist

# coffeescript port of Paul Irish's requestAnimFrame shim
# http://paulirish.com/2011/requestanimationframe-for-smart-animating/
requestAnimFrame =
    window.requestAnimationFrame       ?
    window.webkitRequestAnimationFrame ?
    window.mozRequestAnimationFrame    ?
    window.oRequestAnimationFrame      ?
    window.msRequestAnimationFrame     ?
    (callback -> window.setTimeout callback, 1000 / 60)

class CoordinateSpace
    constructor: (viewBox) ->
        [@bottomLat, @leftLon, @topLat, @rightLon, @innerExpand] = viewBox

    apply: (targetDims) ->
        [@destWidth, @destHeight] = targetDims
        midLon = (@leftLon + @rightLon) / 2
        midLat = (@topLat + @bottomLat) / 2
        lonMultiplier = Math.pow(Math.cos(midLat * (Math.PI/180)), 2)

        srcWidth = (@rightLon - @leftLon)
        srcWidthAdjusted = srcWidth * lonMultiplier
        srcHeight = (@topLat - @bottomLat)

        scaleWidth = @destWidth / srcWidthAdjusted
        scaleHeight = @destHeight / srcHeight

        sigWidth = sigHeight = 1
        if scaleWidth < 0
            scaleWidth = -scaleWidth
            sigWidth = -1
        if scaleHeight < 0
            scaleHeight = -scaleHeight
            sigHeight = -1

        if (scaleWidth < scaleHeight) == @innerExpand
            srcWidthAdjusted = (@destWidth / scaleHeight) * sigWidth
            srcWidth = srcWidthAdjusted / lonMultiplier
            @leftLon = midLon - (srcWidth / 2)
            @rightLon = midLon + (srcWidth / 2)
        else
            srcHeight = (@destHeight / scaleWidth) * sigHeight
            @topLat = midLat + (srcHeight / 2)
            @bottomLat = midLat - (srcHeight / 2)
        
        @lonRange = @rightLon - @leftLon
        @latRange = @bottomLat - @topLat

    toCoords: ([x, y]) ->
        [(y * @latRange / @destHeight) + @topLat,
         (x * @lonRange / @destWidth) + @leftLon]

    toPixels: ([coordLat, coordLon]) ->
        [@destWidth * (coordLon - @leftLon) / @lonRange,
         @destHeight * (coordLat - @topLat) / @latRange]

class Canvas
    constructor: (canvasId) ->
        @canvas = document.getElementById canvasId
        @canvas.width = window.innerWidth
        @canvas.height = window.innerHeight
        @ctx = @canvas.getContext '2d'
        @time = 0

    setCoordinateSpace: (@cs) ->
        @cs.apply [@canvas.width, @canvas.height]

    reset: () =>
        @ctx.clearRect(0, 0, @canvas.width, @canvas.height)

    drawCircle: (point, radius=1, fill='white') =>
        [x, y] = @cs.toPixels(point)
        @ctx.beginPath()
        @ctx.arc(x, y, raduis, 0, 2*Math.PI)
        @ctx.fillStyle = fill
        @ctx.fill()

    drawPath: (path, strokeWidth=1, color='white') =>
        @ctx.beginPath()
        for point in path
            [x, y] = @cs.toPixels(point)
            @ctx.lineTo(x, y)
        @ctx.lineWidth = strokeWidth
        @ctx.strokeStyle = color
        @ctx.stroke()

    euclidean: (point1, point2) ->
        [x1, y1] = point1
        [x2, y2] = point2
        Math.sqrt(Math.pow(x1 - x2, 2) + Math.pow(y1 - y2, 2))

    pathDistance: (path) ->
        dist = 0
        lastPoint = path[0]
        for point in path[1..]
            dist += @euclidean lastPoint, point
            lastPoint = point
        return dist
    
    cutPath: (path, cutDist) ->
        dist = 0
        lastPoint = path[0]

        for i in [1...path.length]
            point = path[i]
            nextDist = @euclidean lastPoint, point
            if dist + nextDist >= cutDist
                frac = (cutDist - dist) / nextDist
                midPoint = interpolatePair lastPoint, point, frac

                beforeCut = path[0...i]
                afterCut = path[i...]
                beforeCut.push(midPoint)
                afterCut.unshift(midPoint)

                return [beforeCut, afterCut]
            lastPoint = point
            dist += nextDist
        return [path, []]
            
    clockTo: (time) =>
        @time = time

    animatePath: (path, startTime, endTime, pathDist=@pathDistance(path), distCovered=0, strokeWidth=1, color='white') =>
        frac = Math.max((@time - startTime) / (endTime - startTime), 1)
        distNeeded = frac * pathDist
        [usePath, savePath] = @cutPath path, distNeeded - distCovered

        @drawPath usePath, strokeWidth, color

        if (@time < endTime) and savePath.length
            callback = => @animatePath(savePath, startTime, endTime, pathDist, distCovered, color)
            setTimeout(callback, 10)


class TransitData
    constructor: ->
        @coords = require('../computed/coords.json')
        @segments = require('../computed/segments.json')
        @graph = require('../computed/graph.json')
        @walkingGraph = require('../computed/walkinggraph.json')
        stops = require('../computed/stops.json')
        
        @stops = [@decompressStop(stop) for stop in stops][0]
        @stopsTree = new kdTree(@stops, pointDist, ['lat', 'lon'])

    getCoord: (coord) ->
        if coord[0] == undefined
            coordId = coord
            return [@coords[coordId], 1]
        else
            return [@coords[coord[0]], coord[1]]

    decompressStop: (stop) ->
        stop =
            id: stop[0]
            code: stop[1]
            name: stop[2]
            lat: parseFloat(stop[3])
            lon: parseFloat(stop[4])
        return stop

    decompressSegment: (segment) ->
        [tripType, coords] = segment
        path = []
        for coordDescriptor, i in coords
            [coord, frac] = @getCoord coordDescriptor
            if frac == 1
                path.push coord
            else
                if i == 0
                    [nextCoord,] = @getCoord coords[1]
                    prevCoord = coord
                else
                    [prevCoord,] = @getCoord coords[i-1]
                    nextCoord = coord
                path.push interpolatePair(prevCoord, nextCoord, frac)
        return [tripType, path]

    getSegment: (startNode, endNode) ->
        @decompressSegment(@segments[startNode][endNode])

class Traveller
    constructor: (@td, startNode, startTime=0, @segmentCallback) ->
        @minTimes = new Dictionary()
        @minTimeEdges = new Dictionary()
        @queue = new PriorityQueue(lowFirst)
        @minSoFar = new Dictionary()
        @queue.enqueue [startTime, startNode]

    clockTo: (clockTime) ->
        while (not @queue.isEmpty()) and (@queue.peek()[0] <= clockTime)
            [time, stop] = @queue.dequeue()
            if @minTimes.containsKey stop
                continue
            @minTimes.set stop, time

            if stop not of @td.graph
                continue

            for neighbour in @td.walkingGraph[stop] ? []
                [duration, nextStop] = neighbour
                arrivalTime = time + duration
                if (not @minSoFar.containsKey(nextStop)) or (@minSoFar.get(nextStop) > arrivalTime)
                    @queue.enqueue [arrivalTime, nextStop]

            for nextStop, times of @td.graph[stop]
                lastDepartureTime = 0
                for trip in times
                    [departureTime, arrivalTime] = trip
                    departureTime += lastDepartureTime
                    if departureTime >= time
                        arrivalTime += departureTime
                        if (not @minSoFar.containsKey(nextStop)) or (@minSoFar.get(nextStop) > arrivalTime)
                            @queue.enqueue [arrivalTime, nextStop]
                            @minTimeEdges.set([stop, nextStop], arrivalTime)
                        [tripType, segment] = @td.getSegment stop, nextStop
                        @segmentCallback(segment, departureTime, arrivalTime, tripType)
                        break
                    lastDepartureTime = departureTime
        if @queue.isEmpty()
            @doneCallback()
            return
    
class SimController
    constructor: (@time, @speed, @tickCallback) ->
        @running = false
        @started = false

    milis: ->
        date = new Date()
        date.getTime()

    updateClock: =>
        if @running
            @time = @clockStart + (@milis() - @startMilis) * @speed
            @tickCallback(@time)
            requestAnimFrame @updateClock

    setSpeed: (@speed) =>
        @startTime = @time

    setTime: (@time) =>
        @clockStart = @time

    step: (delta) =>
        if not @started
            if @startCallback
                @startCallback()
        @started = true
        @time += delta
        @tickCallback(@time)

    rew: (@time) =>
        @clockStart = @time
        @started = false
        @running = false

    play: =>
        if not @started
            if @startCallback
                @startCallback()
        @clockStart = @time
        @started = true
        @running = true
        @startMilis = @milis()
        @updateClock()

    pause: =>
        @running = false

class SimUI
    constructor: (@controller, @viewBoxes, @stop) ->
        @clockTime = document.getElementById('clock_time')
        @clockDaypart = document.getElementById('clock_daypart')
        @playButton = document.getElementById('play_btn')
        @rewButton = document.getElementById('rew_btn')
        @stepButton = document.getElementById('step_btn')
        @speedSelect = document.getElementById('speed')
        @startSelect = document.getElementById('startTime')
        @zoomSelect = document.getElementById('zoom')
        @stopElement = document.getElementById('stopid')
        @setStop(@stop)

        for name, dims of @viewBoxes
            option = document.createElement('option')
            option.innerHTML = name
            option.value = name
            @zoomSelect.appendChild(option)

        for time in [16...40]
            startTime = time * 1800
            option = document.createElement('option')
            option.innerHTML = @humanTime(startTime)
            option.value = startTime
            @startSelect.appendChild(option)

        @playButton.onclick = =>
            if @controller.running
                @playButton.innerText = 'Play'
                @rewButton.disabled = false
                @stepButton.disabled = false
                @controller.pause()
            else
                if not @controller.started
                    @controller.setTime parseInt(@startSelect.value)
                    @onViewbox(@viewBoxes[@zoomSelect.value])
                @playButton.innerText = 'Pause'
                @rewButton.disabled = true
                @stepButton.disabled = true
                @controller.play()

        @rewButton.onclick = =>
            @controller.rew parseInt(@startSelect.value)

        @stepButton.onclick = =>
            @controller.step 600

        @speedSelect.onchange = =>
            @controller.setSpeed @speedSelect.value

    setStop: (@stop) ->
        @stopElement.innerText = @stop.name

    humanTime: (clock, sep=false) ->
        days = ['Monday', 'Tuesday']
        halfdays = ['AM', 'PM']
        
        ONE_MINUTE = 60
        ONE_HOUR = 60 * ONE_MINUTE
        ONE_HALFDAY = 12 * ONE_HOUR
        ONE_DAY = 2 * ONE_HALFDAY

        day = Math.floor(clock / ONE_DAY)
        halfday = Math.floor((clock % ONE_DAY) / ONE_HALFDAY)
        hour = Math.floor((clock % ONE_HALFDAY) / ONE_HOUR) % ONE_HALFDAY
        hour = 12 if hour == 0
        minute = Math.floor((clock % ONE_HOUR) / ONE_MINUTE)
        minute = minute = "0" + minute if minute < 10
        if sep
            return ["#{hour}:#{minute}", "#{halfdays[halfday]}"]
        else
            return "#{hour}:#{minute} #{halfdays[halfday]}"

    clockTo: (clock) ->
        [@clockTime.innerHTML, @clockDaypart.innerHTML] = @humanTime clock, true


class InfoBox
    constructor: (@canvas, @td, @ui, @traveller) ->
        @boxElement = document.getElementById('stop_info')
        @nameElement = document.getElementById('stop_name')
        @reachedElement = document.getElementById('stop_reached')

    click: (e) =>
        [lat, lon] = @canvas.cs.toCoords([e.clientX, e.clientY])
        [[point, dist]] = @td.stopsTree.nearest({lat: lat, lon: lon}, 1)
        if dist < 0.005
            @ui.setStop(point)

    updateInfoBox: (e) =>
        [lat, lon] = @canvas.cs.toCoords([e.clientX, e.clientY])
        [[point, dist]] = @td.stopsTree.nearest({lat: lat, lon: lon}, 1)
        if dist < 0.005
            @nameElement.innerHTML = point.name
            minTime = @traveller.minTimes.get point.id
            if minTime != undefined
                @reachedElement.innerText = 'Time reached ' + @ui.humanTime minTime
            else
                @reachedElement.innerText = 'Not yet reached'
            @boxElement.style.display = ''
        else
            @boxElement.style.display = 'none'


main = ->
    config = require('../config.json')

    canvas = new Canvas('client_canvas')
    td = new TransitData()
    tripColors = ['red', 'white', null, 'pink']
    thickness = [1, 3, null, 0.5]
    infobox = new InfoBox(canvas, td)
    
    segmentCallback = (segment, departureTime, arrivalTime, tripType) =>
        canvas.animatePath(segment, departureTime, arrivalTime, null, null, thickness[tripType], tripColors[tripType])

    traveller = null
    controller = new SimController(36000, 1, (clock) ->
        canvas.clockTo clock
        traveller.clockTo clock
        ui.clockTo clock
    )

    controller.startCallback = =>
        canvas.reset()
        traveller = new Traveller(td, ui.stop.id, controller.time, segmentCallback)
        traveller.doneCallback = controller.pause
        infobox.traveller = traveller

    ui = new SimUI(controller, config.viewBoxes, config.originStop)
    infobox.ui = ui

    ui.onViewbox = (viewbox) =>
        cs = new CoordinateSpace(viewbox)
        canvas.setCoordinateSpace cs

        canvas.canvas.onmousemove = infobox.updateInfoBox
        canvas.canvas.onclick = infobox.click

        

main()
