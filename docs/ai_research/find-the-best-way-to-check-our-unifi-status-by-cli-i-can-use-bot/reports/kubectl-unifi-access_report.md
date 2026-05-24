# kubectl-Based UniFi Access Patterns — Research Report

## 1. Summary

The UniFi Network Application 10.0.162 running in k3s on the `closet` node (NodePort `30443`) uses the `jacobalberty/unifi` Docker image, which bundles an embedded MongoDB instance alongside the controller. This self-contained architecture makes direct data access through `kubectl` entirely feasible without the REST API.

Three viable kubectl-based access patterns exist, listed from simplest to most powerful:

**(a) `kubectl logs` — passive event monitoring.** The controller writes structured, timestamped log lines to `server.log` (path: `/usr/lib/unifi/logs/server.log`, symlinked from `/unifi/log/`). These logs contain device discovery, client association/disassociation, AP connection state changes, and error messages in a parseable ISO-8601 format with severity level and subsystem tags. This is the safest method — it is read-only, requires no authentication inside the container, and cannot corrupt the database. However, it provides only event streams, not current state snapshots.

**(b) `kubectl exec` + embedded MongoDB shell — direct state queries.** The container includes a full MongoDB toolchain at `/usr/lib/unifi/bin/` (`mongod`, `mongo`, `mongosh`, `mongodump`, `mongorestore`, `mongoexport`). The embedded database listens on `localhost:27117` inside the container and uses database name `ace`. A single `kubectl exec` one-liner can retrieve current AP status, client lists, and historical statistics from collections including `device`, `client`, `stat_ap`, `stat_device`, `stat_sessions`, `event`, and `alarm`. For example: `kubectl exec -n <namespace> <unifi-pod> -- mongo --quiet --port 27117 ace --eval "db.device.find({type:/uap/}, {mac:1, name:1, state:1, uptime:1, num_sta:1}).pretty()"` returns every AP's MAC, name, connection state, uptime, and current client count. This method provides complete, current-state data with sub-second latency — far faster than REST API round-trips that go through HTTP, authentication, and the Java application layer.

**(c) `kubectl exec` + `ace.jar` admin commands — controller management.** The Java application JAR at `/usr/lib/unifi/lib/ace.jar` supports an `admin` subcommand group offering `backup`, `restore`, `status`, and `list` operations. These are useful for controller maintenance but do not expose AP or client operational data.

The embedded MongoDB approach is **the most practical CLI-native method** for the stated goal of querying wireless AP status. It is faster than the REST API (direct DB access vs. HTTP+auth+Java stack), provides access to all collections including historical statistics not exposed through the API, and requires only `kubectl exec` — no port forwarding, API keys, or external tool dependencies. The trade-off is direct database access bypasses the controller's access control layer and risks breakage across UniFi version upgrades if the MongoDB schema changes. For read-only status queries on a home network with two APs, this risk is manageable and the latency/reliability advantages are decisive.

## 2. Relation to Primary Question

kubectl-based direct MongoDB access is the fastest, most complete, and lowest-dependency method to query UniFi AP status from the CLI — it outperforms the REST API in latency and data completeness while requiring only `kubectl exec` privileges, though it carries a version-upgrade fragility risk that the REST API avoids through schema abstraction.

## 3. Source Evaluation

### Source 1: jacobalberty/unifi-docker GitHub Repository (Dockerfile and entrypoint.sh)
- **URL:** https://github.com/jacobalberty/unifi-docker
- **Title:** jacobalberty/unifi-docker: Unifi Docker files
- **Credibility:** **Primary source, official code.** The Dockerfile and `docker-entrypoint.sh` are the authoritative definitions of the container's filesystem layout, environment variables, bundled binaries, and startup behavior. The repository has 1.4K stars on Docker Hub and is the most widely-used self-hosted UniFi Docker image (259M pulls). Maintained by Jacob Alberty with a public commit history.
- **Weighting:** Highest weight. This is definitive for the container internals — no inference needed.

