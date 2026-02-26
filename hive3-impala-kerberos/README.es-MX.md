# Hive 3 + Impala Modo Dual (Kerberos + Open)

Idiomas:
- [Português](README.md)
- [English](README.en.md)
- Español (México) (este archivo)

Entorno local completo para pruebas con Talend y JDBC, con ambos modos activos al mismo tiempo:

- Hive 3.1.3 con endpoint Kerberos y endpoint sin Kerberos
- Impala 4.5.0 con endpoint Kerberos y endpoint sin Kerberos
- KDC MIT Kerberos local (`EXAMPLE.COM`)
- HDFS + YARN
- PostgreSQL para Hive Metastore

## 1) Prerrequisitos

- Docker + Docker Compose
- Para pruebas Kerberos en Windows:
  - `kinit`/`klist` de Java (no el `klist` de Windows AD)
  - archivo `krb5.ini`
  - keytab del usuario de prueba (`talend.user.keytab`)

## 2) Levantar entorno desde cero

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

Si solo quieres reiniciar sin borrar datos:

```bash
docker compose up -d
docker compose ps
```

## 3) Puertos y endpoints

Infra:

- `88/tcp` + `88/udp`: KDC
- `749/tcp`: kadmin
- `9870`: UI de NameNode
- `8020`: HDFS RPC
- `8088`: UI de YARN
- `19888`: UI de JobHistory
- `9083`: Hive Metastore
- `5433`: metastore PostgreSQL

HiveServer2:

- `10000`: Hive con Kerberos
- `10001`: Hive sin Kerberos (`noSasl`)

Impala:

- `21050`: Impala con Kerberos (HS2)
- `21051`: Impala sin Kerberos (HS2)
- `25000`: UI Kerberos
- `25001`: UI sin Kerberos

## 4) Principals y credenciales del laboratorio

Realm: `EXAMPLE.COM`

- admin: `admin/admin@EXAMPLE.COM` contraseña `admin123`
- usuario Talend: `talend@EXAMPLE.COM` contraseña `talend123`
- servicio Hive: `hive/localhost@EXAMPLE.COM`
- servicio Impala (cliente): `impala/impala.hadoop.local@EXAMPLE.COM`
- servicio Impala (interno): `impala/impala-statestored@EXAMPLE.COM`, `impala/impala-catalogd@EXAMPLE.COM`

## 5) Health-check rápido

```bash
docker compose ps -a
```

Esperado:

- `hb-kdc`: `healthy`
- `hb-postgres`: `healthy`
- `hb-hdfs-init`: `Exited (0)`
- `hb-hive-metastore`: `healthy`
- `hb-hive-server2`: `Up`
- `hb-hive-server2-open`: `Up`
- `hb-impala-daemon`: `Up`
- `hb-impala-daemon-open`: `Up`

Revisión de puertos:

```bash
nc -zv localhost 10000
nc -zv localhost 10001
nc -zv localhost 21050
nc -zv localhost 21051
```

## 6) Talend - conexión sin Kerberos (primera prueba)

En el asistente de conexión Hive (Repository):

- `Connection Mode`: `Standalone`
- `Hive Version`: `Hive 2`
- `Hadoop Version`: `Hadoop 3`
- `Server`: `localhost`
- `Port`: `10001`
- `DataBase`: `default`
- `Login`: vacío
- `Password`: vacío
- `Additional JDBC Settings`: `auth=noSasl`

Nota: en algunas versiones de Talend, `String of Connection` es solo lectura. En ese caso, usa siempre `Additional JDBC Settings` para inyectar parámetros JDBC.

## 7) Talend - conexión con Kerberos (Hive)

### 7.1 Preparar `krb5.ini` en Windows

Archivo de ejemplo:

- [examples/windows/krb5.ini](/codex/cloudera/hive3-impala-kerberos/examples/windows/krb5.ini)

Usa una de estas opciones:

- copiar a `C:\Windows\krb5.ini` (por defecto), o
- definir variable `KRB5_CONFIG` apuntando a otra ruta.

### 7.2 Asegurar keytab en Windows

Copiar la keytab generada en el contenedor KDC:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker cp hb-kdc:/keytabs/talend.user.keytab /tmp/talend.user.keytab
```

Después copia `/tmp/talend.user.keytab` a Windows, por ejemplo:

- `C:\Users\<TU_USUARIO>\talend.user.keytab`

### 7.3 Generar ticket Kerberos en Windows

En `cmd.exe`:

```bat
set KRB5_CONFIG=C:\Windows\krb5.ini
set PATH=D:\portable\java\bin;%PATH%
kinit -k -t C:\Users\<TU_USUARIO>\talend.user.keytab talend@EXAMPLE.COM
klist
```

Esperado en `klist` de Java: principal por defecto `talend@EXAMPLE.COM`.

### 7.4 Configurar en Talend (sin checkbox “Use Kerberos authentication”)

Si la pantalla no muestra checkbox Kerberos y la URL está bloqueada, usa:

- `Server`: `localhost`
- `Port`: `10000`
- `DataBase`: `default`
- `Login`: vacío
- `Password`: vacío
- `Additional JDBC Settings`: `auth=kerberos;principal=hive/localhost@EXAMPLE.COM`

Equivale a:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

## 8) JDBC de referencia

Hive sin Kerberos:

```text
jdbc:hive2://localhost:10001/default;auth=noSasl
```

Hive con Kerberos:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

Impala sin Kerberos:

```text
jdbc:impala://localhost:21051/default;AuthMech=0
```

Impala con Kerberos:

```text
jdbc:impala://localhost:21050/default;AuthMech=1;KrbRealm=EXAMPLE.COM;KrbHostFQDN=impala.hadoop.local;KrbServiceName=impala
```

## 9) Troubleshooting rápido

Error de handshake/transport en Talend:

- confirma puerto correcto (`10001` sin Kerberos, `10000` Kerberos)
- confirma `Additional JDBC Settings`
- valida si el driver JDBC de Hive/Impala está instalado en Talend

`kinit` autenticando contra AD corporativo en vez de `EXAMPLE.COM`:

- ajusta `PATH` para usar `kinit`/`klist` de Java
- valida con `where kinit` y `where klist`

`PortUnreachableException` en `kinit`:

- Docker/KDC no es accesible desde la máquina Windows
- confirma `docker compose ps` y puertos `88/udp` y `88/tcp` publicados

Entorno inestable después de muchas pruebas:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

## 10) Logs útiles

```bash
docker logs -f hb-kdc
docker logs -f hb-hive-metastore
docker logs -f hb-hive-server2
docker logs -f hb-hive-server2-open
docker logs -f hb-impala-daemon
docker logs -f hb-impala-daemon-open
```
