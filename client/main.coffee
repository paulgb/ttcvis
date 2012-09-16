
#graph = require('../computed/graph.json')
coords = require('../computed/coords.json')
segments = require('../computed/segments.json')

###
PriorityQueue = require('../lib/buckets.js')
###

class CoordinateSpace
    constructor: (viewbox, target_dims) ->
        [@width, @height] = target_dims
        [@top_lat, @left_lon, right_lat, bottom_lon] = viewbox
        @lon_range = right_lon - @left_lon
        @lat_range = bottom_lon - @top_lat

    toPixels: ([coord_lat, coord_lon]) ->
        [@width * (coord_lon - @left_lon) / @lon_range,
         @height * (coord_lat - @top_lat) / @lat_range]

class Canvas
    constructor: ->
        @canvas = document.getElementById 'client_canvas'
        @ctx = @canvas.getContext '2d'

    drawCircle = ([x, y], radius=1, fill='black') ->
        ctx.beginPath()
        ctx.arc(x, y, raduis, 0, 2*Math.PI)
        ctx.fillStyle = fill
        ctx.fill()

    drawPath = (path, strokeWidth=1, color='black') ->
        ctx.beginPath()
        for [x, y] in path
            ctx.lineTo(x, y)
        ctx.lineWidth = strokeWidth
        ctx.strokeStyle = color
        ctx.stroke()

class TransitData
    constructor: ->
        @coords = require('../computed/coords.json')
        @segments = require('../computed/segments.json')

    getCoord: (coord) ->
        if coord[0] == undefined
            coord_id = coord
            return [@coords[coord_id], 1]
        else
            return [@coords[coord[0]], coord[1]]

    interpolate: (start, end, fraction) ->
        return start + (end - start) * fraction

    interpolatePair: ([start1, start2], [end1, end2], fraction) ->
        [@interpolate(start1, end1, fraction),
         @interpolate(start2, end2, fraction)]

    segmentToPath: (segment) ->
        path = []
        for coord_descriptor, i in segment
            coord, frac = getCoord coord_descriptor
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


main = ->
    config = require('../config.json')
    [lon_min, lat_min, lon_max, lat_max] = config.viewbox

    cs = new CoordinateSpace(config.viewbox, config.canvasSize)


main()