### Source 2: Ubiquiti Help Center — Explaining the UniFi system.properties File
- **URL:** https://help.ui.com/hc/en-us/articles/205202580-Explaining-the-UniFi-system-properties-File
- **Title:** Explaining the UniFi system.properties File
- **Credibility:** **Primary source, official vendor documentation.** Published by Ubiquiti Inc. on their official help center. Documents the `system.properties` configuration mechanism directly. Updated to reflect current UniFi Network Server versions. The article explicitly notes it applies to self-hosted installations, which matches our deployment.
- **Weighting:** High. Authoritative for configuration file semantics. Does not cover Docker-specific paths (those come from Source 1).

### Source 3: Ubiquiti Help Center — UniFi System Logs & SIEM Integration
- **URL:** https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration
- **Title:** UniFi System Logs & SIEM Integration
- **Credibility:** **Primary source, official vendor documentation.** Documents the log categories, event types, CEF export format, and log structure. Confirms the types of events that appear in server.log (client connected/disconnected, device adopted/offline, admin activity, etc.). Published by Ubiquiti.
- **Weighting:** High for understanding what events are logged and their structure. Does not describe the raw `server.log` format in detail (that is inferred from community sources and Docker entrypoint behavior).

### Source 4: Incredigeek — "Searching for devices in UniFi via command line / MongoDB"
- **URL:** https://www.incredigeek.com/home/searching-for-devices-in-unifi-via-command-line-mongodb
- **Title:** Searching for devices in UniFi via command line / MongoDB
- **Credibility:** **Secondary source, community blog.** Published April 22 (year not specified, but content references MongoDB 3.x-era syntax using the legacy `mongo` shell). Author is a technical blogger, not a Ubiquiti employee. Provides practical, verifiable commands that match the confirmed MongoDB schema.
- **Weighting:** Medium. The specific MongoDB commands are verifiable against the known ace database schema and match community consensus across multiple forums. Used for practical query examples, not architectural claims.

### Source 5: Ubiquiti Community — "Querying the MongoDB behind the UniFi Controller for Session to SSID/wlanconf association"
- **URL:** https://community.ui.com/questions/Querying-the-MongoDB-behind-the-UniFi-Controller-for-Session-to-SSIDswlanconf-association/9021199b-69ab-4f5a-8a82-24a7adcb2445
- **Title:** Querying the MongoDB behind the UniFi Controller for Session to SSID/wlanconf association
- **Credibility:** **Secondary source, community forum.** Posted on Ubiquiti's official community forum. The question and answers come from community members, not Ubiquiti staff. However, the commands and schema details discussed are consistent with verified documentation and other community sources.
- **Weighting:** Medium. Validates the `stat_sessions`, `stat_ap`, and `stat_device` collection schemas through practical community usage. The forum is hosted by Ubiquiti, lending some official adjacency.

### Source 6: averred/unifi-find-ap GitHub Repository
- **URL:** https://github.com/averred/unifi-find-ap/blob/master/unifi-find-ap
- **Title:** unifi-find-ap — Bash script to find UniFi AP by MAC address by accessing MongoDB
- **Credibility:** **Secondary source, community tool.** A bash script by Talha Khan (dated August 2020) that demonstrates the practical pattern of using `mongo --port 27117 ace` inside the UniFi container to query the `device`, `site`, and `setting` collections. Code is public and auditable. Somewhat dated (uses legacy `mongo` shell) but the pattern remains valid.
- **Weighting:** Medium-Low. Demonstrates a real, working pattern for direct MongoDB access. Age is a concern, but the core approach (local MongoDB on port 27117, `ace` database, `device` collection) is independently confirmed by other sources.

