/*-
 * ========================LICENSE_START=================================
 * O-RAN-SC
 * %%
 * Copyright (C) 2020 Nordix Foundation
 * %%
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
 * ========================LICENSE_END===================================
 */

package org.oransc.enrichment.controllers.producer;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.google.gson.annotations.SerializedName;

import io.swagger.v3.oas.annotations.media.Schema;

import org.immutables.gson.Gson;

@Gson.TypeAdapters
@Schema(name = "producer_ei_type_info", description = "Information for an EI type")
public class ProducerEiTypeInfo {

    @Schema(name = "ei_job_data_schema", description = "Json schema for the job data", required = true)
    @SerializedName("ei_job_data_schema")
    @JsonProperty(value = "ei_job_data_schema", required = true)
    public Object jobDataSchema;

    public ProducerEiTypeInfo(Object jobDataSchema) {
        this.jobDataSchema = jobDataSchema;
    }

    public ProducerEiTypeInfo() {
    }

}
