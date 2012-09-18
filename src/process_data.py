
from argparse import ArgumentParser
from os.path import dirname, join
import os
import csv
from itertools import groupby
import json
from collections import defaultdict
from rtree import index
from math import cos, pi, sqrt


from joblib import Memory


CONFIG_FILE = 'config.json'

mem = Memory(join(dirname(__file__), '../cache'))

EARTH_CIRCUMFERENCE = 40075000 # meters
WALK_DIST = 30 # meters
WALK_SPEED = 1.35 # meters/s


def time_to_seconds(time):
    h, m, s = map(int, time.split(':'))
    return ((h * 60 + m) * 60) + s


def load_csv_data_file(filename):
    fh = file(join(dirname(__file__), '../', 'data', filename + '.txt'))
    return csv.DictReader(fh)


def load_config():
    if not hasattr(load_config, 'config'):
        config_file = file(join(dirname(__file__), '../', CONFIG_FILE))
        load_config.config = json.load(config_file)
    return load_config.config


def output_json(obj, filename):
    fh = file(join(output_dir(), filename + '.json'), 'w')

    json.dump(obj, fh)


def output_dir():
    computed_dir = join(dirname(__file__), '../', 'computed')
    try:
        os.mkdir(computed_dir)
    except OSError:
        pass
    return computed_dir


@mem.cache
def get_trip_to_type():
    route_type = dict()
    routes = load_csv_data_file('routes')
    for route in routes:
        route_type[route['route_id']] = int(route['route_type'])

    trip_type = dict()
    trips = load_csv_data_file('trips')
    for trip in trips:
        trip_type[trip['trip_id']] = route_type[trip['route_id']]

    return trip_type

@mem.cache
def generate_coords():
    shapes = load_csv_data_file('shapes')
    coords = dict()
    count = 0

    for shape in shapes:
        coord = (shape['shape_pt_lat'], shape['shape_pt_lon'])
        if coord in coords:
            continue
        coords[coord] = count
        count = count + 1

    return coords


@mem.cache
def generate_walking_graph():
    stops = load_csv_data_file('stops')
    stop_index = index.Index()

    walking_graph = {}
    stop_cache = dict()
    for stop in stops:
        stop['stop_id'] = int(stop['stop_id'])
        stop['stop_lon'] = float(stop['stop_lon'])
        stop['stop_lat'] = float(stop['stop_lat'])
        stop_cache[stop['stop_id']] = stop
        lon = float(stop['stop_lon'])
        lat = float(stop['stop_lat'])
        stop_id = stop['stop_id']

        stop_index.insert(stop_id, (lat, lon, lat, lon))

    min_lat, min_lon, max_lat, max_lon = stop_index.bounds
    mid_lat = (min_lat + max_lat) / 2
    lon_factor = cos(mid_lat * (pi/180)) ** 2 

    def point_distance((lat1, lon1), (lat2, lon2)):
        dist = sqrt((lat2 - lat1) ** 2 + (lon_factor * (lon2 - lon1)) ** 2)
        return dist * EARTH_CIRCUMFERENCE / 360

    def neigbour_bounding_box((lat, lon), distance):
        lat_bound = (float(distance) / EARTH_CIRCUMFERENCE) * 360
        lon_bound = lat_bound * lon_factor
        return (lat - lat_bound, lon - lon_bound, lat + lat_bound, lon + lon_bound)

    for stop_id, stop in stop_cache.iteritems():
        boundingbox = neigbour_bounding_box((stop['stop_lat'], stop['stop_lon']), WALK_DIST)
        neighbours = list(stop_index.intersection(boundingbox))
        for neighbour_id in neighbours:
            if neighbour_id == stop_id:
                continue
            neighbour = stop_cache[neighbour_id]
            dist = point_distance((stop['stop_lat'],
                                   stop['stop_lon']),
                                  (neighbour['stop_lat'],
                                   neighbour['stop_lon']))
            duration = int(dist / WALK_SPEED)
            walking_graph.setdefault(stop_id, list()).append([duration, neighbour['stop_id']])

    return walking_graph



def output_coords(coords):
    fh = file(join(output_dir(), 'coords.json'), 'w')
    coords_map = dict((v, k) for (k, v) in coords.iteritems())
    coords = (coords_map[i] for i in xrange(0, len(coords)))
    coords_list = [(float(lat), float(lon)) for lat, lon in coords]

    json.dump(coords_list, fh)


@mem.cache
def create_trip_set():
    service_ids = load_config()['serviceIds']
    trips = load_csv_data_file('trips')
    
    trip_set = set()

    for trip in trips:
        if trip['service_id'] in set(service_ids):
            trip_set.add(trip['trip_id'])

    return trip_set


