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

TC_ONELINE_DESCR="Repeatedly create and delete policies in each RICs for 24h (or configured number of days). Via a1pms REST/DMAAP/DMAAP_BATCH and SDNC using http or https"

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

generate_policy_uuid

#Local vars in test script
##########################

# Number of RICs per interface type (OSC and STD)
NUM_RICS=30
if [ "$A1PMS_VERSION" == "V2" ]; then
   NUM_RICS=20 # 3 A1 interfaces test, less sims per interface. total sims will be same
fi

# Number of policy instances per RIC
NUM_INSTANCES=5

DAYS=3

clean_environment

start_kube_proxy

# use HTTP or HTTPS for all apis
HTTPX=HTTPS

if [ $HTTPX == "HTTP" ]; then
   use_cr_http
   use_a1pms_rest_http
   use_sdnc_http
   use_simulator_http
else
   use_cr_https
   use_a1pms_rest_https
   use_sdnc_https
   use_simulator_https
fi

start_ric_simulators ricsim_g1 $NUM_RICS OSC_2.1.0

start_ric_simulators ricsim_g2 $NUM_RICS STD_1.1.3

if [ "$A1PMS_VERSION" == "V2" ]; then
   start_ric_simulators ricsim_g3 $NUM_RICS  STD_2.0.0
fi

start_mr

start_cr 1

start_control_panel $SIM_GROUP/$CONTROL_PANEL_COMPOSE_DIR/$CONTROL_PANEL_CONFIG_FILE

if [ ! -z "$NRT_GATEWAY_APP_NAME" ]; then
   start_gateway $SIM_GROUP/$NRT_GATEWAY_COMPOSE_DIR/$NRT_GATEWAY_CONFIG_FILE
fi

start_a1pms NORPOXY $SIM_GROUP/$A1PMS_COMPOSE_DIR/$A1PMS_CONFIG_FILE

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

start_sdnc


a1pms_api_get_status 200

echo "Print the interface for group 1 simulators, shall be OSC"
for ((i=1; i<=$NUM_RICS; i++))
do
   sim_print ricsim_g1_$i interface
done

echo "Print the interface for group 2 simulators, shall be STD"
for ((i=1; i<=$NUM_RICS; i++))
do
   sim_print ricsim_g2_$i interface
done

if [ "$A1PMS_VERSION" == "V2" ]; then
   echo "Print the interface for group 2 simulators, shall be STD 2"
   for ((i=1; i<=$NUM_RICS; i++))
   do
      sim_print ricsim_g3_$i interface
   done
fi

echo "Load policy type in group 1 simulators"
for ((i=1; i<=$NUM_RICS; i++))
do
   sim_put_policy_type 201 ricsim_g1_$i 1 testdata/OSC/sim_1.json
done

if [ "$A1PMS_VERSION" == "V2" ]; then
   echo "Load policy type in group 3 simulators"
   for ((i=1; i<=$NUM_RICS; i++))
   do
      sim_put_policy_type 201 ricsim_g3_$i STD_QOS2_0.1.0 testdata/STD2/sim_qos2.json
   done
fi

echo "Check the number of instances in  group 1 simulators, shall be 0"
for ((i=1; i<=$NUM_RICS; i++))
do
   sim_equal ricsim_g1_$i num_instances 0
done

echo "Check the number of instances in  group 2 simulators, shall be 0"
for ((i=1; i<=$NUM_RICS; i++))
do
   sim_equal ricsim_g2_$i num_instances 0
done

if [ "$A1PMS_VERSION" == "V2" ]; then
   echo "Check the number of instances in group 3 simulators, shall be 0"
   for ((i=1; i<=$NUM_RICS; i++))
   do
      sim_equal ricsim_g3_$i num_instances 0
   done
fi

echo "Wait for the a1pms to refresh types from the simulator"
if [ "$A1PMS_VERSION" == "V2" ]; then
   a1pms_equal json:policy-types 3 300
else
   a1pms_equal json:policy_types 2 300
fi

echo "Check the number of types in the a1pms for each ric is 1"
for ((i=1; i<=$NUM_RICS; i++))
do
   if [ "$A1PMS_VERSION" == "V2" ]; then
      a1pms_equal json:policy-types?ric_id=ricsim_g1_$i 1 120
      a1pms_equal json:policy-types?ric_id=ricsim_g3_$i 1 120
   else
      a1pms_equal json:policy_types?ric=ricsim_g1_$i 1 120
   fi
done

echo "Register a service"
a1pms_api_put_service 201 "serv1" 0 "$CR_SERVICE_APP_PATH_0/1"

TEST_DURATION=$((24*3600*$DAYS))
TEST_START=$SECONDS

