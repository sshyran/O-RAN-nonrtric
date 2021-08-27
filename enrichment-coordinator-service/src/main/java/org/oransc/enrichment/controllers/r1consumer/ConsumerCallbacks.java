/*-
 * ========================LICENSE_START=================================
 * O-RAN-SC
 * %%
 * Copyright (C) 2021 Nordix Foundation
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

package org.oransc.enrichment.controllers.r1consumer;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import org.oransc.enrichment.clients.AsyncRestClient;
import org.oransc.enrichment.clients.AsyncRestClientFactory;
import org.oransc.enrichment.configuration.ApplicationConfig;
import org.oransc.enrichment.repository.InfoType;
import org.oransc.enrichment.repository.InfoTypeSubscriptions;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

/**
 * Callbacks to the Consumer. Notifies consumer according to the API (which this
 * class adapts to)
 */
@SuppressWarnings("java:S3457") // No need to call "toString()" method as formatting and string ..
@Component
public class ConsumerCallbacks implements InfoTypeSubscriptions.Callbacks {

    private static Gson gson = new GsonBuilder().create();

    private final AsyncRestClient restClient;

    public ConsumerCallbacks(@Autowired ApplicationConfig config) {
        AsyncRestClientFactory restClientFactory = new AsyncRestClientFactory(config.getWebClientConfig());
        this.restClient = restClientFactory.createRestClientNoHttpProxy("");
    }

    @Override
    public Mono<String> notifyTypeRegistered(InfoType type, InfoTypeSubscriptions.SubscriptionInfo subscriptionInfo) {
        ConsumerTypeRegistrationInfo info = new ConsumerTypeRegistrationInfo(type.getJobDataSchema(),
            ConsumerTypeRegistrationInfo.ConsumerTypeStatusValues.REGISTERED, type.getId());
        String body = gson.toJson(info);

        return restClient.post(subscriptionInfo.getCallbackUrl(), body);

    }

    @Override
    public Mono<String> notifyTypeRemoved(InfoType type, InfoTypeSubscriptions.SubscriptionInfo subscriptionInfo) {
        ConsumerTypeRegistrationInfo info = new ConsumerTypeRegistrationInfo(type.getJobDataSchema(),
            ConsumerTypeRegistrationInfo.ConsumerTypeStatusValues.DEREGISTERED, type.getId());
        String body = gson.toJson(info);
        return restClient.post(subscriptionInfo.getCallbackUrl(), body);
    }

}