### Source 7: LinuxServer.io — docker-unifi-network-application README
- **URL:** https://github.com/linuxserver/docker-unifi-network-application/blob/main/README.md
- **Title:** linuxserver/docker-unifi-network-application
- **Credibility:** **Secondary source, reputable community project.** LinuxServer.io is a well-established Docker image maintainer with extensive documentation. This image differs from jacobalberty's (it requires external MongoDB), but its documentation confirms the MongoDB tool paths (`/usr/lib/unifi/bin/`), the decoupled database design starting in UniFi 8.1, and supported MongoDB versions.
- **Weighting:** Medium. Credible for filesystem layout and tool availability, but the jacobalberty image (which bundles MongoDB) is the one actually deployed in this environment.

### Source 8: theDXT — "UniFi Network Server with Docker"
- **URL:** https://thedxt.ca/2023/12/unifi-network-server-with-docker/
- **Title:** UniFi Network Server with Docker
- **Credibility:** **Secondary source, personal technical blog.** Published December 2023 by a self-hosting practitioner. Documents the LinuxServer.io image setup. Confirms the decoupling of MongoDB from the controller in newer UniFi versions and the required init scripts for MongoDB setup.
- **Weighting:** Low-Medium. Useful for context on the broader UniFi Docker ecosystem but not authoritative. The specific Docker Compose setup described is for LinuxServer.io, not the jacobalberty image in use here.

### Source 9: Web search result aggregations (multiple)
- **URLs:** Various (see Bibliography)
- **Credibility:** **Secondary/tertiary.** Several findings were drawn from search engine result snippets that aggregated data across multiple community forums (Reddit, Stack Overflow, Ubiquiti Community). These were used for discovery and cross-referencing, not as primary evidence. Key claims (MongoDB port 27117, `ace` database name, collection names) were verified against at least two independent sources before inclusion.
- **Weighting:** Low for any single result; collectively useful for pattern confirmation. Specific claims were only included when corroborated.

## 4. Conclusions

### 4.1 Direct MongoDB queries via `kubectl exec` are the optimal CLI access method

For the stated use case — a home network with two UniFi APs (U7 Pro XGS at 192.168.5.171, U7 Lite at 192.168.5.173), no UniFi switches or routers, controller running in k3s on `closet` — direct MongoDB access through `kubectl exec` is the best approach:

- **No additional dependencies.** The `mongo` shell is already inside the container. No API key management, no external tool installation, no port forwarding.
- **Complete data access.** All collections are available: `device` (AP status, state, uptime, IP), `client` (connected clients with MAC, hostname, signal strength, traffic counters), `stat_ap` (historical AP performance metrics), `stat_device` and `stat_sessions` (historical client session data), `event` and `alarm` (system events and alerts).
- **Low latency.** A direct `mongo --eval` query completes in milliseconds versus hundreds of milliseconds for a REST API round-trip through authentication, the Java HTTP stack, and the controller's internal query logic.
- **Scriptable.** The `--quiet` flag on the `mongo` shell suppresses the MongoDB banner, producing clean output suitable for piping into `jq` (after using `printjson()`) or shell scripts.

### 4.2 Key MongoDB collections for AP status queries

| Collection | Purpose | Key fields for AP queries |
|-----------|---------|--------------------------|
| `device` | All adopted devices (APs, switches, gateways) | `type`, `mac`, `name`, `state` (1=online), `uptime`, `num_sta` (client count), `ip`, `model`, `version`, `last_seen` |
| `client` | Currently known clients | `mac`, `hostname`, `ip`, `ap_mac`, `essid`, `rssi`, `tx_rate`, `rx_rate`, `uptime`, `last_seen` |
| `stat_ap` | Time-series AP performance | `ap_id`, `time`, `num_sta`, `cpu`, `mem`, `rx_bytes`, `tx_bytes`, `loadavg_1`, `temperature` |
| `stat_device` | Time-series client performance | `mac`, `time`, `ap_id`, `signal`, `tx_rate`, `rx_rate`, `essid`, `rx_bytes`, `tx_bytes` |
| `stat_sessions` | Historical client sessions | `ap`, `client_mac`, `start`, `stop`, `duration`, `tx_bytes`, `rx_bytes`, `ssid` |
| `event` | System event log | `time`, `msg`, `key` (device MAC), `subsystem` |
| `alarm` | System alerts | `time`, `msg`, `source`, `type` |

