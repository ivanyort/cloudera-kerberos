# Cloudera + Kerberos en Docker

Idiomas:
- [Português](README.md)
- [English](README.en.md)
- Español (México) (este archivo)

Este proyecto levanta un entorno con:

- `kdc`: servidor MIT Kerberos (realm `CLOUDERA.LOCAL`)
- `cloudera`: nodo Cloudera QuickStart integrado con KDC
- `kerberos-client`: cliente auxiliar para validaciones de `kinit`/`klist` sin depender de la imagen legacy de QuickStart

## Prerrequisitos

- Docker
- Docker Compose v2

## Levantar el entorno

```bash
docker compose build kdc cloudera kerberos-client
docker compose up -d
```

Si aparece `container kdc exited (1)`, limpia estado anterior y levanta de nuevo:

```bash
docker compose down -v
docker compose build --no-cache kdc cloudera kerberos-client
docker compose up -d
```

## Checklist después de iniciar (ejecutar en secuencia)

1. Confirmar contenedores en ejecución:

```bash
docker compose ps
```

2. Validar Kerberos (KDC y autenticación):

```bash
docker exec -it kdc bash -lc "kadmin.local -q 'listprincs'"
docker exec -it kerberos-client bash -lc "echo cloudera123 | kinit cloudera@CLOUDERA.LOCAL && klist"
docker exec -it kerberos-client bash -lc "echo admin123 | kinit admin/admin@CLOUDERA.LOCAL && klist"
```

3. Validar Hive (estatus + puertos + query):

```bash
docker exec -it cloudera bash -lc "service hive-metastore status; service hive-server2 status"
docker exec -it cloudera bash -lc "ss -lnt | grep 9083; ss -lnt | grep 10000"
docker exec -it cloudera bash -lc "beeline -u 'jdbc:hive2://127.0.0.1:10000/default' -n cloudera -p cloudera123 -e 'show databases;'"
```

4. Si el puerto `10000` no levanta, revisar log de HiveServer2:

```bash
docker exec -it cloudera bash -lc "tail -n 120 /var/log/hive/hive-server2.log"
```

## Variables de entorno usadas

En `docker-compose.yml`, los valores por defecto son:

- `KRB5_REALM=CLOUDERA.LOCAL`
- `KRB5_KDC=kdc.cloudera.local`
- `KRB5_ADMIN_SERVER=kdc.cloudera.local`
- `KRB5_ADMIN_PRINCIPAL=admin/admin` (en el contenedor `cloudera`)
- `KRB5_ADMIN_PASSWORD=admin123`
- `KRB5_USER_PASSWORD=cloudera123`
- `KRB5_SERVICE_PASSWORD=service123` (definida en compose; actualmente no la consumen los scripts)

## Puertos expuestos

- `7180`: Cloudera Manager
- `8888`: Hue
- `8020`: NameNode RPC
- `50070`: NameNode UI
- `88/tcp+udp`, `749/tcp`: Kerberos
- `10000`: HiveServer2 (Thrift)
- `9083`: Hive Metastore (Thrift)

## Credenciales por defecto

- Admin Kerberos: `admin/admin@CLOUDERA.LOCAL` / `admin123`
- Usuario Kerberos: `cloudera@CLOUDERA.LOCAL` / `cloudera123`

## Notas

- La imagen oficial `cloudera/quickstart` usa formato de manifiesto legacy y suele fallar en Docker moderno.
- Este proyecto usa una imagen local derivada de `withinboredom/cloudera:quickstart`.
- Las validaciones Kerberos se realizan en `kerberos-client` para evitar dependencias de paquetes en la imagen legacy de QuickStart.

## Troubleshooting

Si el contenedor `cloudera` termina con `Exit 139` sin logs, normalmente es incompatibilidad del host/kernel con `withinboredom/cloudera:quickstart` (generalmente falta `vsyscall=emulate` en el arranque).

Prueba rápida:

```bash
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

Si regresa `139`, habilita `vsyscall=emulate` en el host y reinicia.

Ejemplo en RHEL/CentOS:

```bash
sudo grubby --args="vsyscall=emulate" --update-kernel=ALL
sudo reboot
```

Ejemplo en WSL2 (Windows):

1. Cierra todas las distribuciones WSL:

```powershell
wsl --shutdown
```

2. Edita `%UserProfile%\.wslconfig` y agrega:

```ini
[wsl2]
kernelCommandLine=vsyscall=emulate
```

3. Inicia WSL otra vez y valida:

```bash
uname -a
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

Después del reinicio:

```bash
docker compose down -v
docker compose up -d
```

En pruebas de este entorno, los errores más comunes fueron:
- `SafeModeException` en HDFS (NameNode todavía en safe mode al iniciar HiveServer2).
- Fallas del metastore Derby en `/metastore_db` cuando hay estado residual de intentos previos.
