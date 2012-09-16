
{Dictionary, PriorityQueue, defaultCompare} = require('../lib/buckets.js')

class CoordinateSpace
    constructor: (viewBox, targetDims) ->
        [@width, @height] = targetDims
        [@topLat, @leftLon, bottomLat, rightLon] = viewBox
        @lonRange = rightLon - @leftLon
        @latRange = bottomLat - @topLat

    toPixels: ([coordLat, coordLon]) ->
        [@width * (coordLon - @leftLon) / @lonRange,
         @height * (coordLat - @topLat) / @latRange]

class Canvas
    constructor: (canvasId, @cs) ->
        @canvas = document.getElementById canvasId
        @ctx = @canvas.getContext '2d'

    drawCircle: (point, radius=1, fill='black') =>
        [x, y] = @cs.toPixels(point)
        @ctx.beginPath()
        @ctx.arc(x, y, raduis, 0, 2*Math.PI)
        @ctx.fillStyle = fill
        @ctx.fill()

    drawPath: (path, strokeWidth=1, color='black') =>
        @ctx.beginPath()
        for point in path
            [x, y] = @cs.toPixels(point)
            @ctx.lineTo(x, y)
        @ctx.lineWidth = strokeWidth
        @ctx.strokeStyle = color
        @ctx.stroke()

class TransitData
    constructor: ->
        @coords = require('../computed/coords.json')
        @segments = require('../computed/segments.json')
        @graph = require('../computed/graph.json')

    getCoord: (coord) ->
        if coord[0] == undefined
            coordId = coord
            return [@coords[coordId], 1]
        else
            return [@coords[coord[0]], coord[1]]

    interpolate: (start, end, fraction) ->
        start + (end - start) * fraction

    interpolatePair: ([start1, start2], [end1, end2], fraction) ->
        [@interpolate(start1, end1, fraction),
         @interpolate(start2, end2, fraction)]

    decompressSegment: (segment) ->
        path = []
        for coordDescriptor, i in segment
            [coord, frac] = @getCoord coordDescriptor
            if frac == 1
                path.push coord
            else
                if i == 0
                    [nextCoord,] = @getCoord segment[1]
                    prevCoord = coord
                else
                    [prevCoord,] = @getCoord segment[i-1]
                    nextCoord = coord
                path.push @interpolatePair(prevCoord, nextCoord, frac)
        return path

    getSegment: (startNode, endNode) ->
        @decompressSegment(@segments[startNode][endNode])

    getSeglist: (n) ->
        seglist = []
        i = 0
        for firstStop, secondStops of @segments
            for secondStop, segment of secondStops
                seglist.push @decompressSegment(segment)
                if n and ++i == n
                    return seglist
        return seglist

class Traveller
    constructor: (@td, startNodes, startTime=0, @segmentCallback) ->
        lowFirst = ([a,], [b,]) -> defaultCompare(b, a)
        @minTimes = new Dictionary()
        @minTimeEdges = new Dictionary()
        @queue = new PriorityQueue(lowFirst)
        for node in startNodes
            @queue.enqueue [startTime, node]

    clockTo: (clockTime) ->
        while (not @queue.isEmpty()) and (@queue.peek()[0] <= clockTime)
            [time, stop, lastStop] = @queue.dequeue()
            if @minTimes.containsKey stop
                continue
            @minTimes.set stop, time
            if lastStop != undefined
                segment = @td.getSegment lastStop, stop
                @segmentCallback segment

            if stop not of @td.graph
                continue

            for nextStop, times of @td.graph[stop]
                lastDepartureTime = 0
                for trip in times
                    [departureTime, arrivalTime] = trip
                    departureTime += lastDepartureTime
                    if departureTime >= time
                        arrivalTime += departureTime
                        @queue.enqueue [arrivalTime, nextStop, stop]
                        @minTimeEdges.set([stop, nextStop], arrivalTime)
                        break
                    lastDepartureTime = departureTime
    
class Timer
    milis: ->
        date = new Date()
        date.getTime()

    startTimer: ->
        @lastMilis = @milis()

    checkTimer: ->
        return @milis() - @lastMilis

main = ->
    config = require('../config.json')

    cs = new CoordinateSpace(config.viewBox, config.canvasSize)
    canvas = new Canvas('client_canvas', cs)
    td = new TransitData()
    
    traveller = new Traveller(td, config.originStops, config.originTime, canvas.drawPath)

    clockStart = clock = 35500
    timer = new Timer()
    timer.startTimer()
    milis = timer.milis()
    incrClock = ->
        if timer.checkTimer() < 1
            webkitRequestAnimationFrame incrClock
            return
        timer.startTimer()
        clock = clockStart + (timer.milis() - milis) / 10
        traveller.clockTo clock
        if clock <= 60000
            webkitRequestAnimationFrame incrClock

    incrClock()
    #canvas.drawPath segment for segment in td.getSeglist()

main()
