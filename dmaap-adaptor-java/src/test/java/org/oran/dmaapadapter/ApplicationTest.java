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

package org.oran.dmaapadapter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.gson.JsonParser;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Paths;

import org.json.JSONObject;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.oran.dmaapadapter.clients.AsyncRestClient;
import org.oran.dmaapadapter.clients.AsyncRestClientFactory;
import org.oran.dmaapadapter.configuration.ApplicationConfig;
import org.oran.dmaapadapter.configuration.ImmutableHttpProxyConfig;
import org.oran.dmaapadapter.configuration.ImmutableWebClientConfig;
import org.oran.dmaapadapter.configuration.WebClientConfig;
import org.oran.dmaapadapter.configuration.WebClientConfig.HttpProxyConfig;
import org.oran.dmaapadapter.controllers.ProducerCallbacksController;
import org.oran.dmaapadapter.r1.ConsumerJobInfo;
import org.oran.dmaapadapter.r1.ProducerJobInfo;
import org.oran.dmaapadapter.repository.InfoType;
import org.oran.dmaapadapter.repository.InfoTypes;
import org.oran.dmaapadapter.repository.Jobs;
import org.oran.dmaapadapter.tasks.ProducerRegstrationTask;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.LocalServerPort;
import org.springframework.boot.web.servlet.server.ServletWebServerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.junit.jupiter.SpringExtension;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

@ExtendWith(SpringExtension.class)
@SpringBootTest(webEnvironment = WebEnvironment.DEFINED_PORT)
@TestPropertySource(properties = { //
        "server.ssl.key-store=./config/keystore.jks", //
        "app.webclient.trust-store=./config/truststore.jks", //
        "app.configuration-filepath=./src/test/resources/test_application_configuration.json"//
})
class ApplicationTest {

    @Autowired
    private ApplicationConfig applicationConfig;

    @Autowired
    private ProducerRegstrationTask producerRegstrationTask;

    @Autowired
    private Jobs jobs;

    @Autowired
    private InfoTypes types;

    @Autowired
    private ConsumerController consumerController;

    @Autowired
    private EcsSimulatorController ecsSimulatorController;

    private com.google.gson.Gson gson = new com.google.gson.GsonBuilder().create();

    @LocalServerPort
    int localServerHttpPort;

    static class TestApplicationConfig extends ApplicationConfig {
        @Override
        public String getEcsBaseUrl() {
            return thisProcessUrl();
        }

        @Override
        public String getDmaapBaseUrl() {
            return thisProcessUrl();
        }

        @Override
        public String getSelfUrl() {
            return thisProcessUrl();
        }

        private String thisProcessUrl() {
            final String url = "https://localhost:" + getLocalServerHttpPort();
            return url;
        }
    }

    /**
     * Overrides the BeanFactory.
     */
    @TestConfiguration
    static class TestBeanFactory extends BeanFactory {

        @Override
        @Bean
        public ServletWebServerFactory servletContainer() {
            return new TomcatServletWebServerFactory();
        }

        @Override
        @Bean
        public ApplicationConfig getApplicationConfig() {
            TestApplicationConfig cfg = new TestApplicationConfig();
            return cfg;
        }
    }

    @AfterEach
    void reset() {
        this.consumerController.testResults.reset();
        this.ecsSimulatorController.testResults.reset();
        this.jobs.clear();
        this.types.clear();
    }

    private AsyncRestClient restClient(boolean useTrustValidation) {
        WebClientConfig config = this.applicationConfig.getWebClientConfig();
        HttpProxyConfig httpProxyConfig = ImmutableHttpProxyConfig.builder() //
                .httpProxyHost("") //
                .httpProxyPort(0) //
                .build();
        config = ImmutableWebClientConfig.builder() //
                .keyStoreType(config.keyStoreType()) //
                .keyStorePassword(config.keyStorePassword()) //
                .keyStore(config.keyStore()) //
                .keyPassword(config.keyPassword()) //
                .isTrustStoreUsed(useTrustValidation) //
                .trustStore(config.trustStore()) //
                .trustStorePassword(config.trustStorePassword()) //
                .httpProxyConfig(httpProxyConfig).build();

        AsyncRestClientFactory restClientFactory = new AsyncRestClientFactory(config);
        return restClientFactory.createRestClientNoHttpProxy(baseUrl());
    }

    private AsyncRestClient restClient() {
        return restClient(false);
    }

    private String baseUrl() {
        return "https://localhost:" + this.applicationConfig.getLocalServerHttpPort();
    }

