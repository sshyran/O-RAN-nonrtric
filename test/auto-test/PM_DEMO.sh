#!/usr/bin/env bash

#  ============LICENSE_START===============================================
#  Copyright (C) 2020 Nordix Foundation. All rights reserved.
#  ========================================================================
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#  ============LICENSE_END=================================================
#

TC_ONELINE_DESCR="Preparation demo setup  - populating a number of ric simulators with types and instances"

#App names to include in the test when running docker, space separated list
DOCKER_INCLUDED_IMAGES="CBS CONSUL CP CR MR A1PMS RICSIM SDNC NGW KUBEPROXY"

#App names to include in the test when running kubernetes, space separated list
KUBE_INCLUDED_IMAGES="CP CR MR A1PMS RICSIM SDNC KUBEPROXY NGW"
#Prestarted app (not started by script) to include in the test when running kubernetes, space separated list
KUBE_PRESTARTED_IMAGES=""

#Ignore image in DOCKER_INCLUDED_IMAGES, KUBE_INCLUDED_IMAGES if
#the image is not configured in the supplied env_file
#Used for images not applicable to all supported profile
CONDITIONALLY_IGNORED_IMAGES="CBS CONSUL NGW"

#Supported test environment profiles
SUPPORTED_PROFILES="ONAP-GUILIN ONAP-HONOLULU ONAP-ISTANBUL ONAP-JAKARTA ORAN-CHERRY ORAN-D-RELEASE ORAN-E-RELEASE ORAN-F-RELEASE"
#Supported run modes
SUPPORTED_RUNMODES="DOCKER KUBE"

. ../common/testcase_common.sh $@

setup_testenvironment

#### TEST BEGIN ####

#Local vars in test script
##########################

use_cr_https
use_a1pms_rest_https
use_sdnc_https
use_simulator_https

if [ "$A1PMS_VERSION" == "V2" ]; then
    notificationurl=$CR_SERVICE_APP_PATH_0"/test"
else
    notificationurl=""
fi

clean_environment

start_kube_proxy

OSC_NUM_RICS=6
STD_NUM_RICS=5

start_ric_simulators  $RIC_SIM_PREFIX"_g1" $OSC_NUM_RICS OSC_2.1.0

start_ric_simulators  $RIC_SIM_PREFIX"_g2" $STD_NUM_RICS STD_1.1.3

if [ "$A1PMS_VERSION" == "V2" ]; then
    start_ric_simulators $RIC_SIM_PREFIX"_g3" $STD_NUM_RICS STD_2.0.0
fi

start_mr #Just to prevent errors in the a1pms log...

start_control_panel $SIM_GROUP/$CONTROL_PANEL_COMPOSE_DIR/$CONTROL_PANEL_CONFIG_FILE

if [ ! -z "$NRT_GATEWAY_APP_NAME" ]; then
    start_gateway $SIM_GROUP/$NRT_GATEWAY_COMPOSE_DIR/$NRT_GATEWAY_CONFIG_FILE
fi

start_sdnc

start_a1pms NORPOXY $SIM_GROUP/$A1PMS_COMPOSE_DIR/$A1PMS_CONFIG_FILE

set_a1pms_trace

prepare_consul_config      SDNC  ".consul_config.json"

if [ $RUNMODE == "KUBE" ]; then
    a1pms_load_config                       ".consul_config.json"
else
    if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
        a1pms_api_put_configuration 200 ".consul_config.json"
    else
        start_consul_cbs
        consul_config_app                   ".consul_config.json"
    fi
fi

a1pms_api_get_status 200

# Print the A1 version for OSC
for ((i=1; i<=$OSC_NUM_RICS; i++))
do
    sim_print $RIC_SIM_PREFIX"_g1_"$i interface
done


# Print the A1 version for STD 1.X
for ((i=1; i<=$STD_NUM_RICS; i++))
do
    sim_print $RIC_SIM_PREFIX"_g2_"$i interface
done

if [ "$A1PMS_VERSION" == "V2" ]; then
    # Print the A1 version for STD 2.X
    for ((i=1; i<=$STD_NUM_RICS; i++))
    do
        sim_print $RIC_SIM_PREFIX"_g3_"$i interface
    done
fi


# Load the polictypes in osc
for ((i=1; i<=$OSC_NUM_RICS; i++))
do
    sim_put_policy_type 201 $RIC_SIM_PREFIX"_g1_"$i 100 demo-testdata/OSC/sim_qos.json
    sim_put_policy_type 201 $RIC_SIM_PREFIX"_g1_"$i 20008 demo-testdata/OSC/sim_tsa.json
done


