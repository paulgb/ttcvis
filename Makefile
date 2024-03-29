
all : dist/main.js dist/client.html dist/client.css

dist/client.html : client/client.html
	cp client/client.html dist/client.html

dist/client.css : client/client.css
	cp client/client.css dist/client.css

dist/main.js : client/main.coffee computed/graph.json computed/segments.json computed/coords.json computed/walkinggraph.json computed/stops.json
	mkdir -p dist ;\
	browserify -d -o dist/main.js -e client/main.coffee

computed/graph.json : data 
	python src/process_data.py --output-graph

computed/segments.json : data
	python src/process_data.py --output-segments

computed/coords.json : data 
	python src/process_data.py --output-coords

computed/walkinggraph.json : data
	python src/process_data.py --output-walking-graph

computed/stops.json : data
	python src/process_data.py --output-stops

data : downloads/OpenData_TTC_Schedules.zip
	mkdir -p data ;\
	unzip downloads/OpenData_TTC_Schedules.zip -d data/

downloads/OpenData_TTC_Schedules.zip :
	mkdir -p ;\
	curl http://opendata.toronto.ca/TTC/routes/OpenData_TTC_Schedules.zip -o downloads/OpenData_TTC_Schedules.zip

