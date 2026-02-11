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

import ballerina/regex;
import ballerina/io;
import ballerina/os;

# Use Anthropic LLM to find root client class using weighted scoring
#
# + classes - All classes from SDK
# + maxCandidates - Maximum number of candidates to consider
# + return - Sorted candidates with LLM scores
public function identifyClientClassWithLLM(ClassInfo[] classes, int maxCandidates) 
        returns [ClassInfo, LLMClientScore][]|AnalyzerError {

    if !isAnthropicConfigured() {
        return error AnalyzerError("Anthropic LLM not configured: LLM-only candidate scoring required");
    }

    // Filter potential candidates using conservative structural rules
    ClassInfo[] potential = [];
    foreach ClassInfo cls in classes {
        if shouldConsiderAsClientCandidate(cls) {
            potential.push(cls);
        }
    }
    if potential.length() > 0 {
        int sampleCount = potential.length() > 5 ? 5 : potential.length();
        foreach int i in 0 ..< sampleCount {
        }
    }

    if potential.length() == 0 {
        // Structural filtering produced no candidates (may be a smaller SDK).
        // Fall back to a looser selection.
        ClassInfo[] fallback = [];
        foreach ClassInfo cls in classes {
            if !cls.className.includes("$") && !cls.isEnum && !cls.isAbstract && cls.methods.length() > 0 {
                fallback.push(cls);
            }
        }
        if fallback.length() == 0 {
            return error AnalyzerError("No potential client candidates after structural filtering");
        }
        // Sort fallback by method count descending and take a reasonable sample
        ClassInfo[] sortedFallback = from var c in fallback
                                      order by c.methods.length() descending
                                      select c;
        int sampleCount = sortedFallback.length() > 10 ? 10 : sortedFallback.length();
        potential = sortedFallback.slice(0, sampleCount);
    }

    [ClassInfo, LLMClientScore][] scored = [];

    // Score each potential candidate using the LLM exclusively. Propagate or log failures per-class.
    foreach ClassInfo cls in potential {
        LLMClientScore|error score = calculateLLMClientScore(cls, classes);
        if score is LLMClientScore {
            scored.push([cls, score]);
        } else {
            error e = <error> score;
            io:println(string `LLM scoring failed for ${cls.className}: ${e.message()}`);
        }
    }

    if scored.length() == 0 {
        return error AnalyzerError("LLM failed to score any client candidates");
    }

    // Sort by LLM total score descending
    [ClassInfo, LLMClientScore][] sorted = from var [cls, score] in scored
                                           order by score.totalScore descending
                                           select [cls, score];

    int finalCount = sorted.length() < maxCandidates ? sorted.length() : maxCandidates;
    return sorted.slice(0, finalCount);
}

# Detect class initialization pattern using LLM
#
# + rootClient - The identified root client class
# + return - Detected initialization pattern
public function detectClientInitPatternWithLLM(ClassInfo rootClient) returns ClientInitPattern|error {
    if !isAnthropicConfigured() {
        return error("Anthropic LLM not configured: cannot detect init pattern using LLM");
    }

    // Use LLM to detect pattern and propagate any errors
    ClientInitPattern|error pattern = detectInitPatternWithLLM(rootClient);
    if pattern is ClientInitPattern {
        return pattern;
    }
    return pattern; // propagate error
}

# Extract all public methods from root client class
#
# + rootClient - The root client class
# + return - All public methods with metadata
public function extractPublicMethods(ClassInfo rootClient) returns MethodInfo[] {
    MethodInfo[] publicMethods = [];
    
    foreach MethodInfo method in rootClient.methods {
        // Skip constructor methods and private methods
        if !method.name.startsWith("<") && method.name != "toString" && 
           method.name != "hashCode" && method.name != "equals" {
            publicMethods.push(method);
        }
    }
    
    return publicMethods;
}

