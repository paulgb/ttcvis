
all: data

data: downloads/OpenData_TTC_Schedules.zip
	mkdir -p data ;\
	unzip downloads/OpenData_TTC_Schedules.zip -d data/

downloads/OpenData_TTC_Schedules.zip:
	mkdir -p downloads ;\
	curl http://opendata.toronto.ca/TTC/routes/OpenData_TTC_Schedules.zip -o downloads/OpenData_TTC_Schedules.zip

