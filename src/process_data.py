
from os.path import dirname, join
import os
import csv
from itertools import groupby
import json
from Queue import PriorityQueue


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


@mem.cache
def create_trip_set(service_ids):
    trips = load_csv_data_file('trips')
    
    trip_set = set()

    for trip in trips:
        if trip['service_id'] in set(service_ids):
            trip_set.add(trip['trip_id'])

    return trip_set


@mem.cache
def create_graph(trip_set):
    stop_times = load_csv_data_file('stop_times')
    edges = dict()

    for trip, stops in groupby(stop_times, lambda x: x['trip_id']):
        if trip not in trip_set:
            continue
        previous_stop = stops.next()
        for stop in stops:
            edges.setdefault(previous_stop['stop_id'], dict()) \
                 .setdefault(stop['stop_id'], set()) \
                 .add((
                     time_to_seconds(previous_stop['departure_time']),
                     time_to_seconds(stop['arrival_time'])))
            previous_stop = stop

    return edges


@mem.cache
def get_origin_stop_ids(origin_stop):
    stops = load_csv_data_file('stops')
    stop_ids = set()
    for stop in stops:
        if stop['stop_code'] in origin_stop:
            stop_ids.add(stop['stop_id'])
    
    return stop_ids


@mem.cache
def shortest_path_to_edges(edges, origin_time, origin_stops):
    queue = PriorityQueue()

    min_time = dict()
    min_time_edge = dict()

    for origin_stop in origin_stops:
        queue.put((origin_time, origin_stop))

    while not queue.empty():
        (time, stop) = queue.get()
        print time, stop
        if stop in min_time:
            continue
        min_time[stop] = time

        if stop not in edges:
            print stop, 'has no out edges'
            # no out-edges
            continue
        for next_stop, times in edges[stop].iteritems():
            try:
                next_stop_time = min(arr for dep, arr in times if dep > time)
            except ValueError:
                # the node is unreachable
                print 'got here'
                continue
            queue.put((next_stop_time, next_stop))
            min_time_edge[(stop, next_stop)] = next_stop_time

    return min_time_edge


@mem.cache
def load_stops():
    stops = load_csv_data_file('stops')
    return dict((stop['stop_id'], stop) for stop in stops)


def output_dir():
    computed_dir = join(dirname(__file__), '../', 'computed')
    try:
        os.mkdir(computed_dir)
    except OSError:
        pass
    return computed_dir


@mem.cache
def output_edges(stops, min_time_edge):
    fh = file(join(output_dir(), 'edges.csv'), 'w')
    writer = csv.writer(fh)

    writer.writerow(('start_stop_id', 'start_stop_lat', 'start_stop_lon',
        'end_stop_id', 'end_stop_lat', 'end_stop_lon', 'end_time'))

    for (start_stop_id, end_stop_id), time in min_time_edge.iteritems():
        start_stop = stops[start_stop_id]
        end_stop = stops[end_stop_id]
        writer.writerow((
            start_stop['stop_id'],
            start_stop['stop_lat'],
            start_stop['stop_lon'],
            end_stop['stop_id'],
            end_stop['stop_lat'],
            end_stop['stop_lon'],
            time))


@mem.cache
def load_shapes_to_trips():
    trips = load_csv_data_file('trips')
    
    shapes_to_trips = dict()
    trips_to_shapes = dict()
    for trip in trips:
        if trip['shape_id'] not in shapes_to_trips:
            shapes_to_trips[trip['shape_id']] = trip['trip_id']
            trips_to_shapes[trip['trip_id']] = trip['shape_id']

    return shapes_to_trips, trips_to_shapes


@mem.cache
def output_segments(segments):
    fh = file(join(output_dir(), 'segments.csv'), 'w')
    writer = csv.writer(fh)

    writer.writerow(('start_stop_id', 'end_stop_id', 'point_lat', 'point_lon'))

    for (start_stop_id, end_stop_id), path in segments:
        for point in path:
            writer.writerow((start_stop_id, end_stop_id, point[0], point[1]))


@mem.cache
def get_segments():
    shapes = load_csv_data_file('shapes')
    shapes_to_trips, trips_to_shapes = load_shapes_to_trips()
    stop_times = load_csv_data_file('stop_times')
    segments = []

    trips = dict()
    for trip, stops in groupby(stop_times, lambda x: x['trip_id']):
        if trip not in trips_to_shapes:
            continue
        
        shape_id = trips_to_shapes[trip]
        trips[shape_id] = [(stop['stop_id'], float(stop['shape_dist_traveled'] or 0)) for stop in stops]

    for shape_id, points in groupby(shapes, lambda x: x['shape_id']):
        points_latlon = (
            ((float(p['shape_pt_lat']), float(p['shape_pt_lon'])), float(p['shape_dist_traveled']))
                for p in points)
        trip = iter(trips[shape_id])
        trip_segments = []

        previous_stop, dist_travelled = trip.next()
        assert dist_travelled == 0

        start_point, dist_travelled = points_latlon.next()
        assert dist_travelled == 0
        path = [start_point]

        take_next = True
        for stop_id, stop_dist in trip:
            while dist_travelled < stop_dist:
                if take_next:
                    next_point, new_dist_travelled = points_latlon.next()

                if new_dist_travelled < stop_dist:
                    path.append(next_point)
                    dist_travelled = new_dist_travelled
                    take_next = True

                else:
                    if new_dist_travelled > dist_travelled:
                        dist_needed = stop_dist - dist_travelled
                        segment_dist = new_dist_travelled - dist_travelled
                        segment_fraction = dist_needed / segment_dist

                        last_lat, last_lon = path[-1]
                        new_lat, new_lon = next_point
                        end_lat = last_lat + (new_lat - last_lat) * segment_fraction
                        end_lon = last_lon + (new_lon - last_lon) * segment_fraction
                        take_next = False
                        path.append((end_lat, end_lon))
                    else:
                        take_next = True
                        path.append(next_point)

                    trip_segments.append(((previous_stop, stop_id), path))
                    previous_stop = stop_id
                    path = path[-1:]
                    dist_travelled = stop_dist

        segments.extend(trip_segments)

    return segments


def main():
    print 'loading config'
    config = load_config()
    print 'loading trip set'
    trip_set = create_trip_set(config['service_ids'])
    print 'loading edges'
    edges = create_graph(trip_set)
    print 'loading stop ids'
    stop_ids = get_origin_stop_ids(config['origin_stops'])
    print 'calculating minimum edge times'
    min_time_edge = shortest_path_to_edges(edges, config['origin_time'], stop_ids)
    print 'loading stops'
    stops = load_stops()
    print 'writing edges'
    output_edges(stops, min_time_edge)

    print 'creating segments'
    segments = get_segments()
    print 'writing segments'
    output_segments(segments)


if __name__ == '__main__':
    main()