# Use LLM to rank methods by usage frequency  
#
# + methods - All public methods from root client
# + return - Methods ranked by usage frequency
public function rankMethodsByUsageWithLLM(MethodInfo[] methods) returns MethodInfo[]|error {
    
    if methods.length() <= 1 {
        return methods;
    }
    
    if !isAnthropicConfigured() {
        return error("Anthropic LLM not configured: cannot rank methods using LLM");
    }

    // Use LLM to rank methods by usage frequency
    return rankMethodsUsingLLM(methods);
}

# Extract request/response parameters and corresponding fields with types
#
# + methods - Methods to analyze for parameters
# + allClasses - All classes for type lookup
# + return - Enhanced methods with parameter field information
public function extractParameterFieldTypes(MethodInfo[] methods, ClassInfo[] allClasses) 
        returns MethodInfo[] {
    
    // Deduplicate overloads preferring variants that resolve to a Request class
    map<MethodInfo> chosen = {};
    foreach MethodInfo method in methods {
        boolean hasRequestParam = false;
        foreach ParameterInfo p in method.parameters {
            ClassInfo? resolved = resolveRequestClassFromParameter(p, allClasses, method.name);
            if resolved is ClassInfo {
                hasRequestParam = true;
                break;
            }
        }

        if !chosen.hasKey(method.name) {
            chosen[method.name] = method;
        } else {
            MethodInfo? existing = chosen[method.name];
            if existing is MethodInfo {
                boolean existingHasRequest = false;
                foreach ParameterInfo p in existing.parameters {
                    ClassInfo? r = resolveRequestClassFromParameter(p, allClasses, existing.name);
                    if r is ClassInfo {
                        existingHasRequest = true;
                        break;
                    }
                }
                if !existingHasRequest && hasRequestParam {
                    chosen[method.name] = method;
                } else if existingHasRequest && hasRequestParam {
                    // Both overloads resolve to a request type. Prefer the overload
                    // whose parameter type directly references a Request class (i.e., typeName contains "Request")
                    boolean existingDirect = false;
                    boolean currentDirect = false;
                    foreach ParameterInfo p in existing.parameters {
                        if p.typeName != "" && (p.typeName.endsWith("Request") || p.typeName.indexOf("Request") != -1) {
                            existingDirect = true;
                            break;
                        }
                    }
                    foreach ParameterInfo p in method.parameters {
                        if p.typeName != "" && (p.typeName.endsWith("Request") || p.typeName.indexOf("Request") != -1) {
                            currentDirect = true;
                            break;
                        }
                    }
                    if currentDirect && !existingDirect {
                        chosen[method.name] = method;
                    }
                }
            }
        }
    }

    // Reconstruct ordered list preserving first-seen order of original methods
    MethodInfo[] enhancedMethodsOrdered = [];
    map<boolean> added = {};
    foreach MethodInfo m in methods {
        if !added.hasKey(m.name) {
            MethodInfo? selOpt = chosen[m.name];
            if selOpt is MethodInfo {
                MethodInfo sel = selOpt;
                MethodInfo enhancedMethod = {
                    name: sel.name,
                    returnType: sel.returnType,
                    parameters: extractEnhancedParameters(sel.parameters, allClasses, sel.name),
                    isStatic: sel.isStatic,
                    isFinal: sel.isFinal,
                    isAbstract: sel.isAbstract,
                    isDeprecated: sel.isDeprecated,
                    annotations: sel.annotations,
                    exceptions: sel.exceptions,
                    typeParameters: sel.typeParameters,
                    javadoc: sel.javadoc,
                    signature: sel.signature
                };
                enhancedMethodsOrdered.push(enhancedMethod);
                added[m.name] = true;
            }
        }
    }

    return enhancedMethodsOrdered;
}

