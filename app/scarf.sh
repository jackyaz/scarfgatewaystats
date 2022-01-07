#!/bin/sh
#shellcheck disable=SC2155
#shellcheck disable=SC2181
#shellcheck disable=SC3043
START_DATE="$(date -d "1 hour ago" +"%F")"
END_DATE="$(date -d "+1 days" +"%F")"

ProcessPackageStats(){
	local PACKAGE_NAME="$1"
	local PACKAGE_DIR="/scarfgatewaystats/CSVs/$PACKAGE_NAME"
	mkdir -p "$PACKAGE_DIR"
	rm -f "$PACKAGE_DIR/$PACKAGE_NAME.csv"*
	
	grep "$PACKAGE_NAME" /scarfgatewaystats/CSVs/events.csv > "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp"
	
	if [ -f "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" ]; then
		echo "$PACKAGE_NAME - Processing stats"
		
		if [ "$(wc -l < "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp")" -gt 1 ]; then
			if [ -z "$2" ]; then
				if [ -f "$PACKAGE_DIR/$PACKAGE_NAME.bak" ]; then
					if [ "$(md5sum "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" | awk '{print $1}')" = "$(md5sum "$PACKAGE_DIR/$PACKAGE_NAME.bak" | awk '{print $1}')" ]; then
						echo "$PACKAGE_NAME - No changes detected, skipping"
						rm -f "$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
						rm -f "$PACKAGE_DIR/split"*
						rm -f "$PACKAGE_DIR/$PACKAGE_NAME.csv"*
						return 1
					fi
				fi
			fi
			
			cp -a "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" "$PACKAGE_DIR/$PACKAGE_NAME.bak"
			
			csvcut -c 5,8,9 "$PACKAGE_DIR/$PACKAGE_NAME.csv.tmp" | tail -n +2 > "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			rm -f "$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
			while IFS='' read -r line2 || [ -n "$line2" ]; do
				local TIMESTAMP="$(date -d"$(echo "$line2" | cut -f1 -d',')" -u "+%s%N")"
				if [ -n "$(echo "$line2" | cut -f3 -d',')" ] && [ "$(echo "$line2" | cut -f3 -d',')" != "" ]; then
					VALUE="1"
					if echo "$line2" | grep -q "amtm-version"; then
						VALUE="0.5"
					fi
					printf "Download,package=%s,originid=%s,%s value=%s $TIMESTAMP\\n" "$PACKAGE_NAME" "$(echo "$line2" | cut -f3 -d',')" "$(echo "$line2" | cut -f2 -d',' | sed 's/&/,/g')" "$VALUE" >> "$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
				fi
			done < "$PACKAGE_DIR/$PACKAGE_NAME.csv"
			
			local NUMROWS="$(wc -l < "$PACKAGE_DIR/$PACKAGE_NAME.influxdb")"
			echo "$PACKAGE_NAME - Sending $NUMROWS rows to InfluxDB"
			
			local FILELIST=""
			if [ "$NUMROWS" -gt 5000 ]; then
				echo "$PACKAGE_NAME - $NUMROWS is greater than 5000, splitting into parts"
				rm -f "$PACKAGE_DIR/split"*
				split -l 5000 -d -e "$PACKAGE_DIR/$PACKAGE_NAME.influxdb" "$PACKAGE_DIR/split"
				FILELIST="$(ls "$PACKAGE_DIR/split"*)"
			else
				FILELIST="$PACKAGE_DIR/$PACKAGE_NAME.influxdb"
			fi
			
			local INFLUX_AUTHHEADER=""
			local INFLUX_URL=""
			if [ "$INFLUXDB_VERSION" = "1.8" ]; then
				local INFLUX_AUTHHEADER="${INFLUXDB_USERNAME}:${INFLUXDB_PASSWORD}"
				local INFLUX_URL="write?db=$INFLUXDB_DB&precision=ns"
			elif [ "$INFLUXDB_VERSION" = "2.0" ]; then
				local INFLUX_AUTHHEADER="$INFLUXDB_APITOKEN"
				local INFLUX_URL="api/v2/write?bucket=$INFLUXDB_DB&precision=ns"
			fi
			
			local COUNT=1
			local ISERROR="false"
			for file in $FILELIST; do
				echo "$PACKAGE_NAME - Sending part $COUNT of $(echo "$FILELIST" | wc -w)"
				rm -f "$file.gz"
				gzip "$file"
				curl -fsSL --retry 3 --connect-timeout 15 --output /dev/null -XPOST "http://$INFLUXDB_HOST:$INFLUXDB_PORT/$INFLUX_URL" \
					--header "Authorization: Token $INFLUX_AUTHHEADER" --header "Accept-Encoding: gzip" \
					--header "Content-Encoding: gzip" --header "Content-Type: text/plain; charset=utf-8" --header "Accept: application/json" \
					--data-binary "@$file.gz" 2> "$PACKAGE_NAME.out"
				if [ $? -ne 0 ]; then
					ISERROR="true"
					echo "$PACKAGE_NAME - $(cat "$PACKAGE_NAME.out")"
				fi
				rm -f "$file.gz"*
				rm -f "$PACKAGE_NAME.out"
				COUNT=$((COUNT + 1))
			done
			
			if [ "$ISERROR" = "false" ]; then
				echo "$PACKAGE_NAME - Stats successfully sent to InfluxDB"
			else
				echo "$PACKAGE_NAME - Stats sent to InfluxDB with some errors, please review above"
			fi
		else
			echo "$PACKAGE_NAME - No stats found!"
		fi
	fi
	rm -f "$PACKAGE_DIR/split"*
	rm -f "$PACKAGE_DIR/$PACKAGE_NAME.csv"*
}

