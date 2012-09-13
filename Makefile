
rawdata/ttc: downloads/OpenData_TTC_Schedules.zip
	mkdir -p rawdata/ttc ;\
	unzip downloads/OpenData_TTC_Schedules.zip -d rawdata/ttc/

downloads/OpenData_TTC_Schedules.zip:
	mkdir -p downloads ;\
	curl http://opendata.toronto.ca/TTC/routes/OpenData_TTC_Schedules.zip -o downloads/OpenData_TTC_Schedules.zip