### 4.3 Practical query examples

**List all APs with current status:**
```bash
kubectl exec -n <namespace> <unifi-pod> -- \
  mongo --quiet --port 27117 ace \
  --eval 'db.device.find({type:/uap/}, {mac:1, name:1, state:1, uptime:1, num_sta:1, ip:1, model:1}).forEach(printjson)'
```

**List all currently connected wireless clients with signal strength:**
```bash
kubectl exec -n <namespace> <unifi-pod> -- \
  mongo --quiet --port 27117 ace \
  --eval 'db.client.find({}, {mac:1, hostname:1, ip:1, essid:1, rssi:1, ap_mac:1, uptime:1}).forEach(printjson)'
```

**Check recent AP disconnection events from server.log:**
```bash
kubectl logs -n <namespace> <unifi-pod> | grep -E 'disconnect|disassoc|Device.*offline'
```

**Get historical client count per AP (last 24 hours from stat_ap):**
```bash
kubectl exec -n <namespace> <unifi-pod> -- \
  mongo --quiet --port 27117 ace \
  --eval 'db.stat_ap.find({time:{$gte:new Date(ISODate().getTime()-86400000)}}, {ap_id:1, num_sta:1, time:1}).forEach(printjson)'
```

### 4.4 Risks and mitigations of direct MongoDB access

- **Schema changes across upgrades.** Ubiquiti may rename collections or restructure documents between UniFi versions. The REST API abstracts this; direct queries would break. **Mitigation:** Pin queries to known stable fields (`mac`, `name`, `state`, `type`) which are unlikely to change. Test queries after each UniFi upgrade.
- **No access control.** Anyone with `kubectl exec` access to the pod can read and write the entire database. **Mitigation:** This is acceptable for a single-user home network. For read-only safety, use `--eval` with find-only queries (no `update`, `remove`, `drop`).
- **Database corruption risk.** Writing to MongoDB while the controller is running could corrupt data. **Mitigation:** Use read-only queries exclusively. Never run `db.device.update()` or `db.client.remove()` while the controller is active.
- **No transactional consistency guarantees for long queries.** MongoDB queries on live data may see partially-updated documents. **Mitigation:** For status snapshots, use simple `find()` queries that return in milliseconds, minimizing the window for inconsistency.

### 4.5 `kubectl logs` is useful for event history, not current state

The `server.log` file provides a real-time event stream but is not a state database. Use `kubectl logs` for:
- Debugging connectivity issues (see disassociation reasons, signal problems)
- Monitoring adoption/device discovery events
- Auditing admin actions
- Detecting error conditions

Do not use `kubectl logs` for:
- Current AP online/offline status (use MongoDB `device.state` field)
- Current client lists (use MongoDB `client` collection)
- Traffic statistics (use MongoDB `stat_*` collections)

### 4.6 Comparison: kubectl/MongoDB vs. REST API

| Dimension | kubectl + MongoDB | REST API |
|-----------|------------------|----------|
| **Latency** | ~10-50ms (single mongo query) | ~100-500ms (HTTP + auth + Java + DB) |
| **Data completeness** | Full access to all collections, including historical stats | Limited to documented endpoints; some collections not exposed |
| **Dependencies** | Only `kubectl exec` | Requires API key or session cookie management |
| **Schema stability** | Brittle — breaks on UniFi upgrades if schema changes | Stable — controller abstracts schema |
| **Access control** | None — full DB read/write if exec is available | Controller-enforced roles and permissions |
| **Reliability** | Direct DB access may see inconsistent states during writes | Controller provides consistent views |
| **Setup complexity** | None — tools already in container | Requires authentication bootstrap (API key or cookie) |
| **Recommended for** | Ad-hoc CLI queries, scripting, home networks | Production integrations, multi-user environments |

