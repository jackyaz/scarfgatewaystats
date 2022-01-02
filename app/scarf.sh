#!/bin/sh
START_DATE="2022-01-01"
END_DATE="2022-01-31"

curl -fsL -H "Authorization: Bearer $API_TOKEN" https://scarf.sh/api/v1/packages | jq -r '.[] | select(.libraryType=="file") | (.name + "," + .uuid)' | sort > packages

while IFS='' read -r line || [ -n "$line" ]; do
	PACKAGE_NAME=$(echo "$line" | cut -f1 -d',')
	PACKAGE_UUID=$(echo "$line" | cut -f2 -d',')
	rm -f "CSVs/$PACKAGE_NAME.csv"*
	curl -fsL -o "CSVs/$PACKAGE_NAME.csv.tmp" -H "Authorization: Bearer $API_TOKEN" "https://scarf.sh/api/v1/packages/$PACKAGE_UUID/events/$PACKAGE_NAME.csv?startDate=$START_DATE&endDate=$END_DATE"
	if [ -f "CSVs/$PACKAGE_NAME.csv.tmp" ]; then
		printf "\\nProcessing stats for %s\\n" "$PACKAGE_NAME"
		if [ "$(wc -l < "CSVs/$PACKAGE_NAME.csv.tmp")" -gt 1 ]; then
			csvcut -c 5,8,9 "CSVs/$PACKAGE_NAME.csv.tmp" | tail -n +2 > "CSVs/$PACKAGE_NAME.csv.tmp2"
			while IFS='' read -r line2 || [ -n "$line2" ]; do
				printf "%s,%s,%s,%s,%s\\n" "$(echo "$line2" | cut -f1 -d',')" "$(echo "$line2" | cut -f2 -d',' | cut -f1 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f2 -d',' | cut -f2 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f2 -d',' | cut -f3 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f3 -d',')" >> "CSVs/$PACKAGE_NAME.csv"
			done < "CSVs/$PACKAGE_NAME.csv.tmp2"
			INFLUX_AUTHHEADER=""
			if [ "$INFLUXDB_VERSION" = "1.8" ]; then
				INFLUX_AUTHHEADER="${INFLUXDB_USERNAME}:${INFLUXDB_PASSWORD}"
				INFLUX_URL="write?db=$INFLUXDB_DB&precision=ns"
			elif [ "$INFLUXDB_VERSION" = "2.0" ]; then
				INFLUX_AUTHHEADER="$INFLUXDB_APITOKEN"
				INFLUX_URL="api/v2/write?bucket=$INFLUXDB_DB&precision=ns"
			fi
			
			rm -f "CSVs/$PACKAGE_NAME.influxdb"
			while IFS='' read -r line2 || [ -n "$line2" ]; do
				TIMESTAMP=$(date -d"$(echo "$line2" | cut -f1 -d',')" -u "+%s%N")
				if [ -n "$(echo "$line2" | cut -f5 -d',')" ] && [ "$(echo "$line2" | cut -f5 -d',')" != "" ]; then
					printf "%s\\n" "Download,package=$PACKAGE_NAME,filename=$(echo "$line2" | cut -f2 -d','),branch=$(echo "$line2" | cut -f3 -d','),downloadtype=$(echo "$line2" | cut -f4 -d','),originid=$(echo "$line2" | cut -f5 -d',') value=1 $TIMESTAMP" >> "CSVs/$PACKAGE_NAME.influxdb"
				fi
			done < "CSVs/$PACKAGE_NAME.csv"
			gzip "CSVs/$PACKAGE_NAME.influxdb"
			curl -fsSL --retry 3 --connect-timeout 15 --output /dev/null -XPOST "http://$INFLUXDB_HOST:$INFLUXDB_PORT/$INFLUX_URL" \
				--header "Authorization: Token $INFLUX_AUTHHEADER" --header "Accept-Encoding: gzip" \
				--header "Content-Encoding: gzip" --header "Content-Type: text/plain; charset=utf-8" --header "Accept: application/json" \
				--data-binary "@CSVs/$PACKAGE_NAME.influxdb.gz"
			cp "CSVs/$PACKAGE_NAME.influxdb.gz" "CSVs/$PACKAGE_NAME.influxdb.gz.bak"
			rm -f "CSVs/$PACKAGE_NAME.influxdb.gz"
			sed -i '1i Date,Filename,Branch,DownloadType,OriginID' "CSVs/$PACKAGE_NAME.csv"
			printf "Successfully sent to InfluxDB\\n"
		else
			printf "No stats found!\\n"
		fi
	fi
	rm -f "CSVs/$PACKAGE_NAME.csv.tmp"*
done < packages

rm -f packages