# Generate structured metadata with all information
#
# + rootClient - The identified root client
# + initPattern - The initialization pattern
# + rankedMethods - Methods ranked by usage
# + allClasses - All classes for context
# + return - Complete structured metadata
public function generateStructuredMetadata(
    ClassInfo rootClient, 
    ClientInitPattern initPattern,
    MethodInfo[] rankedMethods,
    ClassInfo[] allClasses
) returns StructuredSDKMetadata {
    
    // Populate request fields for all parameters in the selected methods
    MethodInfo[] methodsWithRequestFields = [];
    foreach MethodInfo method in rankedMethods {
        MethodInfo updatedMethod = method;
        
        // Update each parameter with request fields if it's a request object
        ParameterInfo[] updatedParams = [];
        foreach ParameterInfo param in method.parameters {
            ParameterInfo updatedParam = param;

            // Try to resolve the request class via generics, builders, or method-name heuristics
            ClassInfo? requestClass = resolveRequestClassFromParameter(param, allClasses, method.name);
            if requestClass is ClassInfo {
                // Replace the parameter's exposed type with the resolved Request class
                updatedParam.typeName = requestClass.className;
                updatedParam.requestFields = extractRequestFields(requestClass);

                // If the parameter name is generic (e.g., 'consumer'), replace it with a sensible name
                if param.name.toLowerAscii().indexOf("consumer") != -1 || param.name.startsWith("arg") {
                    string simple = requestClass.simpleName;
                    if simple.length() > 0 {
                        string newName = simple.substring(0,1).toLowerAscii() + simple.substring(1);
                        updatedParam.name = newName;
                    }
                }
            }

            updatedParams.push(updatedParam);
        }
        
        updatedMethod.parameters = updatedParams;
        methodsWithRequestFields.push(updatedMethod);
    }
    
    return {
        sdkInfo: {
            name: extractSdkNameFromClass(rootClient),
            version: "unknown",
            rootClientClass: rootClient.className
        },
        clientInit: initPattern,
        rootClient: {
            className: rootClient.className,
            packageName: rootClient.packageName,
            simpleName: rootClient.simpleName,
            isInterface: rootClient.isInterface,
            constructors: rootClient.constructors,
            methods: methodsWithRequestFields
        },
        supportingClasses: extractSupportingClasses(rankedMethods, allClasses),
        analysis: {
            totalClassesFound: allClasses.length(),
            totalMethodsInClient: rootClient.methods.length(),
            selectedMethods: methodsWithRequestFields.length(),
            analysisApproach: "JavaParser with LLM enhancement"
        }
    };
}

# Extract SDK name from class information
#
# + rootClient - Root client class
# + return - Inferred SDK name
function extractSdkNameFromClass(ClassInfo rootClient) returns string {
    string packageName = rootClient.packageName;
    if packageName == "" {
        return "Java SDK";
    }

    string[] parts = regex:split(packageName, "\\.");
    // Find last non-empty segment
    string last = "";
    foreach string p in parts.reverse() {
        if p.trim().length() > 0 {
            last = p;
            break;
        }
    }

    if last.length() == 0 {
        return "Java SDK";
    }

    // Title-case the last segment
    string namePart = last;
    if namePart.length() > 1 {
        string first = namePart.substring(0, 1).toUpperAscii();
        string rest = namePart.substring(1);
        namePart = first + rest;
    } else {
        namePart = namePart.toUpperAscii();
    }

    return namePart + " SDK";
}

