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

TC_ONELINE_DESCR="Change supported policy types and reconfigure rics"

#App names to include in the test when running docker, space separated list
DOCKER_INCLUDED_IMAGES="CBS CONSUL CP CR MR A1PMS RICSIM SDNC KUBEPROXY"

#App names to include in the test when running kubernetes, space separated list
KUBE_INCLUDED_IMAGES="CP CR MR A1PMS RICSIM SDNC KUBEPROXY"
#Prestarted app (not started by script) to include in the test when running kubernetes, space separated list
KUBE_PRESTARTED_IMAGES=""

#Ignore image in DOCKER_INCLUDED_IMAGES, KUBE_INCLUDED_IMAGES if
#the image is not configured in the supplied env_file
#Used for images not applicable to all supported profile
CONDITIONALLY_IGNORED_IMAGES="CBS CONSUL"

#Supported test environment profiles
SUPPORTED_PROFILES="ONAP-GUILIN ONAP-HONOLULU ONAP-ISTANBUL ONAP-JAKARTA ORAN-CHERRY ORAN-D-RELEASE ORAN-E-RELEASE ORAN-F-RELEASE"
#Supported run modes
SUPPORTED_RUNMODES="DOCKER KUBE"

. ../common/testcase_common.sh $@

setup_testenvironment

#### TEST BEGIN ####

generate_policy_uuid

use_cr_http

NUM_RICS=10
NUM_RICS_2=$(($NUM_RICS-2))

# Tested variants of REST/SDNC config
TESTED_VARIANTS="REST   REST+SDNC"

