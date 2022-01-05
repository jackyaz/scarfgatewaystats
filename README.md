# Scarf Gateway Stats

## About
This project is designed for exporting data from Scarf Gateway for "file" packages.

Example package configuration in Scarf to be compatible with this project
```
Template Path: /YazFi/{branch}/{downloadtype}/{filename}
Host Url: https://raw.githubusercontent.com/jackyaz/YazFi/{branch}/{filename}
```

Scarf Gateway data for the current day will be retrieved for all of your packages, running at 5 past and 35 past every hour.

Included is an example Grafana dashboard to visualise the captured data.

This fork assumes you have InfluxDB and Grafana deployed already.

Tested on Ubuntu with Docker and Python 3.9.

## Screenshot

![Grafana Dashboard](https://raw.githubusercontent.com/jackyaz/scarfgatewaystats/main/grafana-dashboard.PNG)

## Usage
A Docker image for this app is available on [Docker Hub](https://hub.docker.com/r/jackyaz/scarfgatewaystats)

### docker cli
```bash
docker run -d \
  --name=scarfgatewaystats \
  -e API_TOKEN="aaabbbccc" \
  -e EXCLUDED_PACKAGES="mypackagename,otherpackage" \
  -e INFLUXDB_VERSION="1.8" \
  -e INFLUXDB_USERNAME="user" \
  -e INFLUXDB_PASSWORD="password" \
  -e INFLUXDB_APITOKEN="xxxyyyzzz" \
  -e INFLUXDB_HOST="influxdb" \
  -e INFLUXDB_PORT="8086" \
  -e INFLUXDB_DB="scarf" \
  -v /path/to/data:/scarfgatewaystats/CSVs \
  --restart unless-stopped \
  jackyaz.io/jackyaz/scarfgatewaystats
```

### Parameters
The Docker images supports some parameters. These parameters are separated by a colon and indicate `<external>:<internal>` respectively. For example, `-v /apps/scarfgatewaystats:/scarfgatewaystats/CSVs` would map ```/apps/scarfgatewaystats``` on the Docker host to ```/scarfgatewaystats/CSVs``` inside the container.

#### Environment Variables (-e)
| Env | Function |
| :----: | --- |
| `API_TOKEN="aaabbbccc"` | Scarf Gateway API token |
| `EXCLUDED_PACKAGES="mypackagename,otherpackage"` | List of Scarf packages to exclude from processing |
| `INFLUXDB_VERSION="1.8"` | Version of InfluxDB you are exporting to, either 1.8 or 2.0 |
| `INFLUXDB_USERNAME="user"` | Username of the InfluxDB user to authenticate as (1.8) |
| `INFLUXDB_PASSWORD="password"` | Password of the InfluxDB user to authenticate as (1.8) |
| `INFLUXDB_APITOKEN="xxxyyyzzz"` | API token for InfluxDB to authenticate with (2.0+) |
| `INFLUXDB_HOST="influxdb"` | Hostname or IP address of InfluxDB instance |
| `INFLUXDB_PORT="8086"` | Port number for InfluxDB instance |
| `INFLUXDB_DB="scarf"` | Database name to save data to |

#### Volume Mappings (-v)
| Parameter | Function |
| :----: | --- |
| `-v /scarfgatewaystats/CSVs` | Local path for exported stats from Scarf Gateway as CSVs |

## Configuration
When creating the container, ensure you provide a value for all environment variables as appropriate.

You should create an InfluxDB database ```scarf```. The Grafana dashboard can be imported to visualise the data either via the provided json file or using the dashboard id ```xxxxx```.