# Extract supporting classes used by the selected methods
#
# + methods - Selected methods 
# + allClasses - All available classes
# + return - Supporting classes information
function extractSupportingClasses(MethodInfo[] methods, ClassInfo[] allClasses) 
        returns SupportingClassInfo[] {
    
    SupportingClassInfo[] supportingClasses = [];
    map<boolean> addedClasses = {};
    
    foreach MethodInfo method in methods {
        // Check return type
        string returnType = method.returnType;
        if returnType != "void" && !isSimpleType(returnType) {
            ClassInfo? cls = findClassByName(returnType, allClasses);
            if cls is ClassInfo && !addedClasses.hasKey(cls.className) {
                supportingClasses.push({
                    className: cls.className,
                    simpleName: cls.simpleName,
                    packageName: cls.packageName,
                    purpose: "Return type"
                });
                addedClasses[cls.className] = true;
            }
        }
        
        // Check parameter types
        foreach ParameterInfo param in method.parameters {
            if !isSimpleType(param.typeName) {
                ClassInfo? cls = findClassByName(param.typeName, allClasses);
                if cls is ClassInfo && !addedClasses.hasKey(cls.className) {
                    supportingClasses.push({
                        className: cls.className,
                        simpleName: cls.simpleName,
                        packageName: cls.packageName,
                        purpose: "Parameter type"
                    });
                    addedClasses[cls.className] = true;
                }
            }
        }
    }
    
    return supportingClasses;
}

# Check if class should be considered as client candidate
#
# + cls - Class to check
# + return - True if should be considered
function shouldConsiderAsClientCandidate(ClassInfo cls) returns boolean {
    // Skip inner classes and enums
    if cls.className.includes("$") || cls.isEnum {
        return false;
    }

    // Skip abstract classes (but allow interfaces)
    if cls.isAbstract && !cls.isInterface {
        return false;
    }

    // Must have reasonable number of methods for non-named candidates
    if cls.methods.length() < 3 {
        return false;
    }

    // Interface with reasonable method count
    if cls.isInterface && cls.methods.length() >= 5 {
        return true;
    }

    return false;
}

# Check if Anthropic LLM is properly configured
#
# + return - True if configured
function isAnthropicConfigured() returns boolean {
    // Check environment variable first
    string? apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is string {
        if apiKey.trim().length() > 0 {
            return true;
        }
    }

    // If getAnthropicConfig returns a config, then Anthropic is configured.
    AnthropicConfiguration|error conf = getAnthropicConfig();
    if conf is AnthropicConfiguration {
        return true;
    }

    return false;
}

function detectInitPatternWithLLM(ClassInfo rootClient) returns ClientInitPattern|error {
    // Use LLM for comprehensive pattern analysis if available
    if isAnthropicConfigured() {
        string systemPrompt = getInitPatternSystemPrompt();
        string constructorDetails = formatConstructorDetails(rootClient.constructors);
        string staticMethodInfo = formatStaticMethods(rootClient.methods);
        string userPrompt = getInitPatternUserPrompt(
            rootClient.simpleName,
            rootClient.packageName,
            constructorDetails,
            staticMethodInfo,
            rootClient.methods.length(),
            rootClient.isInterface
        );

        json|error response = callAnthropicAPI(check getAnthropicConfig(), systemPrompt, userPrompt);
        
        if response is json {
            string responseText = extractResponseText(response);
            
            // Parse pattern and reason from response
            string[] lines = regex:split(responseText, "\n");
            string patternName = "";
            string reason = "";
            
            foreach string line in lines {
                string trimmed = line.trim();
                if trimmed.startsWith("PATTERN:") {
                    patternName = trimmed.substring(8).trim().toLowerAscii();
                } else if trimmed.startsWith("REASON:") {
                    reason = trimmed.substring(7).trim();
                }
            }
            
            // Validate pattern name
            if patternName == "constructor" || patternName == "builder" || 
               patternName == "static-factory" || patternName == "instance-factory" || 
               patternName == "no-constructor" {
                string initCode = generateInitializationCode(patternName, rootClient);
                ClientInitPattern llmPattern = {
                    patternName: patternName,
                    initializationCode: initCode,
                    explanation: reason == "" ? "Pattern detected by LLM analysis" : reason,
                    detectedBy: "llm"
                };
                return llmPattern;
            }
        } else {
            error e = <error>response;
            io:println(string `LLM init pattern detection failed: ${e.message()}`);
        }
    }
    
    // Fallback to heuristic pattern if LLM unavailable or fails
    ClientInitPattern heuristicPattern = detectClientInitPatternHeuristically(rootClient);
    return heuristicPattern;
}



