# Cloudera + Kerberos in Docker

Languages:
- [Portuguese](README.md)
- English (this file)
- [Spanish (Mexico)](README.es-MX.md)

This project brings up an environment with:

- `kdc`: MIT Kerberos server (realm `CLOUDERA.LOCAL`)
- `cloudera`: Cloudera QuickStart node integrated with KDC
- `kerberos-client`: helper client for `kinit`/`klist` checks without relying on the QuickStart legacy image

## Prerequisites

- Docker
- Docker Compose v2

## Start the environment

```bash
docker compose build kdc cloudera kerberos-client
docker compose up -d
```

If you see `container kdc exited (1)`, clean old state and start again:

```bash
docker compose down -v
docker compose build --no-cache kdc cloudera kerberos-client
docker compose up -d
```

## Post-start checklist (run in order)

1. Confirm containers are running:

```bash
docker compose ps
```

2. Validate Kerberos (KDC and authentication):

```bash
docker exec -it kdc bash -lc "kadmin.local -q 'listprincs'"
docker exec -it kerberos-client bash -lc "echo cloudera123 | kinit cloudera@CLOUDERA.LOCAL && klist"
docker exec -it kerberos-client bash -lc "echo admin123 | kinit admin/admin@CLOUDERA.LOCAL && klist"
```

3. Validate Hive (status + ports + query):

```bash
docker exec -it cloudera bash -lc "service hive-metastore status; service hive-server2 status"
docker exec -it cloudera bash -lc "ss -lnt | grep 9083; ss -lnt | grep 10000"
docker exec -it cloudera bash -lc "beeline -u 'jdbc:hive2://127.0.0.1:10000/default' -n cloudera -p cloudera123 -e 'show databases;'"
```

4. If port `10000` does not come up, check HiveServer2 log:

```bash
docker exec -it cloudera bash -lc "tail -n 120 /var/log/hive/hive-server2.log"
```

## Environment variables used

In `docker-compose.yml`, default values are:

- `KRB5_REALM=CLOUDERA.LOCAL`
- `KRB5_KDC=kdc.cloudera.local`
- `KRB5_ADMIN_SERVER=kdc.cloudera.local`
- `KRB5_ADMIN_PRINCIPAL=admin/admin` (in `cloudera` container)
- `KRB5_ADMIN_PASSWORD=admin123`
- `KRB5_USER_PASSWORD=cloudera123`
- `KRB5_SERVICE_PASSWORD=service123` (set in compose; currently not consumed by scripts)

## Exposed ports

- `7180`: Cloudera Manager
- `8888`: Hue
- `8020`: NameNode RPC
- `50070`: NameNode UI
- `88/tcp+udp`, `749/tcp`: Kerberos
- `10000`: HiveServer2 (Thrift)
- `9083`: Hive Metastore (Thrift)

## Default credentials

- Kerberos admin: `admin/admin@CLOUDERA.LOCAL` / `admin123`
- Kerberos user: `cloudera@CLOUDERA.LOCAL` / `cloudera123`

## Notes

- The official `cloudera/quickstart` image uses a legacy manifest format and often fails on modern Docker.
- This project uses a local image derived from `withinboredom/cloudera:quickstart`.
- Kerberos checks are done in `kerberos-client` to avoid package dependencies in the QuickStart legacy image.

## Troubleshooting

If `cloudera` container exits with `Exit 139` and no logs, it is usually host/kernel incompatibility with `withinboredom/cloudera:quickstart` (commonly missing `vsyscall=emulate` at boot).

Quick test:

```bash
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

If it returns `139`, enable `vsyscall=emulate` on host and reboot.

Example on RHEL/CentOS:

```bash
sudo grubby --args="vsyscall=emulate" --update-kernel=ALL
sudo reboot
```

Example on WSL2 (Windows):

1. Shut down all WSL distros:

```powershell
wsl --shutdown
```

2. Edit `%UserProfile%\.wslconfig` and add:

```ini
[wsl2]
kernelCommandLine=vsyscall=emulate
```

3. Start WSL again and validate:

```bash
uname -a
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

After reboot:

```bash
docker compose down -v
docker compose up -d
```

In tests for this environment, the most common errors were:
- `SafeModeException` in HDFS (NameNode still in safe mode when HiveServer2 starts).
- Derby metastore failures in `/metastore_db` when leftover state exists from previous attempts.
