/*
 * ============LICENSE_START=======================================================
 * Copyright (C) 2021 Nordix Foundation.
 * ================================================================================
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 * ============LICENSE_END=========================================================
 */

executor.logger.info("Task Execution: '"+executor.subject.id+"'. Input Fields: '"+executor.inFields+"'");

var fileReaderClass = java.io.FileReader;
var bufferedReaderClass = java.io.BufferedReader;
var oruOduMap;
try {
    var br = new bufferedReaderClass(new fileReaderClass("/home/apexuser/examples/LinkMonitor/config/o-ru-to-o-du-map.json"));
    var jsonString = "";
    var line;
    while ((line = br.readLine()) != null) {
        jsonString += line;
    }
    oruOduMap = JSON.parse(jsonString);
} catch (err) {
    executor.logger.info("Failed to read o-ru-to-o-du-map.json file " + err);
}

var linkFailureInput = executor.inFields.get("LinkFailureInput");
var oruId = linkFailureInput.get("event").get("commonEventHeader").get("sourceName");
var oduId = oruOduMap[oruId];

executor.outFields.put("OruId", oruId);
executor.outFields.put("OduId", oduId);

executor.logger.info(executor.outFields);

true;