for interface in $TESTED_VARIANTS ; do

    echo "#####################################################################"
    echo "#####################################################################"
    echo "### Testing a1pms: "$interface
    echo "#####################################################################"
    echo "#####################################################################"


    # Clean container and start all needed containers #
    clean_environment

    start_kube_proxy

    #Start simulators and prepare two configs

    start_ric_simulators ricsim_g1 $NUM_RICS_2 OSC_2.1.0

    start_cr 1

    start_mr

    if [ $RUNMODE == "DOCKER" ]; then
        if [[ "$A1PMS_FEATURE_LEVEL" != *"NOCONSUL"* ]]; then
            start_consul_cbs
        fi
    fi

    # Create first config
    if [[ $interface = *"SDNC"* ]]; then
        start_sdnc
        prepare_consul_config      SDNC  ".consul_config_initial.json"
    else
        prepare_consul_config      NOSDNC  ".consul_config_initial.json"
    fi

    # Create 2nd config and save for later
    start_ric_simulators ricsim_g1 $NUM_RICS OSC_2.1.0

    if [[ $interface = *"SDNC"* ]]; then
        prepare_consul_config      SDNC  ".consul_config_all.json"
    else
        prepare_consul_config      NOSDNC  ".consul_config_all.json"
    fi

    if [ $RUNMODE == "KUBE" ] && [[ "$A1PMS_FEATURE_LEVEL" == *"INITIALCONFIGMAP"* ]]; then
        start_a1pms NORPOXY $SIM_GROUP/$A1PMS_COMPOSE_DIR/application2.yaml
    else
        start_a1pms NORPOXY $SIM_GROUP/$A1PMS_COMPOSE_DIR/$A1PMS_CONFIG_FILE
    fi

    set_a1pms_trace

    a1pms_api_get_status 200

    # Create service to be able to receive events when rics becomes available
    # Must use rest towards the a1pms since dmaap is not configured yet
    a1pms_api_put_service 201 "ric-registration" 0 "$CR_SERVICE_APP_PATH_0/ric-registration"

    #Load first config
    if [ $RUNMODE == "KUBE" ]; then
        if [[ "$A1PMS_FEATURE_LEVEL" == *"INITIALCONFIGMAP"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_initial.json"
            a1pms_api_get_configuration 200              ".consul_config_initial.json"
        else
            a1pms_load_config                      ".consul_config_initial.json"
        fi
    else
        if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_initial.json"
            a1pms_api_get_configuration 200              ".consul_config_initial.json"
        else
            consul_config_app                      ".consul_config_initial.json"
        fi
    fi

    for ((i=1; i<=${NUM_RICS}; i++))
    do
        sim_print ricsim_g1_$i interface
    done

    # All sims running but 2 are not configured in consul
    a1pms_equal json:rics 8 300

    if [ "$A1PMS_VERSION" == "V2" ]; then
        cr_equal 0 received_callbacks?id=ric-registration 8 120
        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g1_1 ricsim_g1_2  ricsim_g1_3 ricsim_g1_4 ricsim_g1_5 ricsim_g1_6  ricsim_g1_7  ricsim_g1_8
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:NOTYPE:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:NOTYPE:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:NOTYPE:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:NOTYPE:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:NOTYPE:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:NOTYPE:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:NOTYPE:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:NOTYPE:???? "


    sim_put_policy_type 201 ricsim_g1_1 1 testdata/OSC/sim_1.json
    sim_put_policy_type 201 ricsim_g1_2 1 testdata/OSC/sim_1.json
    sim_put_policy_type 201 ricsim_g1_3 1 testdata/OSC/sim_1.json
    sim_put_policy_type 201 ricsim_g1_4 1 testdata/OSC/sim_1.json
    sim_put_policy_type 201 ricsim_g1_5 1 testdata/OSC/sim_1.json

    sim_put_policy_type 201 ricsim_g1_2 2 testdata/OSC/sim_2.json
    sim_put_policy_type 201 ricsim_g1_3 2 testdata/OSC/sim_2.json
    sim_put_policy_type 201 ricsim_g1_4 2 testdata/OSC/sim_2.json
    sim_put_policy_type 201 ricsim_g1_5 2 testdata/OSC/sim_2.json
    sim_put_policy_type 201 ricsim_g1_6 2 testdata/OSC/sim_2.json

    sim_put_policy_type 201 ricsim_g1_3 3 testdata/OSC/sim_3.json
    sim_put_policy_type 201 ricsim_g1_4 3 testdata/OSC/sim_3.json
    sim_put_policy_type 201 ricsim_g1_5 3 testdata/OSC/sim_3.json
    sim_put_policy_type 201 ricsim_g1_6 3 testdata/OSC/sim_3.json
    sim_put_policy_type 201 ricsim_g1_7 3 testdata/OSC/sim_3.json

    sim_put_policy_type 201 ricsim_g1_4 4 testdata/OSC/sim_4.json
    sim_put_policy_type 201 ricsim_g1_5 4 testdata/OSC/sim_4.json
    sim_put_policy_type 201 ricsim_g1_6 4 testdata/OSC/sim_4.json
    sim_put_policy_type 201 ricsim_g1_7 4 testdata/OSC/sim_4.json
    sim_put_policy_type 201 ricsim_g1_8 4 testdata/OSC/sim_4.json

    sim_put_policy_type 201 ricsim_g1_5 5 testdata/OSC/sim_5.json
    sim_put_policy_type 201 ricsim_g1_6 5 testdata/OSC/sim_5.json
    sim_put_policy_type 201 ricsim_g1_7 5 testdata/OSC/sim_5.json
    sim_put_policy_type 201 ricsim_g1_8 5 testdata/OSC/sim_5.json

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:policy-types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy-types?ric_id=ricsim_g1_1 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_2 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_3 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_4 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_5 5 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_6 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_7 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 2 120
    else
        a1pms_equal json:policy_types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy_types?ric=ricsim_g1_1 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_2 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_3 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_4 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_5 5 120
        a1pms_equal json:policy_types?ric=ricsim_g1_6 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_7 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 2 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3,4:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,4,5:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,4,5:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,4,5:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:4,5:???? "

    if [ "$A1PMS_VERSION" == "V2" ]; then
        cr_equal 0 received_callbacks?id=ric-registration 16 120
        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g1_1 ricsim_g1_2  ricsim_g1_3 ricsim_g1_4 ricsim_g1_5 ricsim_g1_6  ricsim_g1_7  ricsim_g1_8
    fi

    #Load config with all rics
    if [ $RUNMODE == "KUBE" ]; then
        if [[ "$A1PMS_FEATURE_LEVEL" == *"INITIALCONFIGMAP"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_all.json"
            a1pms_api_get_configuration 200              ".consul_config_all.json"
        else
            a1pms_load_config                      ".consul_config_all.json"
        fi
    else
        if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
            a1pms_api_put_configuration 200               ".consul_config_all.json"
            a1pms_api_get_configuration 200               ".consul_config_all.json"
        else
            consul_config_app                       ".consul_config_all.json"
        fi
    fi

    a1pms_equal json:rics 10 120

    if [ "$A1PMS_VERSION" == "V2" ]; then
        cr_equal 0 received_callbacks?id=ric-registration 18 120
        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g1_9  ricsim_g1_10
    fi

    sim_put_policy_type 201 ricsim_g1_9 5 testdata/OSC/sim_5.json

    if [ "$A1PMS_VERSION" == "V2" ]; then

        a1pms_equal json:policy-types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy-types?ric_id=ricsim_g1_1 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_2 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_3 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_4 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_5 5 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_6 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_7 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_9 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_10 0 120
    else

        a1pms_equal json:policy_types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy_types?ric=ricsim_g1_1 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_2 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_3 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_4 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_5 5 120
        a1pms_equal json:policy_types?ric=ricsim_g1_6 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_7 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_9 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_10 0 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3,4:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,4,5:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,4,5:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,4,5:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:4,5:???? \
                             ricsim_g1_9:me1_ricsim_g1_9,me2_ricsim_g1_9:5:???? \
                             ricsim_g1_10:me1_ricsim_g1_10,me2_ricsim_g1_10:NOTYPE:???? "

    if [ "$A1PMS_VERSION" == "V2" ]; then
        cr_equal 0 received_callbacks?id=ric-registration 19 120
        cr_api_check_all_sync_events 200 0 ric-registration ricsim_g1_9
    fi

    #No policy type in sim #10

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:policy-types 5
    else
        a1pms_equal json:policy_types 5
    fi

    a1pms_api_put_service 201 "serv1" 3600 "$CR_SERVICE_APP_PATH_0/serv1"

    if [ "$A1PMS_VERSION" == "V2" ]; then
        notificationurl=$CR_SERVICE_APP_PATH_0"/test"
    else
        notificationurl=""
    fi

    sleep_wait 120

    # Load config with reduced number of rics
    if [ $RUNMODE == "KUBE" ]; then
        if [[ "$A1PMS_FEATURE_LEVEL" == *"INITIALCONFIGMAP"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_initial.json"
            a1pms_api_get_configuration 200              ".consul_config_initial.json"
        else
            a1pms_load_config                      ".consul_config_initial.json"
        fi
    else
        if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_initial.json"
            a1pms_api_get_configuration 200              ".consul_config_initial.json"
        else
            consul_config_app                      ".consul_config_initial.json"
        fi
    fi

    a1pms_equal json:rics 8 120

    if [ "$A1PMS_VERSION" == "V2" ]; then
        cr_equal 0 received_callbacks?id=ric-registration 19 120
        cr_api_check_all_sync_events 200 0 ric-registration EMPTY
    fi

    if [ "$A1PMS_VERSION" == "V2" ]; then

        a1pms_equal json:policy-types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy-types?ric_id=ricsim_g1_1 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_2 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_3 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_4 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_5 5 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_6 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_7 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 2 120
    else

        a1pms_equal json:policy_types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy_types?ric=ricsim_g1_1 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_2 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_3 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_4 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_5 5 120
        a1pms_equal json:policy_types?ric=ricsim_g1_6 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_7 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 2 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3,4:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,4,5:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,4,5:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,4,5:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:4,5:???? "

    sleep_wait 120

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:policy-instances 0
    else
        a1pms_equal json:policy_ids 0
    fi

    a1pms_api_get_policy_types 404 ricsim_g1_9

    # Load config with all rics
    if [ $RUNMODE == "KUBE" ]; then
        if [[ "$A1PMS_FEATURE_LEVEL" == *"INITIALCONFIGMAP"* ]]; then
            a1pms_api_put_configuration 200              ".consul_config_all.json"
            a1pms_api_get_configuration 200              ".consul_config_all.json"
        else
            a1pms_load_config                      ".consul_config_all.json"
        fi
    else
        if [[ "$A1PMS_FEATURE_LEVEL" == *"NOCONSUL"* ]]; then
            a1pms_api_put_configuration 200               ".consul_config_all.json"
            a1pms_api_get_configuration 200               ".consul_config_all.json"
        else
            consul_config_app                      ".consul_config_all.json"
        fi
    fi

    a1pms_equal json:rics 10 120

    if [ "$A1PMS_VERSION" == "V2" ]; then

        a1pms_equal json:policy-types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy-types?ric_id=ricsim_g1_1 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_2 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_3 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_4 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_5 5 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_6 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_7 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_9 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_10 0 120
    else

        a1pms_equal json:policy_types 5 120

        echo "Check the number of types in the a1pms for each ric"
        a1pms_equal json:policy_types?ric=ricsim_g1_1 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_2 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_3 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_4 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_5 5 120
        a1pms_equal json:policy_types?ric=ricsim_g1_6 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_7 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_9 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_10 0 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3,4:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,4,5:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,4,5:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,4,5:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:4,5:???? \
                             ricsim_g1_9:me1_ricsim_g1_9,me2_ricsim_g1_9:5:???? \
                             ricsim_g1_10:me1_ricsim_g1_10,me2_ricsim_g1_10:NOTYPE:???? "

    sleep_wait 120

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:policy-instances 0
    else
        a1pms_equal json:policy_ids 0
    fi

    sim_equal ricsim_g1_9 num_instances 0


    sim_delete_policy_type 204 ricsim_g1_4 4
    sim_delete_policy_type 204 ricsim_g1_5 4
    sim_delete_policy_type 204 ricsim_g1_6 4
    sim_delete_policy_type 204 ricsim_g1_7 4

    sleep_wait 120

    if [ "$A1PMS_VERSION" == "V2" ]; then

        a1pms_equal json:policy-types 5 120

        a1pms_equal json:policy-types?ric_id=ricsim_g1_1 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_2 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_3 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_4 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_5 4 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_6 3 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_7 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 2 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_9 1 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_10 0 120
    else

        a1pms_equal json:policy_types 5 120

        a1pms_equal json:policy_types?ric=ricsim_g1_1 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_2 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_3 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_4 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_5 4 120
        a1pms_equal json:policy_types?ric=ricsim_g1_6 3 120
        a1pms_equal json:policy_types?ric=ricsim_g1_7 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 2 120
        a1pms_equal json:policy_types?ric=ricsim_g1_9 1 120
        a1pms_equal json:policy_types?ric=ricsim_g1_10 0 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                             ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                             ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                             ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3:???? \
                             ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,5:???? \
                             ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,5:???? \
                             ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,5:???? \
                             ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:4,5:???? \
                             ricsim_g1_9:me1_ricsim_g1_9,me2_ricsim_g1_9:5:???? \
                             ricsim_g1_10:me1_ricsim_g1_10,me2_ricsim_g1_10:NOTYPE:???? "

    sim_delete_policy_type 204 ricsim_g1_8 4

    if [ "$A1PMS_VERSION" == "V2" ]; then
        a1pms_equal json:policy-types 5 120
        a1pms_equal json:policy-types?ric_id=ricsim_g1_8 1 120
    else
        a1pms_equal json:policy_types 5 120
        a1pms_equal json:policy_types?ric=ricsim_g1_8 1 120
    fi

    a1pms_api_get_rics 200 NOTYPE "ricsim_g1_1:me1_ricsim_g1_1,me2_ricsim_g1_1:1:???? \
                            ricsim_g1_2:me1_ricsim_g1_2,me2_ricsim_g1_2:1,2:???? \
                            ricsim_g1_3:me1_ricsim_g1_3,me2_ricsim_g1_3:1,2,3:???? \
                            ricsim_g1_4:me1_ricsim_g1_4,me2_ricsim_g1_4:1,2,3:???? \
                            ricsim_g1_5:me1_ricsim_g1_5,me2_ricsim_g1_5:1,2,3,5:???? \
                            ricsim_g1_6:me1_ricsim_g1_6,me2_ricsim_g1_6:2,3,5:???? \
                            ricsim_g1_7:me1_ricsim_g1_7,me2_ricsim_g1_7:3,5:???? \
                            ricsim_g1_8:me1_ricsim_g1_8,me2_ricsim_g1_8:5:???? \
                            ricsim_g1_9:me1_ricsim_g1_9,me2_ricsim_g1_9:5:???? \
                            ricsim_g1_10:me1_ricsim_g1_10,me2_ricsim_g1_10:NOTYPE:???? "



    check_a1pms_logs
    if [[ $interface = *"SDNC"* ]]; then
        check_sdnc_logs
    fi

    store_logs          ${interface}

done


#### TEST COMPLETE ####


print_result

auto_clean_environment