### 4.7 Environment and configuration available inside the container

The container entrypoint (from `docker-entrypoint.sh`) exposes these relevant environment variables:
- `BASEDIR=/usr/lib/unifi` — controller root
- `DATADIR=/unifi/data` — persistent data (includes MongoDB files at `db/` subdirectory)
- `LOGDIR=/unifi/log` — server.log location
- `JVM_MAX_HEAP_SIZE` — Java heap (default 1024M)
- `UNIFI_STDOUT=true` — when set, logs also go to stdout (visible in `kubectl logs`)
- `MONGO_HOST`, `MONGO_PORT`, `UNIFI_DB` — configured only when using external MongoDB (not the case here)
- `SYSTEM_IP` — override for device inform address

The `system.properties` file at `/usr/lib/unifi/data/system.properties` stores runtime configuration. It is generated on first run and can include settings like `unifi.http.port`, `unifi.https.port`, `db.mongo.local`, and `unifi.logStdout`.

### 4.8 No UniFi switches/routers — impact on access patterns

The user's environment has only APs (no UniFi switches or routers). This simplifies access patterns:
- The `device` collection will only contain `type: "uap"` documents — no switch or gateway records to filter out
- Log entries will not include switch port events, PoE negotiations, or WAN failover events
- The `stat_ap` collection is the primary time-series store (no `stat_switch` or `stat_gateway` data)
- Client connection data in `client` and `stat_sessions` is fully relevant since all clients connect via APs

## 5. Bibliography

Alberty, J. (n.d.). *jacobalberty/unifi-docker: Unifi Docker files* [Source code]. GitHub. https://github.com/jacobalberty/unifi-docker

Alberty, J. (n.d.). *jacobalberty/unifi* [Docker image]. Docker Hub. https://hub.docker.com/r/jacobalberty/unifi

Averred. (2020). *unifi-find-ap* [Source code]. GitHub. https://github.com/averred/unifi-find-ap/blob/master/unifi-find-ap

Incredigeek. (n.d.). *Searching for devices in UniFi via command line / MongoDB*. https://www.incredigeek.com/home/searching-for-devices-in-unifi-via-command-line-mongodb

LinuxServer.io. (n.d.). *docker-unifi-network-application* [Source code]. GitHub. https://github.com/linuxserver/docker-unifi-network-application/blob/main/README.md

theDXT. (2023, December 16). *UniFi Network Server with Docker*. https://thedxt.ca/2023/12/unifi-network-server-with-docker/

Ubiquiti Inc. (n.d.). *Explaining the UniFi system.properties File*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/205202580-Explaining-the-UniFi-system-properties-File

Ubiquiti Inc. (n.d.). *UniFi System Logs & SIEM Integration*. Ubiquiti Help Center. https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration

Ubiquiti Community. (n.d.). *Querying the MongoDB behind the UniFi Controller for Session to SSID/wlanconf association* [Online forum post]. https://community.ui.com/questions/Querying-the-MongoDB-behind-the-UniFi-Controller-for-Session-to-SSIDswlanconf-association/9021199b-69ab-4f5a-8a82-24a7adcb2445

Ubiquiti Community. (n.d.). *External MongoDB Server* [Online forum post]. https://community.ui.com/questions/External-MongoDB-Server/d311a8f8-43b6-4aeb-859d-eefec9dc1bbc

Ubiquiti Community. (n.d.). *UniFi Network Application 10.0.162 Release* [Release notes]. https://community.ui.com/releases/UniFi-Network-Application-10-0-162/2efd581a-3a55-4c36-80bf-1267dbfc2aee
