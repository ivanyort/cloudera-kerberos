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
  echo "Warning: Kerberos client tools (kinit/klist) are not present in this image."
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

prepare_hive_runtime() {
  # Some CDH services reference short host quickstart.cloudera.
  if ! grep -qE '(^|[[:space:]])quickstart\.cloudera([[:space:]]|$)' /etc/hosts; then
    echo "127.0.0.1 quickstart.cloudera" >> /etc/hosts
  fi

  # Derby metastore should use a writable, persistent path.
  mkdir -p /var/lib/hive/metastore /tmp/hive
  chown -R hive:hive /var/lib/hive /tmp/hive 2>/dev/null || true

  for file in /etc/hive/conf/hive-site.xml /etc/hive/conf.cloudera.hive/hive-site.xml; do
    [ -f "$file" ] || continue
    if ! grep -q "javax.jdo.option.ConnectionURL" "$file"; then
      awk '
        /<configuration>/ {
          print
          print "  <property>"
          print "    <name>javax.jdo.option.ConnectionURL</name>"
          print "    <value>jdbc:derby:/var/lib/hive/metastore/metastore_db;create=true</value>"
          print "  </property>"
          next
        }
        { print }
      ' "$file" > "${file}.tmp"
      mv "${file}.tmp" "$file"
    fi
  done
}

leave_hdfs_safemode() {
  local attempts=36
  local i
  for ((i=1; i<=attempts; i++)); do
    if su -s /bin/bash hdfs -c "hdfs dfsadmin -safemode get" 2>/dev/null | grep -q "Safe mode is OFF"; then
      return 0
    fi
    su -s /bin/bash hdfs -c "hdfs dfsadmin -safemode leave" >/dev/null 2>&1 || true
    sleep 5
  done
  return 1
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local attempts="${3:-24}"
  local i
  for ((i=1; i<=attempts; i++)); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

stabilize_hive() {
  rm -rf /var/lib/hive/metastore/metastore_db /metastore_db || true

  service hive-metastore stop >/dev/null 2>&1 || true
  service hive-server2 stop >/dev/null 2>&1 || true

  service hive-metastore start >/dev/null 2>&1 || true
  wait_for_port "127.0.0.1" "9083" 24 || true

  service hive-server2 start >/dev/null 2>&1 || true
  wait_for_port "127.0.0.1" "10000" 24 || true
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
prepare_hive_runtime
bootstrap_ticket

echo "Starting Cloudera QuickStart on ${HOST_FQDN} with Kerberos realm ${REALM}"
(
  sleep 30
  leave_hdfs_safemode || true
  stabilize_hive || true
) &

exec /usr/bin/docker-quickstart