echo "Starting export of Scarf Gateway Stats"

curl -fsL -H "Authorization: Bearer $API_TOKEN" https://scarf.sh/api/v1/packages | jq -r '.[] | select(.libraryType=="file") | .name' | sort > packages

PACKAGE_SELECTOR=""

if [ -z "$EXCLUDED_PACKAGES" ] || [ "$EXCLUDED_PACKAGES" = "" ]; then
	PACKAGE_SELECTOR=""
else
	PACKAGE_SELECTOR="&selector="
	while IFS='' read -r line || [ -n "$line" ]; do
		name="$line"
		if echo "$EXCLUDED_PACKAGES" | grep -q "^$name," || echo "$EXCLUDED_PACKAGES" | grep -q "^$name$" || echo "$EXCLUDED_PACKAGES" | grep -q ",$name$" \
	|| echo "$EXCLUDED_PACKAGES" | grep -q ",$name," ; then
			echo "Skipping excluded package: $name"
		else
			PACKAGE_SELECTOR="$PACKAGE_SELECTOR$name,"
		fi
	done < packages
	PACKAGE_SELECTOR="$(echo "$PACKAGE_SELECTOR" | sed 's/,$//')"
fi

echo "Retrieving data from Scarf API, please be patient"
curl -fsSL -o "/scarfgatewaystats/CSVs/events.csv" -H "Authorization: Bearer $API_TOKEN" "https://scarf.sh/api/v2/${SCARF_USERNAME}/packages/events/events.csv?startDate=${START_DATE}&endDate=${END_DATE}${PACKAGE_SELECTOR}"

if [ $? -ne 0 ]; then
	echo "Error occured when retrieving data from Scarf API"
	rm -f packages
	rm -f /scarfgatewaystats/CSVs/events.csv
	exit 1
else
	echo "Successfully retrived data from Scarf API"
fi

while IFS='' read -r line || [ -n "$line" ]; do
	name="$(echo "$line" | cut -f1 -d',')"
	if echo "$EXCLUDED_PACKAGES" | grep -q "^$name," || echo "$EXCLUDED_PACKAGES" | grep -q "^$name$" || echo "$EXCLUDED_PACKAGES" | grep -q ",$name$" \
|| echo "$EXCLUDED_PACKAGES" | grep -q ",$name," ; then
		: # do nothing
	else
		if [ "$1" = "force" ]; then
			ProcessPackageStats "$name" "force "&
		else
			ProcessPackageStats "$name" &
		fi
	fi
done < packages

wait

rm -f packages
rm -f /scarfgatewaystats/CSVs/events.csv

echo "Completed export of Scarf Gateway Stats"
