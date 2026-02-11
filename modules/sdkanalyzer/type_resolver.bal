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

// Request/Response type resolution utilities

import ballerina/regex;

# Resolve an underlying Request/Response ClassInfo from a parameter
#
# + param - Parameter to analyze
# + allClasses - All classes for type lookup
# + methodName - Method name for heuristics
# + return - Resolved class or null
public function resolveRequestClassFromParameter(ParameterInfo param, ClassInfo[] allClasses, string methodName)
    returns ClassInfo? {
    string[] candidates = [];

    // Add the parameter's declared type first
    if param.typeName != "" {
        candidates.push(param.typeName);
    }

    // For each candidate type name, generate normalized forms to try to match
    // known Request/Response types.
    foreach string raw in candidates {
        string[] normCandidates = normalizeCandidateTypeNames(raw);
        foreach string cand in normCandidates {
            // Prefer explicit Request/Response names, but allow matching by simple name
            if cand.endsWith("Request") || cand.endsWith("Response") {
                ClassInfo? found = findClassByName(cand, allClasses);
                if found is ClassInfo {
                    return found;
                }
            }
        }
    }

    // If any candidate directly matches a class, return it (non-Request too)
    foreach string raw in candidates {
        ClassInfo? found = findClassByName(raw, allClasses);
        if found is ClassInfo {
            return found;
        }
    }

    // If no generics were present or matched, and the parameter type is a
    // common wrapper, try to derive a request type
    // name from the method name (e.g., createBucket -> CreateBucketRequest).
    if candidates.length() == 1 {
        string rawOnly = candidates[0];
        string lower = rawOnly.toLowerAscii();
        if lower.includes("consumer") || lower.includes("function") || lower.includes("supplier") {
            // Generate PascalCase method name
            string pascal = methodName.substring(0,1).toUpperAscii() + methodName.substring(1);
            string guess = pascal + "Request";
            ClassInfo? guessCls = findClassByName(guess, allClasses);
            if guessCls is ClassInfo {
                return guessCls;
            }
        }
    }

    return null;
}

# Normalize a type name to candidates for lookup
#
# + raw - Raw type name
# + return - Array of normalized candidate names
public function normalizeCandidateTypeNames(string raw) returns string[] {
    string[] out = [];
    if raw == "" {
        return out;
    }

    // If generic-like (with <>), strip generics content
    if raw.includes("<") && raw.includes(">") {
        // e.g., java.util.function.Consumer<com.pkg.XRequest.Builder>
        string[] parts = regex:split(raw, "<|>");
        if parts.length() >= 2 {
            string inner = parts[1];
            out.push(inner);
        }
        string withoutGenerics = regex:replace(raw, "<.*>", "");
        out.push(withoutGenerics);
    }

    // Add original raw
    out.push(raw);

    // If ends with ".Builder" or "Builder", strip it
    if raw.endsWith(".Builder") {
        string removed = regex:replace(raw, "\\.Builder$", "");
        out.push(removed);
    } else if raw.endsWith("Builder") {
        if raw.includes("$") {
            string maybe = regex:replace(raw, "\\$Builder$", "");
            if maybe != raw {
                out.push(maybe);
            }
        }
        string stripped = regex:replace(raw, "Builder$", "");
        out.push(stripped);
    }

    // If contains '$' (inner class), also try replacing with '.' and stripping suffixes
    if raw.includes("$") {
        string dotForm = regex:replace(raw, "\\$", ".");
        out.push(dotForm);
        if dotForm.endsWith(".Builder") {
            string removedDotBuilder = regex:replace(dotForm, "\\.Builder$", "");
            out.push(removedDotBuilder);
        }
    }

    // Also add simple name candidate (strip package)
    string[] parts = regex:split(raw, "\\.");
    if parts.length() > 0 {
        string simple = parts[parts.length() - 1];
        out.push(simple);
        if simple.endsWith("Builder") {
            string simpleStripped = regex:replace(simple, "Builder$", "");
            out.push(simpleStripped);
        }
    }

    // Remove duplicates while preserving order
    string[] uniq = [];
    foreach string s in out {
        if s == "" {
            continue;
        }
        boolean present = uniq.some(function(string x) returns boolean { return x == s; });
        if !present {
            uniq.push(s);
        }
    }

    return uniq;
}

# Find class by name in the class list
#
# + className - Class name to find
# + allClasses - All available classes
# + return - Found class or null
public function findClassByName(string className, ClassInfo[] allClasses) returns ClassInfo? {
    foreach ClassInfo cls in allClasses {
        if cls.className == className || cls.simpleName == className {
            return cls;
        }
    }
    return null;
}

# Extract request fields from a Request class
#
# + requestClass - The Request class to analyze
# + return - List of request field information
public function extractRequestFields(ClassInfo requestClass) returns RequestFieldInfo[] {
    RequestFieldInfo[] requestFields = [];

    foreach MethodInfo method in requestClass.methods {
        if method.parameters.length() == 0 && method.returnType != "void" &&
           method.name != "toString" && method.name != "hashCode" &&
           method.name != "equals" && method.name != "getClass" {

            string fieldName = method.name;
            if fieldName.length() > 0 {
                string firstChar = fieldName.substring(0, 1).toLowerAscii();
                fieldName = firstChar + fieldName.substring(1);
            }

            RequestFieldInfo fieldInfo = {
                name: fieldName,
                typeName: method.returnType,
                fullType: method.returnType,
                isRequired: false
            };

            requestFields.push(fieldInfo);
        }
    }

    return requestFields;
}

# Enhance parameters with resolved request class information
#
# + parameters - Original parameters
# + allClasses - All classes for type resolution
# + methodName - Method name for heuristics
# + return - Enhanced parameters with field information
public function extractEnhancedParameters(ParameterInfo[] parameters, ClassInfo[] allClasses, string methodName)
    returns ParameterInfo[] {
    ParameterInfo[] enhancedParams = [];
    foreach ParameterInfo param in parameters {
        ParameterInfo enhancedParam = param;
        ClassInfo? resolved = resolveRequestClassFromParameter(param, allClasses, methodName);
        if resolved is ClassInfo {
            RequestFieldInfo[] requestFields = extractRequestFields(resolved);
            enhancedParam = {
                name: param.name,
                typeName: param.typeName,
                requestFields: requestFields
            };
        }
        enhancedParams.push(enhancedParam);
    }
    return enhancedParams;
}

# Check if a type is a simple/primitive type
#
# + typeName - Type name to check
# + return - True if simple type
public function isSimpleType(string typeName) returns boolean {
    return typeName == "int" || typeName == "long" || typeName == "boolean" ||
           typeName == "String" || typeName == "double" || typeName == "float" ||
           typeName == "byte" || typeName == "char" || typeName == "short" ||
           typeName == "java.lang.String" || typeName == "java.lang.Object";
}