A1PMS_INTERFACES="REST REST_PARALLEL DMAAP DMAAP-BATCH"

MR_MESSAGES=0

if [ "$A1PMS_VERSION" == "V2" ]; then
      notificationurl=$CR_SERVICE_APP_PATH_0"/test"
else
      notificationurl=""
fi

while [ $(($SECONDS-$TEST_START)) -lt $TEST_DURATION ]; do

    echo ""
    echo "#########################################################################################################"
    echo -e $BOLD"INFO: Test executed for: "$(($SECONDS-$TEST_START)) "seconds. Target is: "$TEST_DURATION" seconds."$EBOLD
    echo "#########################################################################################################"
    echo ""

   for interface in $A1PMS_INTERFACES ; do

      echo "############################################"
      echo "## Testing using a1pms interface: $interface ##"
      echo "############################################"

      if [ $interface == "REST" ] || [ $interface == "REST_PARALLEL" ]; then
         if [ $HTTPX == "HTTP" ]; then
            use_a1pms_rest_http
         else
            use_a1pms_rest_https
         fi
      else
         if [ $HTTPX == "HTTPS" ]; then
               echo "Using secure ports towards dmaap"
               use_a1pms_dmaap_https
         else
               echo "Using non-secure ports towards dmaap"
               use_a1pms_dmaap_http
         fi
      fi

      echo "Create $NUM_INSTANCES instances in each OSC RIC"
      INSTANCE_ID=200000
      INSTANCES=0
      if [ $interface == "REST_PARALLEL" ]; then
         a1pms_api_put_policy_parallel 201 "serv1" ricsim_g1_ $NUM_RICS 1 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/OSC/pi1_template.json $NUM_INSTANCES 3
      fi
      for ((i=1; i<=$NUM_RICS; i++))
      do
         if [ $interface == "DMAAP-BATCH" ]; then
            a1pms_api_put_policy_batch 201 "serv1" ricsim_g1_$i 1 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/OSC/pi1_template.json $NUM_INSTANCES
         elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
            a1pms_api_put_policy 201 "serv1" ricsim_g1_$i 1 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/OSC/pi1_template.json $NUM_INSTANCES
         fi
         if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
            MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
         fi
         sim_equal ricsim_g1_$i num_instances $NUM_INSTANCES
         INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
         INSTANCES=$(($INSTANCES+$NUM_INSTANCES))
      done

      if [ "$A1PMS_VERSION" == "V2" ]; then
         a1pms_equal json:policy-instances $INSTANCES
      else
         a1pms_equal json:policy_ids $INSTANCES
      fi

      echo "Create $NUM_INSTANCES instances in each STD RIC"
      if [ $interface == "REST_PARALLEL" ]; then
         a1pms_api_put_policy_parallel 201 "serv1" ricsim_g2_ $NUM_RICS NOTYPE $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD/pi1_template.json $NUM_INSTANCES 3
      fi
      for ((i=1; i<=$NUM_RICS; i++))
      do
         if [ $interface == "DMAAP-BATCH" ]; then
            a1pms_api_put_policy_batch 201 "serv1" ricsim_g2_$i NOTYPE $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD/pi1_template.json $NUM_INSTANCES
         elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
            a1pms_api_put_policy 201 "serv1" ricsim_g2_$i NOTYPE $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD/pi1_template.json $NUM_INSTANCES
         fi
         if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
            MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
         fi
         sim_equal ricsim_g2_$i num_instances $NUM_INSTANCES
         INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
         INSTANCES=$(($INSTANCES+$NUM_INSTANCES))
      done

      if [ "$A1PMS_VERSION" == "V2" ]; then
         a1pms_equal json:policy-instances $INSTANCES
      else
         a1pms_equal json:policy_ids $INSTANCES
      fi

      if [ "$A1PMS_VERSION" == "V2" ]; then
         echo "Create $NUM_INSTANCES instances in each STD 2 RIC"
         if [ $interface == "REST_PARALLEL" ]; then
            a1pms_api_put_policy_parallel 201 "serv1" ricsim_g3_ $NUM_RICS STD_QOS2_0.1.0 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD2/pi_qos2_template.json $NUM_INSTANCES 3
         fi
         for ((i=1; i<=$NUM_RICS; i++))
         do
            if [ $interface == "DMAAP-BATCH" ]; then
               a1pms_api_put_policy_batch 201 "serv1" ricsim_g3_$i STD_QOS2_0.1.0 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD2/pi_qos2_template.json $NUM_INSTANCES
            elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
               a1pms_api_put_policy 201 "serv1" ricsim_g3_$i STD_QOS2_0.1.0 $INSTANCE_ID NOTRANSIENT $notificationurl testdata/STD2/pi_qos2_template.json $NUM_INSTANCES
            fi
            if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
               MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
            fi
            sim_equal ricsim_g3_$i num_instances $NUM_INSTANCES
            INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
            INSTANCES=$(($INSTANCES+$NUM_INSTANCES))
         done

         if [ "$A1PMS_VERSION" == "V2" ]; then
            a1pms_equal json:policy-instances $INSTANCES
         else
            a1pms_equal json:policy_ids $INSTANCES
         fi
      fi


      echo "Delete all instances in each OSC RIC"

      INSTANCE_ID=200000
      if [ $interface == "REST_PARALLEL" ]; then
         a1pms_api_delete_policy_parallel 204 $NUM_RICS $INSTANCE_ID $NUM_INSTANCES 3
      fi
      for ((i=1; i<=$NUM_RICS; i++))
      do
         if [ $interface == "DMAAP-BATCH" ]; then
            a1pms_api_delete_policy_batch 204 $INSTANCE_ID $NUM_INSTANCES
         elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
            a1pms_api_delete_policy 204 $INSTANCE_ID $NUM_INSTANCES
         fi
         if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
            MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
         fi
         INSTANCES=$(($INSTANCES-$NUM_INSTANCES))
         sim_equal ricsim_g1_$i num_instances 0
         INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
      done

      if [ "$A1PMS_VERSION" == "V2" ]; then
         a1pms_equal json:policy-instances $INSTANCES
      else
         a1pms_equal json:policy_ids $INSTANCES
      fi

      echo "Delete all instances in each STD RIC"

      if [ $interface == "REST_PARALLEL" ]; then
         a1pms_api_delete_policy_parallel 204 $NUM_RICS $INSTANCE_ID $NUM_INSTANCES 3
      fi
      for ((i=1; i<=$NUM_RICS; i++))
      do
         if [ $interface == "DMAAP-BATCH" ]; then
            a1pms_api_delete_policy_batch 204 $INSTANCE_ID $NUM_INSTANCES
         elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
            a1pms_api_delete_policy 204 $INSTANCE_ID $NUM_INSTANCES
         fi
         if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
            MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
         fi
         INSTANCES=$(($INSTANCES-$NUM_INSTANCES))
         sim_equal ricsim_g2_$i num_instances 0
         INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
      done

      if [ "$A1PMS_VERSION" == "V2" ]; then
         a1pms_equal json:policy-instances $INSTANCES
      else
         a1pms_equal json:policy_ids $INSTANCES
      fi

      if [ "$A1PMS_VERSION" == "V2" ]; then
         echo "Delete all instances in each STD 2 RIC"

         if [ $interface == "REST_PARALLEL" ]; then
            a1pms_api_delete_policy_parallel 204 $NUM_RICS $INSTANCE_ID $NUM_INSTANCES 3
         fi
         for ((i=1; i<=$NUM_RICS; i++))
         do
            if [ $interface == "DMAAP-BATCH" ]; then
               a1pms_api_delete_policy_batch 204 $INSTANCE_ID $NUM_INSTANCES
            elif [ $interface == "DMAAP" ] || [ $interface == "REST" ]; then
               a1pms_api_delete_policy 204 $INSTANCE_ID $NUM_INSTANCES
            fi
            if [ $interface == "DMAAP" ] || [ $interface == "DMAAP-BATCH" ]; then
               MR_MESSAGES=$(($MR_MESSAGES+$NUM_INSTANCES))
            fi
            INSTANCES=$(($INSTANCES-$NUM_INSTANCES))
            sim_equal ricsim_g3_$i num_instances 0
            INSTANCE_ID=$(($INSTANCE_ID+$NUM_INSTANCES))
         done

         if [ "$A1PMS_VERSION" == "V2" ]; then
            a1pms_equal json:policy-instances $INSTANCES
         else
            a1pms_equal json:policy_ids $INSTANCES
         fi
      fi

      mr_equal requests_submitted $MR_MESSAGES
      mr_equal requests_fetched $MR_MESSAGES
      mr_equal responses_submitted $MR_MESSAGES
      mr_equal responses_fetched $MR_MESSAGES
      mr_equal current_requests 0
      mr_equal current_responses 0


      for ((i=1; i<=$NUM_RICS; i++))
      do
         sim_contains_str ricsim_g1_$i remote_hosts $SDNC_APP_NAME
         sim_contains_str ricsim_g2_$i remote_hosts $SDNC_APP_NAME

         if [ "$A1PMS_VERSION" == "V2" ]; then
            sim_contains_str ricsim_g3_$i remote_hosts $SDNC_APP_NAME
         fi
      done

   done

done

check_a1pms_logs
check_sdnc_logs

#### TEST COMPLETE ####

store_logs          END

print_result

auto_clean_environment