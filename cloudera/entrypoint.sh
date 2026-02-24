#!/usr/bin/env bash
set -euo pipefail

REALM="${KRB5_REALM:-CLOUDERA.LOCAL}"
ADMIN_PRINCIPAL="${KRB5_ADMIN_PRINCIPAL:-admin/admin}"
ADMIN_PW="${KRB5_ADMIN_PASSWORD:-admin123}"
HOST_FQDN="$(hostname -f)"

wait_for_kdc() {
  local host="${KRB5_KDC:-kdc.cloudera.local}"
  echo "Waiting for Kerberos KDC at ${host}:88..."
  until (echo >"/dev/tcp/${host}/88") >/dev/null 2>&1; do
    sleep 2
  done
}

ensure_kerberos_tools() {
  if command -v kinit >/dev/null 2>&1 && command -v klist >/dev/null 2>&1; then
    return 0
  fi

  echo "Kerberos client tools not found. Trying to install..."
  if command -v yum >/dev/null 2>&1; then
    yum install -y krb5-workstation || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends krb5-user || true
  fi

  if command -v kinit >/dev/null 2>&1 && command -v klist >/dev/null 2>&1; then
    echo "Kerberos client tools installed."
  else
    echo "Warning: Kerberos client tools are still unavailable. Validation commands with kinit/klist may fail."
  fi
}

prepare_keytabs() {
  mkdir -p /etc/security/keytabs
  [ -f /keytabs/hdfs.keytab ] && cp /keytabs/hdfs.keytab /etc/security/keytabs/hdfs.headless.keytab
  [ -f /keytabs/yarn.keytab ] && cp /keytabs/yarn.keytab /etc/security/keytabs/yarn.service.keytab
  [ -f /keytabs/mapred.keytab ] && cp /keytabs/mapred.keytab /etc/security/keytabs/mapred.service.keytab
  [ -f /keytabs/http.keytab ] && cp /keytabs/http.keytab /etc/security/keytabs/spnego.service.keytab
  [ -f /keytabs/cloudera-scm.keytab ] && cp /keytabs/cloudera-scm.keytab /etc/security/keytabs/cloudera-scm.keytab
  chmod 600 /etc/security/keytabs/*.keytab || true
}

bootstrap_ticket() {
  if command -v kinit >/dev/null 2>&1; then
    printf '%s\n' "$ADMIN_PW" | kinit "${ADMIN_PRINCIPAL}@${REALM}" || true
  fi
  if command -v klist >/dev/null 2>&1; then
    klist || true
  fi
}

wait_for_kdc
ensure_kerberos_tools
prepare_keytabs
bootstrap_ticket

echo "Starting Cloudera QuickStart on ${HOST_FQDN} with Kerberos realm ${REALM}"
exec /usr/bin/docker-quickstart
