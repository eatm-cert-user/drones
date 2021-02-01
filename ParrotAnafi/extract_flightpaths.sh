#!/usr/bin/bash
#written by BTU@EATM-CERT


#install required tools first
if [[ ! -f "/usr/bin/sqlite3" ]] || [[ ! -f  "/usr/bin/exiftool" ]]; then
	echo "please install sqlite3 & exiftool"
	exit
fi

#usage
if [[ $1 == "" ]] || [[ $2 == "" ]]; then
	echo "usage:parrot_anafi.sh <path/root of/mountpoint> <extraction method: sqlite|exif|briefinfo>"
	exit
fi

# GLOBAL definitions. Please check if it suits on your environment
mediadir="$1/DCIM/100MEDIA"


# kml file creation. flights.kml file will be generated at the end
function kml {  

case $1 in
	begin)
		echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
		<kml xmlns=\"http://www.opengis.net/kml/2.2\">
		  <Document>
		    <name>ParrotAnafiTestFlight</name>
		    <open>1</open>
		    <Style id=\"transPurpleLineGreenPoly\">
		      <LineStyle>
			<color>7fff00ff</color>
			<width>4</width>
		      </LineStyle>
		      <PolyStyle>
			<color>7f00ff00</color>
		      </PolyStyle>
		    </Style>" > flights.kml
      ;;
      startPlacemark)
			echo " 
			<Placemark>
			<name>Path$2</name>
			<visibility>1</visibility>
			<description>Transparent green wall with yellow outlines</description>
			<styleUrl>#transPurpleLineGreenPoly</styleUrl>
			<LineString>
			  <extrude>1</extrude>
			  <tessellate>0</tessellate>
			  <altitudeMode>absolute</altitudeMode>
			  <coordinates>" >> flights.kml
        ;;
          
       endPlacemark)
			  echo " 
			  </coordinates>
			</LineString>
		      </Placemark>" >> flights.kml
          ;;
       end)
		      	 echo "
		  </Document>
		</kml>" >> flights.kml
          ;;
esac

}


# extracting info media.db sqlite database
function sqlite_extraction {
	     echo "----------------------------------------------------------------------"
	     echo "This method will extract the path from the media.db sqlite database" 
	     echo "----------------------------------------------------------------------"
	     
	     echo "------------------------------------------------"
	     echo -e "Here, you can see the content of the media.db\n\n"
	     if [[ ! -f "$1/DCIM/media.db" ]]; then
	     	echo "media.db file not found..."
	     	exit
	     fi
	     sqlite3 $1/DCIM/media.db -cmd ".mode column" -cmd ".headers on"   "select media_id,run_id,longitude,latitude,altitude from media where gps_valid=1;"
	     
	     echo "---------------------------------------------------------------------------------------"
	     echo -e "Now,the flight paths will be generated according the gps coordinates in the media.db\n\n"
	     output=`sqlite3 $1/DCIM/media.db -cmd ".mode csv"  -cmd ".output /tmp/flightstmp_sqlite.csv"  "select run_id,longitude,latitude,altitude from media where gps_valid=1;"`
	     
	     cnt=0
	     pathid="none"
	     kml begin
	     for i in `cat /tmp/flightstmp_sqlite.csv`
		do
			pathidtmp=`echo $i | awk -F "," '{print $1}'`
			therest=`echo $i | awk -F "," '{print $2","$3","$4}' | tee flightpaths.txt `
			if  [  "$pathid" != "$pathidtmp" ]; then
				cnt=$((cnt+1))
				echo "path"$cnt | tee flightpaths.txt
				echo "--------------" | tee flightpaths.txt
				echo $therest | tee flightpaths.txt
				if [ "$pathid" != "none" ]; then
					kml endPlacemark
				fi
				kml startPlacemark $cnt
				echo $therest >> flights.kml
				pathid=$pathidtmp
				
			else
			    echo $therest | tee flightpaths.txt
			    echo $therest >> flights.kml
			fi
		done
	    kml endPlacemark
	    kml end
	    echo -e "\n------- flights.kml has been created... ---------"

}

