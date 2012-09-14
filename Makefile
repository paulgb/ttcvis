
all: data computed/edges.csv computed/segments.csv

computed/edges.csv : data 
	python src/process_data.py --generate-edges

computed/segments.csv : data
	python src/process_data.py --generate-segments

data : downloads/OpenData_TTC_Schedules.zip
	mkdir -p data ;\
	unzip downloads/OpenData_TTC_Schedules.zip -d data/

downloads/OpenData_TTC_Schedules.zip :
	mkdir -p ;\
	curl http://opendata.toronto.ca/TTC/routes/OpenData_TTC_Schedules.zip -o downloads/OpenData_TTC_Schedules.zip

