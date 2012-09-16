
#graph = require('../computed/graph.json')
coords = require('../computed/coords.json')
segments = require('../computed/segments.json')

###
PriorityQueue = require('../lib/buckets.js')
###

main = ->
    config = require('../config.json')
    [lon_min, lat_min, lon_max, lat_max] = config.viewbox

    canvas_width = 1200
    canvas_height = 600

    canvas = document.getElementById 'client_canvas'
    ctx = canvas.getContext '2d'

    drawCircle = ([lat, lon]) ->
        ctx.beginPath()
        ctx.arc(to_x(lon), to_y(lat), 1, 0, 2*Math.PI)
        ctx.fillStyle = 'red'
        ctx.fill()

    to_x = (k) ->
        canvas_width * (k - lon_min) / (lon_max - lon_min)

    to_y = (k) ->
        canvas_height * (k - lat_min) / (lat_max - lat_min)

    seglist = []
    for first_stop, second_stops of segments
        for second_stop, path of second_stops
            seglist.push path

    drawSegment = (path) ->
        ctx.beginPath()
        for point in path
            if point[0] == undefined
                p = coords[point]
            else
                p = coords[point[0]]
            [lat, lon] = p
            ctx.lineTo(to_x(lon), to_y(lat))
        ctx.lineWidth = 1
        ctx.strokeStyle = 'black'
        ctx.stroke()


    x = 0
    drawSegments = ->
        drawSegment seg for seg in seglist[x..(x+100)]
        x = x + 100
        webkitRequestAnimationFrame drawSegments

    drawSegments()

main()
