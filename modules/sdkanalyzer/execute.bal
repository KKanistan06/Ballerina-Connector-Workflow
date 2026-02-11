// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;
import ballerina/log;
import ballerina/regex;
import ballerina/time;

# Execute SDK Analyzer from command-line arguments.
#
# + args - Command-line arguments [sdk-ref, output-dir, options...]
# + return - Error if execution fails
public function executeSdkAnalyzer(string... args) returns error? {
    string[] actualArgs = args;
    if args.length() > 0 && args[0] == "analyze" {
        actualArgs = args.slice(1);
    }

    if actualArgs.length() < 2 {
        printUsage();
        return;
    }

    string sdkRef = actualArgs[0];
    string outputDir = actualArgs[1];

    AnalyzerConfig config = parseCommandLineArgs(actualArgs.slice(2));

    if !config.quietMode {
        log:printInfo("Starting SDK analysis", sdkRef = sdkRef, outputDir = outputDir);
    }

    return analyzeSDK(sdkRef, outputDir, config);
}

# Analyze Java SDK and generate the analyzer outputs.
#
# + sdkRef - Path to the JAR file or Maven coordinate (mvn:group:artifact:version)
# + outputDir - Output directory for generated files
# + config - Analyzer configuration
# + return - Error if analysis fails
function analyzeSDK(string sdkRef, string outputDir, AnalyzerConfig config) returns error? {
    if !config.quietMode {
        io:println(string `Analyzing SDK: ${sdkRef}`);
    }

    time:Utc startTime = time:utcNow();

    AnalysisResult|AnalyzerError result = analyzeJavaSDK(sdkRef, outputDir, config);

    time:Utc endTime = time:utcNow();
    time:Seconds seconds = time:utcDiffSeconds(endTime, startTime);
    decimal duration = <decimal> seconds;

    if result is AnalysisResult {
        if !config.quietMode {
            io:println(string `Analysis completed in ${duration} seconds`);
            io:println(string `Metadata file: ${result.metadataPath}`);
        }
        return;
    }

    if !config.quietMode {
        log:printError("SDK analysis failed", 'error = result);
    }
    io:println(string `Analysis failed: ${result.message()}`);
    return result;
}

# Parse command-line arguments into configuration.
#
# + args - Command-line arguments
# + return - Parsed configuration
function parseCommandLineArgs(string[] args) returns AnalyzerConfig {
    AnalyzerConfig config = {};

    foreach string arg in args {
        match arg {
            "yes" | "--yes" | "-y" => {
                config.autoYes = true;
            }
            "quiet" | "--quiet" | "-q" => {
                config.quietMode = true;
            }
            "include-deprecated" | "--include-deprecated" => {
                config.includeDeprecated = true;
            }
            "include-internal" | "--include-internal" => {
                config.filterInternal = false;
            }
            "include-non-public" | "--include-non-public" => {
                config.includeNonPublic = true;
            }
            _ => {
                // Handle key=value pairs
                if arg.includes("=") {
                    string[] parts = regex:split(arg, "=");
                    if parts.length() == 2 {
                        string key = parts[0].trim();
                        string value = parts[1].trim();

                        match key {
                            "exclude-packages" | "--exclude-packages" => {
                                if value.length() > 0 {
                                    config.excludePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "include-packages" | "--include-packages" => {
                                if value.length() > 0 {
                                    config.includePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "max-depth" | "--max-depth" => {
                                int|error depth = int:fromString(value);
                                if depth is int {
                                    config.maxDependencyDepth = depth;
                                }
                            }
                            _ => {
                                // Ignore unknown key=value pairs for forward compatibility.
                            }
                        }
                    }
                }
            }
        }
    }

    return config;
}

# Create separator line.
#
# + char - Character to repeat
# + length - Length of separator
# + return - Separator string
function createSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i = i + 1;
    }
    return string:'join("", ...chars);
}

# Print usage information.
function printUsage() {
    io:println();
    io:println("SDK Analyzer - Extract metadata/IR from Java SDK JAR files (and Maven artifacts)");
    io:println();
    io:println("USAGE:");
    io:println("  bal run -- analyze <sdk-ref> <output-dir> [options]");
    io:println();
    io:println("ARGUMENTS:");
    io:println("  sdk-ref               Path to a Java SDK JAR file, OR mvn:groupId:artifactId:version");
    io:println("  output-dir            Directory to save generated files");
    io:println();
    io:println("OPTIONS:");
    io:println("  --yes, -y             Auto-confirm all prompts");
    io:println("  --quiet, -q           Minimal logging output");
    io:println("  --include-deprecated  Include deprecated methods/classes");
    io:println("  --include-internal    Include internal packages (sun.*, com.sun.* etc.)");
    io:println("  --include-non-public  Include protected/private members");
    io:println("  --exclude-packages=   Comma-separated packages to exclude");
    io:println("  --include-packages=   Comma-separated packages to include (only these)");
    io:println("  --max-depth=N         Maximum dependency resolution depth (default: 3)");
    io:println();
    io:println("EXAMPLES:");
    io:println("  bal run -- analyze ./aws-sdk-s3.jar ./output");
    io:println("  bal run -- analyze mvn:software.amazon.awssdk:s3:2.21.0 ./output --yes");
    io:println("  bal run -- analyze ./sdk.jar ./output --yes --quiet");
    io:println("  bal run -- analyze ./sdk.jar ./output --exclude-packages=internal,impl");
    io:println("  bal run -- analyze ./sdk.jar ./output --include-packages=com.example.api");
    io:println();
    io:println("OUTPUT (minimum):");
    io:println("  - sdk-metadata.json   Complete SDK metadata/IR for downstream generation");
    io:println("  - analysis-report.txt Analysis summary report");
    io:println();
}
