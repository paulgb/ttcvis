
from argparse import ArgumentParser
from os.path import dirname, join
import os
import csv
from itertools import groupby
import json
from collections import defaultdict


from joblib import Memory


CONFIG_FILE = 'config.json'

mem = Memory(join(dirname(__file__), '../cache'))


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


def output_coords(coords):
    fh = file(join(output_dir(), 'coords.json'), 'w')
    coords_map = dict((v, k) for (k, v) in coords.iteritems())
    coords = (coords_map[i] for i in xrange(0, len(coords)))
    coords_list = [(float(lat), float(lon)) for lat, lon in coords]

    json.dump(coords_list, fh)


@mem.cache
def create_trip_set():
    service_ids = load_config()['service_ids']
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
def load_stops():
    stops = load_csv_data_file('stops')
    return dict((stop['stop_id'], stop) for stop in stops)


@mem.cache
def load_trips_to_shapes(trip_set):
    trips = load_csv_data_file('trips')
    
    trips_to_shapes = dict()
    for trip in trips:
        trips_to_shapes[trip['trip_id']] = trip['shape_id']

    return trips_to_shapes


@mem.cache
def get_shapes_to_stop_set(trip_set):
    shapes_to_stop_set = dict()
    trips_to_shapes = load_trips_to_shapes(trip_set)
    stop_times = load_csv_data_file('stop_times')
    for trip_id, stops in groupby(stop_times, lambda x: x['trip_id']):
        shape_id = trips_to_shapes[trip_id]
        stop_set = shapes_to_stop_set.setdefault(shape_id, set())
        if trip_id not in trip_set:
            continue
        
        stop_set.add(tuple((stop['stop_id'], float(stop['shape_dist_traveled'] or 0))
              for stop in stops))

    return shapes_to_stop_set


@mem.cache
def get_segments(trip_set, coords):
    shapes_to_stop_set = get_shapes_to_stop_set(trip_set)

    shapes = load_csv_data_file('shapes')

    segments = dict()
    for shape_id, points in groupby(shapes, lambda x: x['shape_id']):
        points_latlon = [
            ((coords[p['shape_pt_lat'], p['shape_pt_lon']]), float(p['shape_dist_traveled']))
                for p in points]

        trip_segments = dict()
        for stops in shapes_to_stop_set[shape_id]:
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
                        path.append([next_point, 1.0])
                        dist_travelled = new_dist_travelled
                        take_next = True

                    else:
                        if new_dist_travelled > dist_travelled:
                            dist_needed = stop_dist - dist_travelled
                            segment_dist = new_dist_travelled - dist_travelled
                            segment_fraction = round(dist_needed / segment_dist, 3)

                            new_path = [[path[-1], segment_fraction]]
                            path.append([next_point, segment_fraction])
                            take_next = False
                        else:
                            take_next = True
                            path.append([next_point, 1.0])
                            new_path = [next_point]

                        trip_segments['%s_%s' % (previous_stop, stop_id)] = path

                        previous_stop = stop_id

                        path = new_path
                        dist_travelled = stop_dist

        segments.update(trip_segments)

    return segments


def main():
    parser = ArgumentParser()
    parser.add_argument('--output-coords', action='store_true')
    parser.add_argument('--output-segments', action='store_true')
    parser.add_argument('--output-graph', action='store_true')
    args = parser.parse_args()

    config = load_config()

    coords = generate_coords()
    
    if args.output_coords:
        output_coords(coords)
    
    if args.output_segments or args.output_graph:
        trip_set = create_trip_set()

    if args.output_segments:
        segments = get_segments(trip_set, coords)
        output_json(segments, 'segments')

    if args.output_graph:
        graph = create_graph(trip_set)
        output_json(graph, 'graph')

if __name__ == '__main__':
    main()