#Check the number of schemas and the individual schemas in OSC
if [ "$A1PMS_VERSION" == "V2" ]; then

    a1pms_equal json:policy-types 3 300

    for ((i=1; i<=$OSC_NUM_RICS; i++))
    do
        a1pms_equal json:policy-types?ric_id=$RIC_SIM_PREFIX"_g1_"$i 2 120
    done

    # Check the schemas in OSC
    for ((i=1; i<=$OSC_NUM_RICS; i++))
    do
        a1pms_api_get_policy_type 200 100 demo-testdata/OSC/qos-a1pms-modified.json
        a1pms_api_get_policy_type 200 20008 demo-testdata/OSC/tsa-a1pms-modified.json
    done
else
    a1pms_equal json:policy_types 3 300

    for ((i=1; i<=$OSC_NUM_RICS; i++))
    do
        a1pms_equal json:policy_types?ric=$RIC_SIM_PREFIX"_g1_"$i 2 120
    done

    # Check the schemas in OSC
    for ((i=1; i<=$OSC_NUM_RICS; i++))
    do
        a1pms_api_get_policy_schema 200 100 demo-testdata/OSC/qos-a1pms-modified.json
        a1pms_api_get_policy_schema 200 20008 demo-testdata/OSC/tsa-a1pms-modified.json
    done
fi




if [ "$A1PMS_VERSION" == "V2" ]; then

    # Load the polictypes in std
    for ((i=1; i<=$STD_NUM_RICS; i++))
    do
        sim_put_policy_type 201 $RIC_SIM_PREFIX"_g3_"$i STD_QOS_0_2_0 demo-testdata/STD2/sim_qos.json
        sim_put_policy_type 201 $RIC_SIM_PREFIX"_g3_"$i STD_QOS2_0.1.0 demo-testdata/STD2/sim_qos2.json
    done

    #Check the number of schemas and the individual schemas in STD
    a1pms_equal json:policy-types 5 120

    for ((i=1; i<=$STD_NUM_RICS; i++))
    do
        a1pms_equal json:policy-types?ric_id=$RIC_SIM_PREFIX"_g3_"$i 2 120
    done

    # Check the schemas in STD
    for ((i=1; i<=$STD_NUM_RICS; i++))
    do
        a1pms_api_get_policy_type 200 STD_QOS_0_2_0 demo-testdata/STD2/qos-a1pms-modified.json
        a1pms_api_get_policy_type 200 'STD_QOS2_0.1.0' demo-testdata/STD2/qos2-a1pms-modified.json
    done
fi

#Check the number of types
if [ "$A1PMS_VERSION" == "V2" ]; then
    a1pms_equal json:policy-types 5 120
else
    a1pms_equal json:policy_types 3 120
fi


# Create policies
use_a1pms_rest_http

a1pms_api_put_service 201 "Emergency-response-app" 0 "$CR_SERVICE_APP_PATH_0/1"

# Create policies in OSC
for ((i=1; i<=$OSC_NUM_RICS; i++))
do
    generate_policy_uuid
    a1pms_api_put_policy 201 "Emergency-response-app" $RIC_SIM_PREFIX"_g1_"$i 100 $((3000+$i)) NOTRANSIENT $notificationurl demo-testdata/OSC/piqos_template.json 1
    generate_policy_uuid
    a1pms_api_put_policy 201 "Emergency-response-app" $RIC_SIM_PREFIX"_g1_"$i 20008 $((4000+$i)) NOTRANSIENT $notificationurl demo-testdata/OSC/pitsa_template.json 1
done


# Check the number of policies in OSC
for ((i=1; i<=$OSC_NUM_RICS; i++))
do
    sim_equal $RIC_SIM_PREFIX"_g1_"$i num_instances 2
done


# Create policies in STD
for ((i=1; i<=$STD_NUM_RICS; i++))
do
    generate_policy_uuid
    a1pms_api_put_policy 201 "Emergency-response-app" $RIC_SIM_PREFIX"_g2_"$i NOTYPE $((2100+$i)) NOTRANSIENT $notificationurl demo-testdata/STD/pi1_template.json 1
    if [ "$A1PMS_VERSION" == "V2" ]; then
        generate_policy_uuid
        a1pms_api_put_policy 201 "Emergency-response-app" $RIC_SIM_PREFIX"_g3_"$i STD_QOS_0_2_0 $((2300+$i)) NOTRANSIENT $notificationurl demo-testdata/STD2/pi1_template.json 1
        generate_policy_uuid
        a1pms_api_put_policy 201 "Emergency-response-app" $RIC_SIM_PREFIX"_g3_"$i 'STD_QOS2_0.1.0' $((2400+$i)) NOTRANSIENT $notificationurl demo-testdata/STD2/pi1_template.json 1
    fi
done


# Check the number of policies in STD
for ((i=1; i<=$STD_NUM_RICS; i++))
do
    sim_equal $RIC_SIM_PREFIX"_g2_"$i num_instances 1
    if [ "$A1PMS_VERSION" == "V2" ]; then
        sim_equal $RIC_SIM_PREFIX"_g3_"$i num_instances 2
    fi
done

check_a1pms_logs
check_sdnc_logs

#### TEST COMPLETE ####

store_logs          END

print_result

auto_clean_environment