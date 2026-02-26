# Hive 3 + Impala Dual-Mode (Kerberos + Open)

Idiomas:
- Português (este arquivo)
- [English](README.en.md)
- [Español (México)](README.es-MX.md)

Ambiente local completo para testes com Talend e JDBC, com os dois modos ativos ao mesmo tempo:

- Hive 3.1.3 com endpoint Kerberos e endpoint sem Kerberos
- Impala 4.5.0 com endpoint Kerberos e endpoint sem Kerberos
- KDC MIT Kerberos local (`EXAMPLE.COM`)
- HDFS + YARN
- PostgreSQL para Hive Metastore

## 1) Pré-requisitos

- Docker + Docker Compose
- Para testes Kerberos no Windows:
  - `kinit`/`klist` do Java (não o `klist` do Windows AD)
  - arquivo `krb5.ini`
  - keytab do usuário de teste (`talend.user.keytab`)

## 2) Subir ambiente do zero

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

Se quiser somente reiniciar sem apagar dados:

```bash
docker compose up -d
docker compose ps
```

## 3) Portas e endpoints

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

- `10000`: Hive com Kerberos
- `10001`: Hive sem Kerberos (`noSasl`)

Impala:

- `21050`: Impala com Kerberos (HS2)
- `21051`: Impala sem Kerberos (HS2)
- `25000`: UI Kerberos
- `25001`: UI sem Kerberos

## 4) Principals e credenciais do laboratório

Realm: `EXAMPLE.COM`

- admin: `admin/admin@EXAMPLE.COM` senha `admin123`
- usuário Talend: `talend@EXAMPLE.COM` senha `talend123`
- serviço Hive: `hive/localhost@EXAMPLE.COM`
- serviço Impala (cliente): `impala/impala.hadoop.local@EXAMPLE.COM`
- serviço Impala (interno): `impala/impala-statestored@EXAMPLE.COM`, `impala/impala-catalogd@EXAMPLE.COM`

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

Checagem de portas:

```bash
nc -zv localhost 10000
nc -zv localhost 10001
nc -zv localhost 21050
nc -zv localhost 21051
```

## 6) Talend - conexão sem Kerberos (primeiro teste)

No assistente de conexão Hive (Repository):

- `Connection Mode`: `Standalone`
- `Hive Version`: `Hive 2`
- `Hadoop Version`: `Hadoop 3`
- `Server`: `localhost`
- `Port`: `10001`
- `DataBase`: `default`
- `Login`: vazio
- `Password`: vazio
- `Additional JDBC Settings`: `auth=noSasl`

Observação: em algumas versões do Talend a `String of Connection` é somente leitura. Nesse caso, use sempre `Additional JDBC Settings` para injetar parâmetros JDBC.

## 7) Talend - conexão com Kerberos (Hive)

### 7.1 Preparar `krb5.ini` no Windows

Arquivo de exemplo:

- [examples/windows/krb5.ini](/codex/cloudera/hive3-impala-kerberos/examples/windows/krb5.ini)

Use uma das opções:

- copiar para `C:\Windows\krb5.ini` (padrão), ou
- definir variável `KRB5_CONFIG` apontando para outro caminho.

### 7.2 Garantir keytab no Windows

Copiar a keytab gerada no container KDC:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker cp hb-kdc:/keytabs/talend.user.keytab /tmp/talend.user.keytab
```

Depois copie `/tmp/talend.user.keytab` para Windows, por exemplo:

- `C:\Users\<SEU_USUARIO>\talend.user.keytab`

### 7.3 Gerar ticket Kerberos no Windows

No `cmd.exe`:

```bat
set KRB5_CONFIG=C:\Windows\krb5.ini
set PATH=D:\portable\java\bin;%PATH%
kinit -k -t C:\Users\<SEU_USUARIO>\talend.user.keytab talend@EXAMPLE.COM
klist
```

Esperado no `klist` (Java): principal default `talend@EXAMPLE.COM`.

### 7.4 Configurar no Talend (sem checkbox “Use Kerberos authentication”)

Se a tela não mostra checkbox Kerberos e a URL é bloqueada, use:

- `Server`: `localhost`
- `Port`: `10000`
- `DataBase`: `default`
- `Login`: vazio
- `Password`: vazio
- `Additional JDBC Settings`: `auth=kerberos;principal=hive/localhost@EXAMPLE.COM`

Isso equivale a:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

## 8) JDBC de referência

Hive sem Kerberos:

```text
jdbc:hive2://localhost:10001/default;auth=noSasl
```

Hive com Kerberos:

```text
jdbc:hive2://localhost:10000/default;auth=kerberos;principal=hive/localhost@EXAMPLE.COM
```

Impala sem Kerberos:

```text
jdbc:impala://localhost:21051/default;AuthMech=0
```

Impala com Kerberos:

```text
jdbc:impala://localhost:21050/default;AuthMech=1;KrbRealm=EXAMPLE.COM;KrbHostFQDN=impala.hadoop.local;KrbServiceName=impala
```

## 9) Troubleshooting rápido

Erro de handshake/transport no Talend:

- confirme porta correta (`10001` sem Kerberos, `10000` Kerberos)
- confirme `Additional JDBC Settings`
- confira se o driver JDBC Hive/Impala está instalado no Talend

`kinit` autenticando no AD corporativo em vez de `EXAMPLE.COM`:

- ajuste `PATH` para usar `kinit`/`klist` do Java
- valide com `where kinit` e `where klist`

`PortUnreachableException` no `kinit`:

- Docker/KDC não está acessível da máquina Windows
- confirme `docker compose ps` e portas `88/udp` e `88/tcp` publicadas

Ambiente instável após muitos testes:

```bash
cd /codex/cloudera/hive3-impala-kerberos
docker compose down -v --remove-orphans
docker compose up -d --build
docker compose ps -a
```

## 10) Logs úteis

```bash
docker logs -f hb-kdc
docker logs -f hb-hive-metastore
docker logs -f hb-hive-server2
docker logs -f hb-hive-server2-open
docker logs -f hb-impala-daemon
docker logs -f hb-impala-daemon-open
```
