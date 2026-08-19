# Zigbee2MQTT

Zigbee2MQTT bridge running as a standalone container, connecting to the SLZB-MR3 coordinator over TCP and publishing to the Mosquitto MQTT broker on Home Assistant.

## Setup

1. Copy the env sample and adjust if needed:

```bash
cp .env.sample .env
```

2. Create the Z2M configuration file in the data volume:

```bash
mkdir -p ../volumes/zigbee2mqtt
```

Then place `configuration.yaml` in `../volumes/zigbee2mqtt/` (see below).

3. Start:

```bash
docker compose up -d
```

## configuration.yaml

Create `../volumes/zigbee2mqtt/configuration.yaml` with:

```yaml
homeassistant: true
permit_join: false
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://HA_IP:1883
  user: MQTT_USER
  password: MQTT_PASSWORD
serial:
  port: tcp://MR3_IP:6638
  adapter: ember
  baudrate: 115200
frontend:
  port: 8099
advanced:
  transmit_power: 20
  log_level: info
```

Replace `HA_IP`, `MQTT_USER`, `MQTT_PASSWORD`, and `MR3_IP` with your actual values.

## Migration from HA add-on

1. Stop the Z2M add-on in Home Assistant (disable watchdog + stop).
2. Copy these files from the HA add-on data directory to `../volumes/zigbee2mqtt/`:
   - `configuration.yaml` (edit `serial.port` to use TCP address)
   - `database.db` (device database)
   - `state.json` (last known device states)
   - `coordinator_backup.json` (network backup)
3. Edit `configuration.yaml`:
   - Change `serial.port` to `tcp://MR3_IP:6638`
   - Add the `mqtt` section with the HA Mosquitto credentials
   - Set `frontend.port: 8099`
4. Start: `docker compose up -d`
5. Verify Z2M frontend is accessible at `http://NAS_IP:8099`
6. In HA, the MQTT integration should auto-discover devices as before (same base_topic).

## Notes

- The container connects to the MR3 coordinator via TCP (port 6638) — no USB passthrough needed.
- MQTT must be accessible from the NAS. Ensure Mosquitto on HA listens on the LAN interface (not just localhost).
- The Z2M frontend is exposed on port 8099.