@mem.cache
def create_graph(trip_set):
    stop_times = load_csv_data_file('stop_times')
    graph = dict()

    for trip, stops in groupby(stop_times, lambda x: x['trip_id']):
        if trip not in trip_set:
            continue
        previous_stop = stops.next()
        for stop in stops:
            graph.setdefault(int(previous_stop['stop_id']), dict()) \
                 .setdefault(int(stop['stop_id']), list()) \
                 .append([
                     time_to_seconds(previous_stop['departure_time']),
                     time_to_seconds(stop['arrival_time'])
                 ])
            previous_stop = stop

    # compress stop times by taking a delta
    for first_stop, second_stops in graph.iteritems():
        for second_stop, stop_times in second_stops.iteritems():
            stop_times.sort()
            previous_time = stop_times[0][0]
            for i in xrange(1, len(stop_times)):
                stop_times[i][1] -= stop_times[i][0]
                previous_time, stop_times[i][0] = \
                  (stop_times[i][0], stop_times[i][0] - previous_time)

    return graph

@mem.cache
def get_stops():
    stops = load_csv_data_file('stops')
    return list((
        stop['stop_id'],
        stop['stop_code'],
        stop['stop_name'],
        stop['stop_lat'],
        stop['stop_lon']) for stop in stops)

@mem.cache
def load_trips_to_shapes(trip_set):
    trips = load_csv_data_file('trips')
    
    trips_to_shapes = dict()
    for trip in trips:
        trips_to_shapes[trip['trip_id']] = trip['shape_id']

    return trips_to_shapes


@mem.cache
def get_shapes_to_stop_set(trip_set, trip_types):
    shapes_to_stop_set = dict()
    trips_to_shapes = load_trips_to_shapes(trip_set)
    stop_times = load_csv_data_file('stop_times')
    for trip_id, stops in groupby(stop_times, lambda x: x['trip_id']):
        trip_type = trip_types[trip_id]
        shape_id = trips_to_shapes[trip_id]
        stop_set = shapes_to_stop_set.setdefault(shape_id, set())
        if trip_id not in trip_set:
            continue
        
        stop_set.add((trip_type, tuple((stop['stop_id'], float(stop['shape_dist_traveled'] or 0))
              for stop in stops)))

    return shapes_to_stop_set


@mem.cache
def get_segments(trip_set, coords, shapes_to_stop_set):
    shapes_to_stop_set

    shapes = load_csv_data_file('shapes')

    segments = dict()
    for shape_id, points in groupby(shapes, lambda x: x['shape_id']):
        points_latlon = [
            ((coords[p['shape_pt_lat'], p['shape_pt_lon']]), float(p['shape_dist_traveled']))
                for p in points]

        for (trip_type, stops) in shapes_to_stop_set[shape_id]:
            stops = iter(stops)
            points_iter = iter(points_latlon)

            previous_stop, dist_travelled = stops.next()
            assert dist_travelled == 0

            start_point, dist_travelled = points_iter.next()
            assert dist_travelled == 0
            path = [start_point]

            take_next = True
            for stop_id, stop_dist in stops:
                while dist_travelled < stop_dist:
                    if take_next:
                        next_point, new_dist_travelled = points_iter.next()

                    if new_dist_travelled < stop_dist:
                        path.append(next_point)
                        dist_travelled = new_dist_travelled
                        take_next = True

                    else:
                        if new_dist_travelled > dist_travelled:
                            dist_needed = stop_dist - dist_travelled
                            segment_dist = new_dist_travelled - dist_travelled
                            segment_fraction = round(dist_needed / segment_dist, 3)

                            if isinstance(path[-1], list):
                                new_path = [[path[-1][0], segment_fraction]]
                                path.append([next_point, segment_fraction + path[-1][1]])
                            else:
                                new_path = [[path[-1], segment_fraction]]
                                path.append([next_point, segment_fraction])

                            take_next = False
                        else:
                            take_next = True
                            path.append(next_point)
                            new_path = [next_point]

                        segments.setdefault(previous_stop, dict())[stop_id] = (trip_type, path)

                        previous_stop = stop_id

                        path = new_path
                        dist_travelled = stop_dist

    return segments


def main():
    parser = ArgumentParser()
    parser.add_argument('--output-coords', action='store_true')
    parser.add_argument('--output-segments', action='store_true')
    parser.add_argument('--output-graph', action='store_true')
    parser.add_argument('--output-walking-graph', action='store_true')
    parser.add_argument('--output-stops', action='store_true')
    args = parser.parse_args()

    coords = generate_coords()
    
    if args.output_coords:
        output_coords(coords)
    
    if args.output_segments or args.output_graph:
        trip_set = create_trip_set()

    if args.output_segments:
        trip_types = get_trip_to_type()
        shapes_to_stop_set = get_shapes_to_stop_set(trip_set, trip_types)
        segments = get_segments(trip_set, coords, shapes_to_stop_set)
        output_json(segments, 'segments')

    if args.output_graph:
        graph = create_graph(trip_set)
        output_json(graph, 'graph')

    if args.output_walking_graph:
        walking_graph = generate_walking_graph()
        output_json(walking_graph, 'walkinggraph')

    if args.output_stops:
        stops = get_stops()
        output_json(stops, 'stops')

if __name__ == '__main__':
    main()

