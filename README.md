# Cloudera + Kerberos em Docker

Idiomas:
- Português (este arquivo)
- [English](README.en.md)
- [Español (México)](README.es-MX.md)

Este projeto sobe um ambiente com:

- `kdc`: servidor MIT Kerberos (realm `CLOUDERA.LOCAL`)
- `cloudera`: nó Cloudera QuickStart integrado ao KDC
- `kerberos-client`: cliente auxiliar para validações de `kinit`/`klist` sem depender da imagem legacy do QuickStart

## Pré-requisitos

- Docker
- Docker Compose v2

## Subir o ambiente

```bash
docker compose build kdc cloudera kerberos-client
docker compose up -d
```

Se aparecer `container kdc exited (1)`, limpe estado antigo e suba de novo:

```bash
docker compose down -v
docker compose build --no-cache kdc cloudera kerberos-client
docker compose up -d
```

## Checklist pós-subida (executar em sequência)

1. Confirmar containers em execução:

```bash
docker compose ps
```

2. Validar Kerberos (KDC e autenticação):

```bash
docker exec -it kdc bash -lc "kadmin.local -q 'listprincs'"
docker exec -it kerberos-client bash -lc "echo cloudera123 | kinit cloudera@CLOUDERA.LOCAL && klist"
docker exec -it kerberos-client bash -lc "echo admin123 | kinit admin/admin@CLOUDERA.LOCAL && klist"
```

3. Validar Hive (status + portas + query):

```bash
docker exec -it cloudera bash -lc "service hive-metastore status; service hive-server2 status"
docker exec -it cloudera bash -lc "ss -lnt | grep 9083; ss -lnt | grep 10000"
docker exec -it cloudera bash -lc "beeline -u 'jdbc:hive2://127.0.0.1:10000/default' -n cloudera -p cloudera123 -e 'show databases;'"
```

4. Se a porta `10000` não subir, checar log do HiveServer2:

```bash
docker exec -it cloudera bash -lc "tail -n 120 /var/log/hive/hive-server2.log"
```

## Variáveis de ambiente usadas

No `docker-compose.yml`, os valores padrão são:

- `KRB5_REALM=CLOUDERA.LOCAL`
- `KRB5_KDC=kdc.cloudera.local`
- `KRB5_ADMIN_SERVER=kdc.cloudera.local`
- `KRB5_ADMIN_PRINCIPAL=admin/admin` (no container `cloudera`)
- `KRB5_ADMIN_PASSWORD=admin123`
- `KRB5_USER_PASSWORD=cloudera123`
- `KRB5_SERVICE_PASSWORD=service123` (definida no compose; atualmente não é consumida pelos scripts)

## Portas expostas

- `7180`: Cloudera Manager
- `8888`: Hue
- `8020`: NameNode RPC
- `50070`: NameNode UI
- `88/tcp+udp`, `749/tcp`: Kerberos
- `10000`: HiveServer2 (Thrift)
- `9083`: Hive Metastore (Thrift)

## Credenciais padrão

- Kerberos admin: `admin/admin@CLOUDERA.LOCAL` / `admin123`
- Kerberos user: `cloudera@CLOUDERA.LOCAL` / `cloudera123`

## Observações

- A imagem oficial `cloudera/quickstart` usa formato de manifesto legado e costuma falhar em Docker moderno.
- Este projeto usa uma imagem local derivada de `withinboredom/cloudera:quickstart`.
- As validações Kerberos são feitas no `kerberos-client` para evitar dependência de pacotes na imagem legacy do QuickStart.

## Troubleshooting

Se o container `cloudera` sair com `Exit 139` sem logs, normalmente é incompatibilidade do host/kernel com a imagem `withinboredom/cloudera:quickstart` (geralmente falta `vsyscall=emulate` no boot).

Teste rápido:

```bash
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

Se retornar `139`, habilite `vsyscall=emulate` no host e reinicie.

Exemplo em RHEL/CentOS:

```bash
sudo grubby --args="vsyscall=emulate" --update-kernel=ALL
sudo reboot
```

Exemplo em WSL2 (Windows):

1. Feche todas as distribuições WSL:

```powershell
wsl --shutdown
```

2. Edite `%UserProfile%\.wslconfig` e adicione:

```ini
[wsl2]
kernelCommandLine=vsyscall=emulate
```

3. Inicie o WSL novamente e valide:

```bash
uname -a
docker run --rm withinboredom/cloudera:quickstart /bin/bash -lc "echo ok"
```

Depois do reboot:

```bash
docker compose down -v
docker compose up -d
```

Em testes deste ambiente, os erros mais comuns foram:
- `SafeModeException` no HDFS (NameNode ainda em safe mode no momento do start do HiveServer2).
- falhas do metastore Derby em `/metastore_db` quando há estado residual de tentativas anteriores.
