# Hive 3 + Impala Dual-Mode (Kerberos + Open)

Languages:
- [Portuguese](README.md)
- English (this file)
- [Spanish (Mexico)](README.es-MX.md)

Complete local environment for Talend and JDBC tests, with both modes active at the same time:

- Hive 3.1.3 with Kerberos endpoint and non-Kerberos endpoint
- Impala 4.5.0 with Kerberos endpoint and non-Kerberos endpoint
- Local MIT Kerberos KDC (`EXAMPLE.COM`)
- HDFS + YARN
- PostgreSQL for Hive Metastore

## 1) Prerequisites

- Docker + Docker Compose
- For Kerberos tests on Windows:
  - Java `kinit`/`klist` (not Windows AD `klist`)
  - `krb5.ini` file
  - test user keytab (`talend.user.keytab`)

## 2) Start environment from scratch

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

If you only want to restart without deleting data:

```bash
docker compose up -d
docker compose ps
```

## 3) Ports and endpoints

Infra:

- `88/tcp` + `88/udp`: KDC
- `749/tcp`: kadmin
- `9870`: NameNode UI
- `8020`: HDFS RPC
- `8088`: YARN UI
- `19888`: JobHistory UI
- `9083`: Hive Metastore
- `5433`: PostgreSQL metastore

HiveServer2:

- `10000`: Hive with Kerberos
- `10001`: Hive without Kerberos (`noSasl`)

Impala:

- `21050`: Impala with Kerberos (HS2)
- `21051`: Impala without Kerberos (HS2)
- `25000`: Kerberos UI
- `25001`: non-Kerberos UI

## 4) Lab principals and credentials

Realm: `EXAMPLE.COM`

- admin: `admin/admin@EXAMPLE.COM` password `admin123`
- Talend user: `talend@EXAMPLE.COM` password `talend123`
- Hive service: `hive/localhost@EXAMPLE.COM`
- Impala service (client): `impala/impala.hadoop.local@EXAMPLE.COM`
- Impala service (internal): `impala/impala-statestored@EXAMPLE.COM`, `impala/impala-catalogd@EXAMPLE.COM`

## 5) Quick health check

```bash
docker compose ps -a
```

Expected:

- `hb-kdc`: `healthy`
- `hb-postgres`: `healthy`
- `hb-hdfs-init`: `Exited (0)`
- `hb-hive-metastore`: `healthy`
- `hb-hive-server2`: `Up`
- `hb-hive-server2-open`: `Up`
- `hb-impala-daemon`: `Up`
- `hb-impala-daemon-open`: `Up`

Port checks:

```bash
nc -zv localhost 10000
nc -zv localhost 10001
nc -zv localhost 21050
nc -zv localhost 21051
```

## 6) Talend - non-Kerberos connection (first test)

In Hive connection wizard (Repository):

- `Connection Mode`: `Standalone`
- `Hive Version`: `Hive 2`
- `Hadoop Version`: `Hadoop 3`
- `Server`: `localhost`
- `Port`: `10001`
- `DataBase`: `default`
- `Login`: empty
- `Password`: empty
- `Additional JDBC Settings`: `auth=noSasl`

Note: in some Talend versions, `String of Connection` is read-only. In that case, always use `Additional JDBC Settings` to inject JDBC parameters.

## 7) Talend - Kerberos connection (Hive)

### 7.1 Prepare `krb5.ini` on Windows

Example file:

- [examples/windows/krb5.ini](/codex/cloudera/hive3-impala-kerberos/examples/windows/krb5.ini)

Use one option:

- copy to `C:\Windows\krb5.ini` (default), or
- set `KRB5_CONFIG` variable pointing to another path.

### 7.2 Ensure keytab on Windows

Copy keytab generated in KDC container:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker cp hb-kdc:/keytabs/talend.user.keytab /tmp/talend.user.keytab
```

Then copy `/tmp/talend.user.keytab` to Windows, for example:

- `C:\Users\<YOUR_USER>\talend.user.keytab`

### 7.3 Generate Kerberos ticket on Windows

In `cmd.exe`:

```bat
set KRB5_CONFIG=C:\Windows\krb5.ini
set PATH=D:\portable\java\bin;%PATH%
kinit -k -t C:\Users\<YOUR_USER>\talend.user.keytab talend@EXAMPLE.COM
klist
```

Expected in Java `klist`: default principal `talend@EXAMPLE.COM`.

### 7.4 Configure in Talend (without “Use Kerberos authentication” checkbox)

If the screen does not show Kerberos checkbox and URL is locked, use:

- `Server`: `localhost`
- `Port`: `10000`
- `DataBase`: `default`
- `Login`: empty
- `Password`: empty
- `Additional JDBC Settings`: `auth=kerberos;principal=hive/localhost@EXAMPLE.COM`

Equivalent to:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

## 8) Reference JDBC

Hive without Kerberos:

```text
jdbc:hive2://localhost:10001/default;auth=noSasl
```

Hive with Kerberos:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

Impala without Kerberos:

```text
jdbc:impala://localhost:21051/default;AuthMech=0
```

Impala with Kerberos:

```text
jdbc:impala://localhost:21050/default;AuthMech=1;KrbRealm=EXAMPLE.COM;KrbHostFQDN=impala.hadoop.local;KrbServiceName=impala
```

## 9) Quick troubleshooting

Handshake/transport error in Talend:

- confirm correct port (`10001` non-Kerberos, `10000` Kerberos)
- confirm `Additional JDBC Settings`
- check whether Hive/Impala JDBC driver is installed in Talend

`kinit` authenticating against corporate AD instead of `EXAMPLE.COM`:

- adjust `PATH` to use Java `kinit`/`klist`
- validate with `where kinit` and `where klist`

`PortUnreachableException` in `kinit`:

- Docker/KDC is not reachable from Windows machine
- confirm `docker compose ps` and `88/udp` and `88/tcp` ports published

Environment unstable after many tests:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

## 10) Useful logs

```bash
docker logs -f hb-kdc
docker logs -f hb-hive-metastore
docker logs -f hb-hive-server2
docker logs -f hb-hive-server2-open
docker logs -f hb-impala-daemon
docker logs -f hb-impala-daemon-open
```
