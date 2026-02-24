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

hive_ports_ready() {
  (echo >"/dev/tcp/127.0.0.1/9083") >/dev/null 2>&1 && \
    (echo >"/dev/tcp/127.0.0.1/10000") >/dev/null 2>&1
}

cleanup_stale_pidfile() {
  local pidfile="$1"
  local pid
  [ -f "$pidfile" ] || return 0

  pid="$(tr -cd '0-9' < "$pidfile" || true)"
  if [ -z "$pid" ] || ! kill -0 "$pid" >/dev/null 2>&1; then
    rm -f "$pidfile"
  fi
}

cleanup_hive_metastore_pidfiles() {
  local pidfile
  for pidfile in \
    /var/run/hive/*metastore*.pid \
    /var/run/*metastore*.pid \
    /var/run/hive-metastore*.pid
  do
    [ -e "$pidfile" ] || continue
    cleanup_stale_pidfile "$pidfile"
  done
}

restart_hive_services() {
  cleanup_hive_metastore_pidfiles
  service hive-metastore restart >/dev/null 2>&1 || true
  service hive-server2 restart >/dev/null 2>&1 || true
}

stabilize_runtime() {
  local attempts=80
  local i
  local metastore_reset=0

  for ((i=1; i<=attempts; i++)); do
    leave_hdfs_safemode || true

    if hive_ports_ready; then
      echo "Runtime stabilized: HDFS safemode is off and Hive ports are open."
      return 0
    fi

    # Retry service startup while cluster settles.
    restart_hive_services

    # If metastore keeps failing, reset Derby state once.
    if [ "$i" -ge 10 ] && [ "$metastore_reset" -eq 0 ] && ! (echo >"/dev/tcp/127.0.0.1/9083") >/dev/null 2>&1; then
      echo "Resetting Hive metastore Derby state for recovery..."
      rm -rf /var/lib/hive/metastore/metastore_db /metastore_db || true
      metastore_reset=1
      restart_hive_services
    fi

    sleep 15
  done

  echo "Warning: runtime stabilization timed out; some services may still be initializing."
  return 1
}

bootstrap_ticket() {
  if command -v kinit >/dev/null 2>&1; then
    printf '%s\n' "$ADMIN_PW" | kinit "${ADMIN_PRINCIPAL}@${REALM}" || true
  fi
  if command -v klist >/dev/null 2>&1; then
    klist || true
  fi
}

configure_cloudera_manager_start() {
  local defaults="/etc/default/cloudera-scm-server"
  [ -f "$defaults" ] || return 0

  # In containers, su-based launch may fail with "could not open session".
  # Force init script to start cmf-server directly.
  if grep -q "^CMF_SUDO_CMD=" "$defaults"; then
    sed -i 's/^CMF_SUDO_CMD=.*/CMF_SUDO_CMD=" "/' "$defaults"
  else
    printf '\nCMF_SUDO_CMD=" "\n' >> "$defaults"
  fi
}

wait_for_kdc
ensure_kerberos_tools
prepare_keytabs
prepare_hive_runtime
bootstrap_ticket
configure_cloudera_manager_start

echo "Starting Cloudera QuickStart on ${HOST_FQDN} with Kerberos realm ${REALM}"
(
  sleep 20
  stabilize_runtime || true
) &

exec /usr/bin/docker-quickstart
