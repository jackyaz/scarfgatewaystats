#!/bin/sh
#shellcheck disable=SC2155
#shellcheck disable=SC2181
#shellcheck disable=SC3043
START_DATE="$(date -d "1 hour ago" +"%F")"
END_DATE="$(date -d "+1 days" +"%F")"

ProcessPackageStats(){
	local PACKAGE_NAME="$1"
	local PACKAGE_UUID="$2"
	local PACKAGE_DIR="/scarfgatewaystats/CSVs/$PACKAGE_NAME"
	mkdir -p "$PACKAGE_DIR"
	rm -f "$PACKAGE_DIR/$PACKAGE_NAME.csv"*
	echo "$PACKAGE_NAME - $(date "+%FT%T") - Retrieving stats from Scarf" > "$PACKAGE_NAME.out"
	curl -fsL -o "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" -H "Authorization: Bearer $API_TOKEN" "https://scarf.sh/api/v1/packages/$PACKAGE_UUID/events/$PACKAGE_NAME.csv?startDate=$START_DATE&endDate=$END_DATE"
	
	if [ -f "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" ]; then
		echo "$PACKAGE_NAME - $(date "+%FT%T") - Processing stats" >> "$PACKAGE_NAME.out"
		
		if [ "$(wc -l < "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp")" -gt 1 ]; then
			csvcut -c 5,8,9 "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" | tail -n +2 > "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp2"
			while IFS='' read -r line2 || [ -n "$line2" ]; do
				printf "%s,%s,%s,%s,%s\\n" "$(echo "$line2" | cut -f1 -d',')" "$(echo "$line2" | cut -f2 -d',' | cut -f1 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f2 -d',' | cut -f2 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f2 -d',' | cut -f3 -d'&' | cut -f2 -d'=')" "$(echo "$line2" | cut -f3 -d',')" >> "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			done < "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp2"
			
			local INFLUX_AUTHHEADER=""
			local INFLUX_URL=""
			if [ "$INFLUXDB_VERSION" = "1.8" ]; then
				local INFLUX_AUTHHEADER="${INFLUXDB_USERNAME}:${INFLUXDB_PASSWORD}"
				local INFLUX_URL="write?db=$INFLUXDB_DB&precision=ns"
			elif [ "$INFLUXDB_VERSION" = "2.0" ]; then
				local INFLUX_AUTHHEADER="$INFLUXDB_APITOKEN"
				local INFLUX_URL="api/v2/write?bucket=$INFLUXDB_DB&precision=ns"
			fi
			
			rm -f "$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
			while IFS='' read -r line2 || [ -n "$line2" ]; do
				local TIMESTAMP="$(date -d"$(echo "$line2" | cut -f1 -d',')" -u "+%s%N")"
				if [ -n "$(echo "$line2" | cut -f5 -d',')" ] && [ "$(echo "$line2" | cut -f5 -d',')" != "" ]; then
					printf "%s\\n" "Download,package=$PACKAGE_NAME,filename=$(echo "$line2" | cut -f2 -d','),branch=$(echo "$line2" | cut -f3 -d','),downloadtype=$(echo "$line2" | cut -f4 -d','),originid=$(echo "$line2" | cut -f5 -d',') value=1 $TIMESTAMP" >> "$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
				fi
			done < "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			cp "$PACKAGE_DIR/$PACKAGE_NAME.influxdb" "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			
			local NUMROWS="$(wc -l < "$PACKAGE_DIR/$PACKAGE_NAME.influxdb")"
			echo "$PACKAGE_NAME - $(date "+%FT%T") - Sending $NUMROWS rows to InfluxDB" >> "$PACKAGE_NAME.out"
			
			local FILELIST=""
			if [ "$NUMROWS" -gt 5000 ]; then
				echo "$PACKAGE_NAME - $(date "+%FT%T") - $NUMROWS is greater than 5000, splitting into parts" >> "$PACKAGE_NAME.out"
				split -l 5000 -d -e "$PACKAGE_DIR/$PACKAGE_NAME.influxdb" "$PACKAGE_DIR/split"
				FILELIST="$(ls "$PACKAGE_DIR/split"*)"
			else
				FILELIST="$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
			fi
			
			local COUNT=1
			local ISERROR="false"
			for file in $FILELIST; do
				echo "$PACKAGE_NAME - $(date "+%FT%T") - Sending part $COUNT of $(echo "$FILELIST" | wc -w)" >> "$PACKAGE_NAME.out"
				rm -f "$file.gz"
				gzip "$file"
				curl -fsSL --retry 3 --connect-timeout 15 --output /dev/null -XPOST "http://$INFLUXDB_HOST:$INFLUXDB_PORT/$INFLUX_URL" \
					--header "Authorization: Token $INFLUX_AUTHHEADER" --header "Accept-Encoding: gzip" \
					--header "Content-Encoding: gzip" --header "Content-Type: text/plain; charset=utf-8" --header "Accept: application/json" \
					--data-binary "@$file.gz" 2>> "$PACKAGE_NAME.out"
				if [ $? -ne 0 ]; then
					ISERROR="true"
				fi
				rm -f "$file.gz"*
				COUNT=$((COUNT + 1))
			done
			
			sed -i '1i Date,Filename,Branch,DownloadType,OriginID' "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			if [ "$ISERROR" = "false" ]; then
				echo "$PACKAGE_NAME - $(date "+%FT%T") - Stats successfully sent to InfluxDB" >> "$PACKAGE_NAME.out"
			else
				echo "$PACKAGE_NAME - $(date "+%FT%T") - Stats sent to InfluxDB with some errors, please review above" >> "$PACKAGE_NAME.out"
			fi
		else
			echo "$PACKAGE_NAME - $(date "+%FT%T") - No stats found!" >> "$PACKAGE_NAME.out"
		fi
	fi
	rm -f "$PACKAGE_DIR/split"*
	rm -f "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp"*
	cat "$PACKAGE_NAME.out"
	rm -f "$PACKAGE_NAME.out"
}

echo "$(date "+%FT%T") - Starting export of Scarf Gateway Stats"

curl -fsL -H "Authorization: Bearer $API_TOKEN" https://scarf.sh/api/v1/packages | jq -r '.[] | select(.libraryType=="file") | (.name + "," + .uuid)' | sort > packages

while IFS='' read -r line || [ -n "$line" ]; do
	name="$(echo "$line" | cut -f1 -d',')"
	uuid="$(echo "$line" | cut -f2 -d',')"
	ProcessPackageStats "$name" "$uuid" &
done < packages

wait

rm -f packages

echo "$(date "+%FT%T") - Completed export of Scarf Gateway Stats"