# exiftool extration. This method extracts more GPS data since video files have sampling and every sample has GPS data.
function exif_extraction {
	echo "exif extraction started"
	for media in  `ls $1/DCIM/100MEDIA`;do
		
		echo "Processing $media..."
		exifcmd=`exiftool -r -ee $mediadir/$media -c "%.8f" | sed 's/ //g'` #extracts embedded objects for video it is sample rate
		runid=`echo "$exifcmd" | grep -i "RunId" | awk -F ":" '{print $2}'`
		nogps=`echo "$exifcmd" | egrep  "500.00000000N|500.00000000E"` 
		if [[ $nogps ]];then #dont process the unnecessary lines. Skip the entry
			echo "No GPS data on $media"
			continue; 
		fi
			 
	 	echo "Please wait extracting GPS path from $media"
		exifcmd_filtered=`echo "$exifcmd" | grep -i -A 10 "sampletime" | egrep -i "GPSLatitude|GPSLongitude|GPSAltitude"`
		
		for j in `echo "$exifcmd_filtered"`;do
			
			field=`echo $j| awk -F ":" '{print $1'}`
			value=`echo $j| awk -F ":" '{print $2'}`
			
			if [[ $field == "GPSLatitude" ]];then
				echo -n $runid"," >> /tmp/flightstmp_exif.csv
				echo -n $value"," | sed 's/N//g' >> /tmp/flightstmp_exif.csv
			elif [[ $field == "GPSLongitude" ]]; then
				echo -n $value"," | sed 's/E//g' >> /tmp/flightstmp_exif.csv
			elif [[ $field == "GPSAltitude" ]];then
				echo $value | sed 's/m//g' >> /tmp/flightstmp_exif.csv
			
			fi
				
		done
	done
	
	echo " contstrution of kml file started"
	cnt=0
	pathid="none"
	kml begin
	for i in `cat /tmp/flightstmp_exif.csv`
		do
			pathidtmp=`echo $i | awk -F "," '{print $1}'`
			therest=`echo $i | awk -F "," '{print $3","$2","$4}' ` #change the lat and long order
			if  [  "$pathid" != "$pathidtmp" ]; then
				cnt=$((cnt+1))
				if [ "$pathid" != "none" ]; then
					kml endPlacemark
				fi
				kml startPlacemark $cnt
				echo $therest >> flights.kml
				pathid=$pathidtmp
				
			else
			    echo $therest >> flights.kml
			fi
	done
	kml endPlacemark
	kml end
	echo -e "\n------- flights.kml file has been created. Please upload to Google Earth -------"
	
	
}

#get some useful info from exif metadata
function showBriefInfo {
	exifcmd=`exiftool -r  $mediadir/*`
	echo "$exifcmd" | grep -i "Serial Number" | sort | uniq
	echo "$exifcmd" | grep -i "Handler Vendor" |sort | uniq
	echo "$exifcmd" | egrep -i "make|model id|software version" |sort | uniq 
	echo -n "# of Power Cycle(boot-id): "; echo "$exifcmd" | grep -i "boot id" |sort | uniq | wc -l
	echo -n "# of flights(run-id): ";echo "$exifcmd" | grep -i "run id" |sort | uniq | wc -l
		
}

#"cleaning before start..."
function cleanFirst {
	
	if [[ -f "/tmp/flightstmp_exif.csv" ]];then
		rm  "/tmp/flightstmp_exif.csv"
	fi
	
	if [[ -f "/tmp/flightstmp_sqlite.csv" ]];then
		rm  "/tmp/flightstmp_sqlite.csv"
	fi
}


###### MAIN ##########

cleanFirst
case $2 in  
	sqlite)
	     	sqlite_extraction $1 
	     	;;
	     
	exif)
		exif_extraction $1 
		;;
	briefinfo)
		showBriefInfo $1
		;;
	*)
		echo "please choose extraction method"
		;;
esac