    private ConsumerJobInfo consumerJobInfo() {
        InfoType type = this.types.getAll().iterator().next();
        return consumerJobInfo(type.getId(), "EI_JOB_ID");
    }

    private Object jsonObject() {
        return jsonObject("{}");
    }

    private Object jsonObject(String json) {
        try {
            return JsonParser.parseString(json).getAsJsonObject();
        } catch (Exception e) {
            throw new NullPointerException(e.toString());
        }
    }

    private ConsumerJobInfo consumerJobInfo(String typeId, String infoJobId) {
        try {
            String targetUri = baseUrl() + ConsumerController.CONSUMER_TARGET_URL;
            return new ConsumerJobInfo(typeId, jsonObject(), "owner", targetUri, "");
        } catch (Exception e) {
            return null;
        }
    }

    @Test
    void generateApiDoc() throws IOException {
        String url = "https://localhost:" + applicationConfig.getLocalServerHttpPort() + "/v3/api-docs";
        ResponseEntity<String> resp = restClient().getForEntity(url).block();
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        JSONObject jsonObj = new JSONObject(resp.getBody());
        assertThat(jsonObj.remove("servers")).isNotNull();

        String indented = (jsonObj).toString(4);
        String docDir = "api/";
        Files.createDirectories(Paths.get(docDir));
        try (PrintStream out = new PrintStream(new FileOutputStream(docDir + "api.json"))) {
            out.print(indented);
        }
    }

    @Test
    void testResponseCodes() throws Exception {
        String supervisionUrl = baseUrl() + ProducerCallbacksController.SUPERVISION_URL;
        ResponseEntity<String> resp = restClient().getForEntity(supervisionUrl).block();
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);

        String jobUrl = baseUrl() + ProducerCallbacksController.JOB_URL;
        resp = restClient().deleteForEntity(jobUrl + "/junk").block();
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);

        ProducerJobInfo info = new ProducerJobInfo(null, "id", "typeId", "targetUri", "owner", "lastUpdated");
        String body = gson.toJson(info);
        testErrorCode(restClient().post(jobUrl, body), HttpStatus.NOT_FOUND, "Could not find type");
    }

    @Test
    void testWholeChain() throws Exception {
        final String JOB_ID = "ID";

        // Register producer, Register types
        await().untilAsserted(() -> assertThat(producerRegstrationTask.isRegisteredInEcs()).isTrue());

        // Create a job
        this.ecsSimulatorController.addJob(consumerJobInfo(), JOB_ID, restClient());
        await().untilAsserted(() -> assertThat(this.jobs.size()).isEqualTo(1));

        // Return two messages from DMAAP and verify that these are sent to the owner of
        // the job (consumer)
        DmaapSimulatorController.dmaapResponses.add("DmaapResponse1");
        DmaapSimulatorController.dmaapResponses.add("DmaapResponse2");
        ConsumerController.TestResults consumer = this.consumerController.testResults;
        await().untilAsserted(() -> assertThat(consumer.receivedBodies.size()).isEqualTo(2));
        assertThat(consumer.receivedBodies.get(0)).isEqualTo("DmaapResponse1");

        // Delete the job
        this.ecsSimulatorController.deleteJob(JOB_ID, restClient());
        await().untilAsserted(() -> assertThat(this.jobs.size()).isZero());
    }

    private void testErrorCode(Mono<?> request, HttpStatus expStatus, String responseContains) {
        testErrorCode(request, expStatus, responseContains, true);
    }

    private void testErrorCode(Mono<?> request, HttpStatus expStatus, String responseContains,
            boolean expectApplicationProblemJsonMediaType) {
        StepVerifier.create(request) //
                .expectSubscription() //
                .expectErrorMatches(
                        t -> checkWebClientError(t, expStatus, responseContains, expectApplicationProblemJsonMediaType)) //
                .verify();
    }

    private boolean checkWebClientError(Throwable throwable, HttpStatus expStatus, String responseContains,
            boolean expectApplicationProblemJsonMediaType) {
        assertTrue(throwable instanceof WebClientResponseException);
        WebClientResponseException responseException = (WebClientResponseException) throwable;
        assertThat(responseException.getStatusCode()).isEqualTo(expStatus);
        assertThat(responseException.getResponseBodyAsString()).contains(responseContains);
        if (expectApplicationProblemJsonMediaType) {
            assertThat(responseException.getHeaders().getContentType()).isEqualTo(MediaType.APPLICATION_PROBLEM_JSON);
        }
        return true;
    }

}