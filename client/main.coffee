
#graph = require('../computed/graph.json')
coords = require('../computed/coords.json')
segments = require('../computed/segments.json')

###
PriorityQueue = require('../lib/buckets.js')
###

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

    drawCircle: (point, radius=1, fill='black') ->
        [x, y] = @cs.toPixels(point)
        @ctx.beginPath()
        @ctx.arc(x, y, raduis, 0, 2*Math.PI)
        @ctx.fillStyle = fill
        @ctx.fill()

    drawPath: (path, strokeWidth=1, color='black') ->
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

    getSeglist: (n) ->
        seglist = []
        i = 0
        for firstStop, secondStops of @segments
            for secondStop, segment of secondStops
                seglist.push @decompressSegment(segment)
                if n and ++i == n
                    return seglist
        return seglist

main = ->
    config = require('../config.json')

    cs = new CoordinateSpace(config.viewbox, config.canvas_size)
    canvas = new Canvas('client_canvas', cs)
    td = new TransitData()
    
    canvas.drawPath segment for segment in td.getSeglist()

main()
