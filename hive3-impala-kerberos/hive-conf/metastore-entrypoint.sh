#!/usr/bin/env bash
set -euo pipefail

export HIVE_CONF_DIR=/opt/hive/conf
if [ -d "${HIVE_CUSTOM_CONF_DIR:-}" ]; then
  find "${HIVE_CUSTOM_CONF_DIR}" -type f -exec ln -sfn {} "${HIVE_CONF_DIR}"/ \;
  export HADOOP_CONF_DIR=$HIVE_CONF_DIR
  export TEZ_CONF_DIR=$HIVE_CONF_DIR
fi

export HADOOP_CLIENT_OPTS="${HADOOP_CLIENT_OPTS:-} -Xmx1G ${SERVICE_OPTS:-}"

# Init schema only when it does not exist yet.
if ! /opt/hive/bin/schematool -dbType postgres -info >/dev/null 2>&1; then
  /opt/hive/bin/schematool -dbType postgres -initSchema
fi

exec /opt/hive/bin/hive --skiphadoopversion --skiphbasecp --service metastore