# Use LLM to intelligently rank SDK methods by usage frequency and examples
#
# + methods - Methods to rank
# + return - Ranked methods or error
function rankMethodsUsingLLM(MethodInfo[] methods) returns MethodInfo[]|error {
    string systemPrompt = getMethodRankingSystemPrompt();
    string methodsList = formatMethodsListForRanking(methods);
    string userPrompt = getMethodRankingUserPrompt(methods.length(), methodsList);

    json|error response = callAnthropicAPI(check getAnthropicConfig(), systemPrompt, userPrompt);

    if response is json {
        string responseText = extractResponseText(response);
        if responseText == "" {
            responseText = response.toString();
        }

        // Parse the comma-separated method names
        string[] rankedNames = regex:split(responseText, ",");
        string[] trimmedNames = rankedNames.map(n => n.trim()).filter(n => n.length() > 0);

        if trimmedNames.length() > 0 {
            // Create a map for quick lookup
            map<MethodInfo> methodMap = {};
            foreach MethodInfo method in methods {
                methodMap[method.name] = method;
            }

            // Build result maintaining LLM's priority order
            MethodInfo[] reordered = [];
            foreach string methodName in trimmedNames {
                if methodMap.hasKey(methodName) {
                    MethodInfo? method = methodMap[methodName];
                    if method is MethodInfo {
                        reordered.push(method);
                    }
                }
            }

            return reordered;
        }
    }

    return error("Failed to rank methods using LLM");
}

# Heuristic-based client initialization pattern detection
#
# + clientClass - The client class to analyze
# + return - Detected initialization pattern
function detectClientInitPatternHeuristically(ClassInfo clientClass) returns ClientInitPattern {
    // Prefer detecting builder/static-factory patterns via presence of static methods
    foreach MethodInfo m in clientClass.methods {
        if m.isStatic {
            string nameLower = m.name.toLowerAscii();
            // static builder() method (common in AWS SDK v2)
            if nameLower == "builder" {
                return {
                    patternName: "builder",
                    initializationCode: clientClass.simpleName + " client = " + clientClass.simpleName + ".builder().build();",
                    explanation: "Detected static builder() method",
                    detectedBy: "heuristic"
                };
            }
            // static create() or createX factory method
            if nameLower == "create" || nameLower.startsWith("create") {
                return {
                    patternName: "static-factory",
                    initializationCode: clientClass.simpleName + " client = " + clientClass.simpleName + ".create();",
                    explanation: "Detected static create() factory method",
                    detectedBy: "heuristic"
                };
            }
        }
    }

    // Fall back to constructors if present
    if clientClass.constructors.length() == 0 {
        return {
            patternName: "no-constructor",
            initializationCode: "// No public constructors found",
            explanation: "The class does not expose public constructors",
            detectedBy: "heuristic"
        };
    }

    string[] patterns = [];
    string[] codePatterns = [];
    foreach ConstructorInfo constructor in clientClass.constructors {
        if constructor.parameters.length() == 0 {
            patterns.push("Default constructor");
            codePatterns.push(string `new ${clientClass.simpleName}()`);
        } else {
            string[] paramTypes = constructor.parameters.map(p => p.typeName);
            patterns.push(string `Constructor(${string:'join(", ", ...paramTypes)})`);
            string[] paramNames = constructor.parameters.map(p => p.name);
            codePatterns.push(string `new ${clientClass.simpleName}(${string:'join(", ", ...paramNames)})`);
        }
    }

    return {
        patternName: "constructor",
        initializationCode: string:'join(" // OR\n", ...codePatterns),
        explanation: string:'join(" | ", ...patterns),
        detectedBy: "heuristic"
    };
}