#!/bin/bash
#
# Copyright 2020 Red Hat Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
set -ex

echo "Starting conductor init"

# Get the statefulset pod index
export PODINDEX=$(echo ${HOSTNAME##*-})

# Get required environment variables
IRONICPASSWORD=${IronicPassword:-""}
TRANSPORTURL=${TransportURL:-""}
QUORUMQUEUES=${QuorumQueues:-"false"}

INIT_CONFIG="/var/lib/config-data/merged/03-init-container-conductor.conf"

if [ -n "${ProvisionNetwork}" ]; then
    export ProvisionNetworkIP=$(/usr/local/bin/container-scripts/get_net_ip ${ProvisionNetwork})
    crudini --set ${INIT_CONFIG} DEFAULT my_ip $ProvisionNetworkIP
fi

if [ -n "${TRANSPORTURL}" ]; then
    crudini --set ${INIT_CONFIG} DEFAULT transport_url ${TRANSPORTURL}
    crudini --set ${INIT_CONFIG} DEFAULT rpc_transport oslo
    if ${QUORUMQUEUES}; then
        crudini --set ${INIT_CONFIG} oslo_messaging_rabbit rabbit_quorum_queue true
        crudini --set ${INIT_CONFIG} oslo_messaging_rabbit rabbit_transient_quorum_queue true
        crudini --set ${INIT_CONFIG} oslo_messaging_rabbit amqp_durable_queues true
    fi
fi

export DEPLOY_HTTP_URL=$(python3 -c 'import os; print(os.environ["DeployHTTPURL"] % os.environ)')

crudini --set ${INIT_CONFIG} deploy http_url ${DEPLOY_HTTP_URL}
crudini --set ${INIT_CONFIG} conductor bootloader ${DEPLOY_HTTP_URL}esp.img
crudini --set ${INIT_CONFIG} conductor deploy_kernel ${DEPLOY_HTTP_URL}ironic-python-agent.kernel
crudini --set ${INIT_CONFIG} conductor deploy_ramdisk ${DEPLOY_HTTP_URL}ironic-python-agent.initramfs
crudini --set ${INIT_CONFIG} conductor rescue_kernel ${DEPLOY_HTTP_URL}ironic-python-agent.kernel
crudini --set ${INIT_CONFIG} conductor rescue_ramdisk ${DEPLOY_HTTP_URL}ironic-python-agent.initramfs

# Set service passwords
if [ -n "${IRONICPASSWORD}" ]; then
    for service in keystone_authtoken service_catalog cinder glance neutron nova swift inspector; do
        crudini --set ${INIT_CONFIG} ${service} password ${IRONICPASSWORD}
    done
fi

# Copy required config to modifiable location
cp /var/lib/config-data/default/dnsmasq.conf /var/lib/ironic/

export DNSMASQ_CFG=/var/lib/ironic/dnsmasq.conf
sed -e "/BLOCK_PODINDEX_${PODINDEX}_BEGIN/,/BLOCK_PODINDEX_${PODINDEX}_END/p" \
    -e "/BLOCK_PODINDEX_.*_BEGIN/,/BLOCK_PODINDEX_.*_END/d" \
    -i ${DNSMASQ_CFG}
sed -e "/BLOCK_PODINDEX_${PODINDEX}_BEGIN/d" \
    -e "/BLOCK_PODINDEX_${PODINDEX}_END/d" \
    -i ${DNSMASQ_CFG}

if [ ! -d "/var/lib/ironic/tmp" ]; then
    mkdir /var/lib/ironic/tmp
fi
if [ ! -d "/var/lib/ironic/httpboot" ]; then
    mkdir /var/lib/ironic/httpboot
fi
if [ ! -d "/var/lib/ironic/ramdisk-logs" ]; then
    mkdir /var/lib/ironic/ramdisk-logs
fi

echo "Conductor init successfully completed"
