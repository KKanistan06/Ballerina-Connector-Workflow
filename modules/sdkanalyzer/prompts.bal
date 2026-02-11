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

// All LLM prompt templates for SDK analysis

# System prompt for client class scoring
#
# + return - System prompt for evaluating client classes
public function getClientScoringSystemPrompt() returns string {
    return "You are an expert Java SDK analyzer. Your task is to evaluate if a Java class is likely " +
        "to be the root/main client class for an SDK. Analyze class characteristics and provide a score from 0-100. " +
        "Use your knowledge of SDK design patterns and conventions to identify the primary client interface that developers would use. " +
        "Return your response in format: SCORE:XX|REASON:your explanation";
}

# User prompt for client class scoring
#
# + classInfo - Formatted class information
# + return - User prompt for evaluating a specific class
public function getClientScoringUserPrompt(string classInfo) returns string {
    return string `
Evaluate this Java class as a potential root SDK client class:

${classInfo}

Analyze the class structure and provide a numeric score 0-100 based on your knowledge of:
- SDK design patterns and naming conventions
- Method diversity and comprehensiveness
- Typical usage patterns in similar SDKs
- Whether this represents the main entry point for SDK operations

Consider what makes a class the primary client interface that developers would interact with.

Format: SCORE:XX|REASON:your brief explanation`;
}

# System prompt for initialization pattern detection
#
# + return - System prompt for detecting instantiation patterns
public function getInitPatternSystemPrompt() returns string {
    return "You are a Java SDK instantiation pattern analyzer. Analyze the class structure and determine the RECOMMENDED client instantiation pattern. " +
        "Use your knowledge of Java SDK design patterns to identify how developers should create instances of this client. " +
        "Return your response in this EXACT format:\n" +
        "PATTERN: <pattern-name>\n" +
        "REASON: <1-3 line explanation>\n" +
        "Pattern names: constructor, builder, static-factory, instance-factory, or no-constructor";
}

# User prompt for initialization pattern detection
#
# + simpleName - Simple class name
# + packageName - Package name
# + constructorDetails - Formatted constructor information
# + staticMethodInfo - Formatted static method information
# + totalMethods - Total method count
# + isInterface - Whether class is an interface
# + return - User prompt for pattern detection
public function getInitPatternUserPrompt(
    string simpleName,
    string packageName,
    string constructorDetails,
    string staticMethodInfo,
    int totalMethods,
    boolean isInterface
) returns string {
    return "Analyze this Java SDK client class and determine the RECOMMENDED instantiation pattern:\n\n" +
        "Class: " + simpleName + "\n" +
        "Package: " + packageName + "\n\n" +
        "Constructors:\n" + constructorDetails + "\n" +
        "Static Methods: " + staticMethodInfo + "\n\n" +
        "Total Methods: " + totalMethods.toString() + "\n" +
        "Is Interface: " + isInterface.toString() + "\n\n" +
        "Based on your knowledge of SDK design patterns and the information above:\n" +
        "1. Determine the RECOMMENDED instantiation pattern\n" +
        "2. Provide a brief reason (1-3 lines) explaining why this pattern is appropriate\n\n" +
        "Consider common SDK patterns and how developers typically instantiate similar clients.\n\n" +
        "Respond in this EXACT format:\n" +
        "PATTERN: <pattern-name>\n" +
        "REASON: <explanation>";
}

# System prompt for method ranking
#
# + return - System prompt for ranking SDK methods
public function getMethodRankingSystemPrompt() returns string {
    return "You are an expert Java SDK usage analyst. Analyze the provided method list and identify the MOST IMPORTANT methods that developers would commonly use. " +
        "Use your knowledge of SDK usage patterns to select methods that represent core functionality and common operations. " +
        "Focus on methods that perform actual SDK operations, NOT utility/meta methods for client configuration or instantiation. " +
        "Return ONLY a comma-separated list of the important method NAMES. The count can vary (typically 20-40) based on SDK complexity. " +
        "Exclude redundant overloads, rarely-used methods, and client meta methods. No commentary, just the comma-separated names.";
}

# User prompt for method ranking
#
# + methodCount - Total number of methods
# + methodsList - Formatted list of methods
# + return - User prompt for method ranking
public function getMethodRankingUserPrompt(int methodCount, string methodsList) returns string {
    return "Analyze these " + methodCount.toString() + " SDK methods and select the MOST IMPORTANT ones that developers commonly use.\n\n" +
        "Use your knowledge of SDK patterns to identify:\n" +
        "- Core operations that represent the main functionality of the SDK\n" +
        "- Commonly-used methods in typical SDK workflows\n" +
        "- Methods that perform actual SDK operations (not client setup/configuration)\n\n" +
        "EXCLUDE:\n" +
        "- Client instantiation and configuration methods\n" +
        "- Utility methods for client management\n" +
        "- Rarely-used or redundant method overloads\n" +
        "- Internal/framework methods\n\n" +
        "Return a comma-separated list of the important method NAMES (no numbers, just names).\n\n" +
        "Methods:\n" + methodsList + "\n" +
        "Important method names (comma-separated):";
}
