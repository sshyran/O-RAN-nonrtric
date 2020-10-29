/*-
 * ========================LICENSE_START=================================
 * O-RAN-SC
 * %%
 * Copyright (C) 2019 Nordix Foundation
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

package org.oransc.enrichment.repository;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.TypeAdapterFactory;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.lang.invoke.MethodHandles;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.ServiceLoader;
import java.util.Vector;

import org.oransc.enrichment.configuration.ApplicationConfig;
import org.oransc.enrichment.exceptions.ServiceException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.FileSystemUtils;

/**
 * Dynamic representation of all existing EI jobs.
 */
public class EiJobs {
    private Map<String, EiJob> allEiJobs = new HashMap<>();

    private MultiMap<EiJob> jobsByType = new MultiMap<>();
    private MultiMap<EiJob> jobsByOwner = new MultiMap<>();
    private final Gson gson;

    private final ApplicationConfig config;
    private final Logger logger = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());

    public EiJobs(ApplicationConfig config) {
        this.config = config;
        GsonBuilder gsonBuilder = new GsonBuilder();
        ServiceLoader.load(TypeAdapterFactory.class).forEach(gsonBuilder::registerTypeAdapterFactory);
        this.gson = gsonBuilder.create();
    }

    public synchronized void restoreJobsFromDatabase() throws IOException {
        File dbDir = new File(getDatabaseDirectory());
        for (File file : dbDir.listFiles()) {
            String json = Files.readString(file.toPath());
            EiJob job = gson.fromJson(json, EiJob.class);
            this.put(job, false);
        }
    }

    public synchronized void put(EiJob job) {
        this.put(job, true);
    }

    public synchronized Collection<EiJob> getJobs() {
        return new Vector<>(allEiJobs.values());
    }

    public synchronized EiJob getJob(String id) throws ServiceException {
        EiJob ric = allEiJobs.get(id);
        if (ric == null) {
            throw new ServiceException("Could not find EI job: " + id);
        }
        return ric;
    }

    public synchronized Collection<EiJob> getJobsForType(String typeId) {
        return jobsByType.get(typeId);
    }

    public synchronized Collection<EiJob> getJobsForType(EiType type) {
        return jobsByType.get(type.getId());
    }

    public synchronized Collection<EiJob> getJobsForOwner(String owner) {
        return jobsByOwner.get(owner);
    }

    public synchronized EiJob get(String id) {
        return allEiJobs.get(id);
    }

    public synchronized EiJob remove(String id) {
        EiJob job = allEiJobs.get(id);
        if (job != null) {
            remove(job);
        }
        return job;
    }

    public synchronized void remove(EiJob job) {
        this.allEiJobs.remove(job.id());
        jobsByType.remove(job.typeId(), job.id());
        jobsByOwner.remove(job.owner(), job.id());

        try {
            Files.delete(getPath(job));
        } catch (IOException e) {
            logger.warn("Could not remove file: {}", e.getMessage());
        }

    }

    public synchronized int size() {
        return allEiJobs.size();
    }

    public synchronized void clear() {
        this.allEiJobs.clear();
        this.jobsByType.clear();
        jobsByOwner.clear();
        try {
            FileSystemUtils.deleteRecursively(Path.of(getDatabaseDirectory()));
        } catch (IOException e) {
            logger.warn("Could not delete database : {}", e.getMessage());
        }
    }

    private void put(EiJob job, boolean storePersistently) {
        allEiJobs.put(job.id(), job);
        jobsByType.put(job.typeId(), job.id(), job);
        jobsByOwner.put(job.owner(), job.id(), job);
        if (storePersistently) {
            storeJobInFile(job);
        }
    }

    private void storeJobInFile(EiJob job) {
        try {
            Files.createDirectories(Paths.get(getDatabaseDirectory()));
            try (PrintStream out = new PrintStream(new FileOutputStream(getFile(job)))) {
                out.print(gson.toJson(job));
            }
        } catch (Exception e) {
            logger.warn("Could not save job: {} {}", job.id(), e.getMessage());
        }
    }

    private File getFile(EiJob job) {
        return getPath(job).toFile();
    }

    private Path getPath(EiJob job) {
        return Path.of(getDatabaseDirectory(), job.id());
    }

    private String getDatabaseDirectory() {
        return config.getVardataDirectory() + "/database";
    }

}
