#!/bin/bash

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


TC_ONELINE_DESCR="Resync of RIC via changes in the consul config or pushed config"

#App names to include in the test when running docker, space separated list
DOCKER_INCLUDED_IMAGES="CBS CONSUL CP CR MR A1PMS RICSIM KUBEPROXY"

#Ignore image in DOCKER_INCLUDED_IMAGES, KUBE_INCLUDED_IMAGES if
#the image is not configured in the supplied env_file
#Used for images not applicable to all supported profile
CONDITIONALLY_IGNORED_IMAGES="CBS CONSUL"

#Supported test environment profiles
SUPPORTED_PROFILES="ONAP-GUILIN ONAP-HONOLULU ONAP-ISTANBUL ONAP-JAKARTA ORAN-CHERRY ORAN-D-RELEASE ORAN-E-RELEASE ORAN-F-RELEASE"
#Supported run modes
SUPPORTED_RUNMODES="DOCKER"

. ../common/testcase_common.sh $@

setup_testenvironment

#### TEST BEGIN ####

if [ "$A1PMS_VERSION" == "V2" ]; then
    TESTED_VARIANTS="CONSUL NOCONSUL"
    if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
        TESTED_VARIANTS="NOCONSUL"
    fi
else
    TESTED_VARIANTS="CONSUL"
fi

for consul_conf in $TESTED_VARIANTS ; do
    generate_policy_uuid

    # Clean container and start all needed containers #
    clean_environment

    start_kube_proxy

    start_a1pms NOPROXY $SIM_GROUP/$A1PMS_COMPOSE_DIR/$A1PMS_CONFIG_FILE

    set_a1pms_trace

    # Create service to be able to receive events when rics becomes available
    # Must use rest towards the a1pms since dmaap is not configured yet
    a1pms_api_put_service 201 "ric-registration" 0 "$CR_SERVICE_APP_PATH_0/ric-registration"

    # Start one RIC of each type
    start_ric_simulators ricsim_g1 1  OSC_2.1.0
    start_ric_simulators ricsim_g2 1  STD_1.1.3
    if [ "$A1PMS_VERSION" == "V2" ]; then
        start_ric_simulators ricsim_g3 1  STD_2.0.0
    fi

    start_mr

    start_cr 1

    start_control_panel $SIM_GROUP/$CONTROL_PANEL_COMPOSE_DIR/$CONTROL_PANEL_CONFIG_FILE

    if [ $consul_conf == "CONSUL" ]; then
        start_consul_cbs
    fi

    prepare_consul_config      NOSDNC  ".consul_config.json"

    if [ "$A1PMS_VERSION" == "V2" ] && [ $consul_conf == "NOCONSUL" ]; then
        a1pms_api_put_configuration 200 ".consul_config.json"
        a1pms_api_get_configuration 200 ".consul_config.json"
    else
        consul_config_app                  ".consul_config.json"
    fi

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:rics 3 300

        cr_equal 0 received_callbacks 3 120

        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g1_1 ricsim_g2_1 ricsim_g3_1
    else
        a1pms_equal json:rics 2 300
    fi

    # Add an STD RIC and check
    start_ric_simulators ricsim_g2 2  STD_1.1.3

    prepare_consul_config      NOSDNC  ".consul_config.json"
    if [ "$A1PMS_VERSION" == "V2" ] && [ $consul_conf == "NOCONSUL" ]; then
        a1pms_api_put_configuration 200 ".consul_config.json"
        a1pms_api_get_configuration 200 ".consul_config.json"
    else
        consul_config_app                  ".consul_config.json"
    fi

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:rics 4 120

        cr_equal 0 received_callbacks 4 120

        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g2_2
    else
        a1pms_equal json:rics 3 120
    fi

    check_a1pms_logs


    # Remove one RIC RIC and check
    start_ric_simulators ricsim_g2 1  STD_1.1.3

    prepare_consul_config      NOSDNC  ".consul_config.json"
    if [ "$A1PMS_VERSION" == "V2" ] && [ $consul_conf == "NOCONSUL" ]; then
        a1pms_api_put_configuration 200 ".consul_config.json"
        a1pms_api_get_configuration 200 ".consul_config.json"
    else
        consul_config_app                  ".consul_config.json"
    fi

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:rics 3 120

        cr_equal 0 received_callbacks 4 120
    else
        a1pms_equal json:rics 2 120
    fi

    if [ "$A1PMS_VERSION" == "V2" ] && [ $consul_conf == "NOCONSUL" ]; then
        a1pms_api_get_configuration 200 ".consul_config.json"
    fi

    check_a1pms_logs

    store_logs          END_$consul_conf
done


#### TEST COMPLETE ####


print_result

auto_clean_environment
