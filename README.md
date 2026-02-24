# Cloudera + Kerberos em Docker

Este projeto sobe um ambiente com:

- `kdc`: servidor MIT Kerberos (realm `CLOUDERA.LOCAL`)
- `cloudera`: nó Cloudera QuickStart integrado ao KDC

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

## Variáveis de ambiente usadas

No `docker-compose.yml`, os valores padrão são:

- `KRB5_REALM=CLOUDERA.LOCAL`
- `KRB5_KDC=kdc.cloudera.local`
- `KRB5_ADMIN_SERVER=kdc.cloudera.local`
- `KRB5_ADMIN_PRINCIPAL=admin/admin` (no container `cloudera`)
- `KRB5_ADMIN_PASSWORD=admin123`
- `KRB5_USER_PASSWORD=cloudera123`
- `KRB5_SERVICE_PASSWORD=service123` (definida no compose; atualmente não é consumida pelos scripts)

## Validar Kerberos

O serviço `cloudera` agora é uma imagem derivada local de `withinboredom/cloudera:quickstart` (com `krb5.conf` e `entrypoint` versionados no projeto).
Como a base é legacy (CentOS 6), use o `kerberos-client` para validações com `kinit`/`klist`.

Verificar principals no KDC:

```bash
docker exec -it kdc bash -lc "kadmin.local -q 'listprincs'"
```

Testar autenticação com usuário:

```bash
docker exec -it kerberos-client bash -lc "echo cloudera123 | kinit cloudera@CLOUDERA.LOCAL && klist"
```

Testar autenticação com admin:

```bash
docker exec -it kerberos-client bash -lc "echo admin123 | kinit admin/admin@CLOUDERA.LOCAL && klist"
```

Se quiser validar keytabs de serviço:

```bash
docker exec -it kerberos-client bash -lc "kinit -kt /keytabs/hdfs.keytab hdfs/quickstart.cloudera.local@CLOUDERA.LOCAL && klist"
```

## Portas expostas

- `7180`: Cloudera Manager
- `8888`: Hue
- `8020`: NameNode RPC
- `50070`: NameNode UI
- `88/tcp+udp`, `749/tcp`: Kerberos

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
