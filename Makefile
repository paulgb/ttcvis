
all : dist/main.js

dist/main.js : client/main.coffee computed/graph.json computed/segments.json computed/coords.json
	mkdir -p dist ;\
	browserify -d -o dist/main.js -e client/main.coffee

computed/graph.json : data 
	python src/process_data.py --output-graph

computed/segments.json : data
	python src/process_data.py --output-segments

computed/coords.json : data 
	python src/process_data.py --output-coords

data : downloads/OpenData_TTC_Schedules.zip
	mkdir -p data ;\
	unzip downloads/OpenData_TTC_Schedules.zip -d data/

downloads/OpenData_TTC_Schedules.zip :
	mkdir -p ;\
	curl http://opendata.toronto.ca/TTC/routes/OpenData_TTC_Schedules.zip -o downloads/OpenData_TTC_Schedules.zip

