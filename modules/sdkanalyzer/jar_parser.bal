// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/jballerina.java;

# Resolve Maven coordinate or local JAR path
#
# + sdkRef - Maven coordinate (e.g., "s3:2.25.16") or local JAR path
# + return - Resolved JAR information or error
public function resolveSDKReference(string sdkRef) returns map<json>|error {
    // Check if it's a Maven coordinate (contains ':')
    if sdkRef.includes(":") && !sdkRef.includes("/") && !sdkRef.includes("\\") {
        // Maven coordinate
        json result = resolveMavenArtifact(sdkRef);
        return <map<json>> result;
    } else {
        // Local JAR path - return simple map
        return {
            "mainJar": sdkRef,
            "allJars": [sdkRef],
            "groupId": "",
            "artifactId": "",
            "version": "",
            "cacheDir": ""
        };
    }
}

# Parse JAR file and extract class information.
# Supports both local JAR paths and Maven resolution results.
#
# + sdkRef - Maven coordinate or local JAR path  
# + sourcesPath - Optional path to sources JAR
# + return - Array of class information or error
public function parseJarFromReference(string sdkRef, string? sourcesPath) returns ClassInfo[]|error {
    // Resolve the SDK reference (Maven or local)
    map<json>|error resolvedResult = resolveSDKReference(sdkRef);
    
    if resolvedResult is error {
        return resolvedResult;
    }
    
    map<json> resolved = resolvedResult;
    
    // Attach optional sources path if provided (native Java analyzer will handle extraction/parsing)
    if sourcesPath != () {
        resolved["sourcesPath"] = sourcesPath;
    }

    // Call JavaParser-based Java method with resolved result
    json result = analyzeJarWithJavaParserExternal(resolved);
    
    // The native Java method returns a JSON-like array
    json[] classArray = <json[]> result;

    ClassInfo[] classes = [];

    // Process each class and normalize fields to match Ballerina record types
    foreach json item in classArray {
        map<json> classMap = <map<json>> item;

        // Compute packageName if missing
        if !classMap.hasKey("packageName") {
            string className = classMap["className"].toString();
            classMap["packageName"] = computePackageName(className);
        }

        // Compute simpleName if missing
        if !classMap.hasKey("simpleName") {
            string className = classMap["className"].toString();
            classMap["simpleName"] = computeSimpleName(className);
        }

        // Ensure class-level defaults
        if !classMap.hasKey("isInterface") {
            classMap["isInterface"] = false;
        }
        if !classMap.hasKey("isAbstract") {
            classMap["isAbstract"] = false;
        }
        if !classMap.hasKey("isEnum") {
            classMap["isEnum"] = false;
        }
        if !classMap.hasKey("isDeprecated") {
            classMap["isDeprecated"] = false;
        }
        if !classMap.hasKey("interfaces") {
            classMap["interfaces"] = [];
        }
        if !classMap.hasKey("annotations") {
            classMap["annotations"] = [];
        }

        // Normalize methods
        if classMap.hasKey("methods") {
            json[] methods = <json[]> classMap["methods"];
            foreach json m in methods {
                map<json> mMap = <map<json>> m;
                if !mMap.hasKey("returnType") {
                    mMap["returnType"] = "";
                }
                if !mMap.hasKey("exceptions") {
                    mMap["exceptions"] = [];
                }
                if !mMap.hasKey("isStatic") {
                    mMap["isStatic"] = false;
                }
                if !mMap.hasKey("isFinal") {
                    mMap["isFinal"] = false;
                }
                if !mMap.hasKey("isAbstract") {
                    mMap["isAbstract"] = false;
                }
                if !mMap.hasKey("signature") {
                    // fallback to method name as signature placeholder
                    if mMap.hasKey("name") {
                        mMap["signature"] = mMap["name"];
                    } else {
                        mMap["signature"] = "";
                    }
                }
                if !mMap.hasKey("typeParameters") {
                    mMap["typeParameters"] = [];
                }
                if !mMap.hasKey("annotations") {
                    mMap["annotations"] = [];
                }

                // Normalize parameters
                if mMap.hasKey("parameters") {
                    json[] params = <json[]> mMap["parameters"];
                    foreach json p in params {
                        map<json> pMap = <map<json>> p;
                        // Java producer uses key "type"; our types expect "typeName"
                        if pMap.hasKey("type") && !pMap.hasKey("typeName") {
                            pMap["typeName"] = pMap["type"];
                        }
                        if !pMap.hasKey("typeName") {
                            pMap["typeName"] = "";
                        }
                        if !pMap.hasKey("name") {
                            pMap["name"] = "";
                        }
                        if !pMap.hasKey("isVarArgs") {
                            pMap["isVarArgs"] = false;
                        }
                        if !pMap.hasKey("typeArguments") {
                            pMap["typeArguments"] = [];
                        }
                        if !pMap.hasKey("requestFields") {
                            pMap["requestFields"] = [];
                        } else {
                            // Normalize requestFields to ensure typeName and fullType consistency
                            json[] reqFields = <json[]> pMap["requestFields"];
                            foreach json rf in reqFields {
                                map<json> rfMap = <map<json>> rf;
                                // Ensure typeName is set from "type" if needed
                                if rfMap.hasKey("type") && !rfMap.hasKey("typeName") {
                                    rfMap["typeName"] = rfMap["type"];
                                }
                                if !rfMap.hasKey("typeName") {
                                    rfMap["typeName"] = rfMap.hasKey("type") ? rfMap["type"] : "";
                                }
                                if !rfMap.hasKey("fullType") {
                                    rfMap["fullType"] = rfMap.hasKey("typeName") ? rfMap["typeName"] : "";
                                }
                                if !rfMap.hasKey("isRequired") {
                                    rfMap["isRequired"] = false;
                                }
                                if !rfMap.hasKey("description") {
                                    rfMap["description"] = null;
                                }
                                if !rfMap.hasKey("enumReference") {
                                    rfMap["enumReference"] = null;
                                }
                            }
                        }
                    }
                } else {
                    mMap["parameters"] = [];
                }
            }
        } else {
            classMap["methods"] = [];
        }

        // Normalize fields
        if classMap.hasKey("fields") {
            json[] flds = <json[]> classMap["fields"];
            foreach json f in flds {
                map<json> fMap = <map<json>> f;
                if fMap.hasKey("type") && !fMap.hasKey("typeName") {
                    fMap["typeName"] = fMap["type"];
                }
                if !fMap.hasKey("typeName") {
                    fMap["typeName"] = "";
                }
                if !fMap.hasKey("name") {
                    fMap["name"] = "";
                }
                if !fMap.hasKey("isStatic") {
                    fMap["isStatic"] = false;
                }
                if !fMap.hasKey("isFinal") {
                    fMap["isFinal"] = false;
                }
                if !fMap.hasKey("isDeprecated") {
                    fMap["isDeprecated"] = false;
                }
            }
        } else {
            classMap["fields"] = [];
        }

        // Normalize constructors
        if classMap.hasKey("constructors") {
            json[] ctors = <json[]> classMap["constructors"];
            foreach json c in ctors {
                map<json> cMap = <map<json>> c;
                if !cMap.hasKey("isDeprecated") {
                    cMap["isDeprecated"] = false;
                }
                if !cMap.hasKey("javadoc") {
                    cMap["javadoc"] = null;
                }
                if cMap.hasKey("parameters") {
                    json[] params = <json[]> cMap["parameters"];
                    foreach json p in params {
                        map<json> pMap = <map<json>> p;
                        if pMap.hasKey("type") && !pMap.hasKey("typeName") {
                            pMap["typeName"] = pMap["type"];
                        }
                        if !pMap.hasKey("typeName") {
                            pMap["typeName"] = "";
                        }
                        if !pMap.hasKey("name") {
                            pMap["name"] = "";
                        }
                        if !pMap.hasKey("isVarArgs") {
                            pMap["isVarArgs"] = false;
                        }
                    }
                } else {
                    cMap["parameters"] = [];
                }
                if !cMap.hasKey("exceptions") {
                    cMap["exceptions"] = [];
                }
            }
        } else {
            classMap["constructors"] = [];
        }

        // Ensure unresolved flag present
        if !classMap.hasKey("unresolved") {
            classMap["unresolved"] = false;
        }

        // Manually construct ClassInfo to avoid cloneWithType conversion issues
        ClassInfo cls = {
            className: classMap.hasKey("className") ? classMap["className"].toString() : "",
            packageName: classMap.hasKey("packageName") ? classMap["packageName"].toString() : "",
            isInterface: <boolean> classMap["isInterface"],
            isAbstract: <boolean> classMap["isAbstract"],
            isEnum: <boolean> classMap["isEnum"],
            simpleName: classMap.hasKey("simpleName") ? classMap["simpleName"].toString() : "",
            superClass: classMap.hasKey("superClass") && classMap["superClass"] != () ? classMap["superClass"].toString() : (),
            interfaces: toStringArray(classMap.hasKey("interfaces") ? <json[]> classMap["interfaces"] : ()),
            methods: convertMethods(classMap.hasKey("methods") ? <json[]> classMap["methods"] : ()),
            fields: convertFields(classMap.hasKey("fields") ? <json[]> classMap["fields"] : ()),
            constructors: convertConstructors(classMap.hasKey("constructors") ? <json[]> classMap["constructors"] : ()),
            isDeprecated: classMap.hasKey("isDeprecated") ? <boolean> classMap["isDeprecated"] : false,
            annotations: toStringArray(classMap.hasKey("annotations") ? <json[]> classMap["annotations"] : ()),
            unresolved: classMap.hasKey("unresolved") ? <boolean> classMap["unresolved"] : false
        };
        classes.push(cls);
    }

    return classes;
}

# Compute package name from fully qualified class name
#
# + className - Fully qualified class name
# + return - Package name
function computePackageName(string className) returns string {
    int? idx = className.lastIndexOf(".");
    return (idx is int && idx > 0) ? className.substring(0, idx) : "";
}

# Compute simple name from fully qualified class name
#
# + className - Fully qualified class name
# + return - Simple name
function computeSimpleName(string className) returns string {
    int? idx = className.lastIndexOf(".");
    return (idx is int && idx > 0) ? className.substring(idx + 1) : className;
}

// Convert a json array of strings (or BString) to Ballerina string[]
function toStringArray(json[]? arr) returns string[] {
    if arr is json[] {
        string[] out = [];
        foreach json v in arr {
            out.push(v.toString());
        }
        return out;
    }
    return [];
}

// Extract simple type name from fully qualified type (e.g., "java.lang.String" -> "String")
function jpExtractSimpleTypeName(string fullType) returns string {
    if fullType == "" {
        return "arg";
    }
    int? idx = fullType.lastIndexOf(".");
    if idx is int {
        if idx >= 0 {
            return fullType.substring(idx + 1);
        }
    }
    return fullType;
}

// Generate a reasonable parameter name from a type name
function jpGenerateParamNameFromType(string fullType, int index) returns string {
    string simple = jpExtractSimpleTypeName(fullType);
    // make camelCase
    if simple.length() == 0 {
        return string `arg${index}`;
    }
    string first = simple.substring(0,1).toLowerAscii();
    string rest = simple.substring(1);
    return string `${first}${rest}`;
}

// Convert parameters array to ParameterInfo[]
function convertParameters(json[]? params) returns ParameterInfo[] {
    ParameterInfo[] out = [];
    if params is json[] {
        foreach json p in params {
            map<json> pMap = <map<json>> p;
            string tname = pMap.hasKey("typeName") ? pMap["typeName"].toString() : (pMap.hasKey("type") ? pMap["type"].toString() : "");
            string pname = pMap.hasKey("name") ? pMap["name"].toString() : "";
            // If name missing or looks like a generated arg, generate a better name
            if pname == "" || pname.startsWith("arg") {
                pname = jpGenerateParamNameFromType(tname, out.length() + 1);
            }

            ParameterInfo param = {
                name: pname,
                typeName: tname,
                requestFields: []
            };
            out.push(param);
        }
    }
    return out;
}

// Convert methods array to MethodInfo[]
function convertMethods(json[]? methods) returns MethodInfo[] {
    MethodInfo[] out = [];
    if methods is json[] {
        foreach json m in methods {
            map<json> mMap = <map<json>> m;
            MethodInfo mi = {
                name: mMap.hasKey("name") ? mMap["name"].toString() : "",
                parameters: convertParameters(mMap.hasKey("parameters") ? <json[]> mMap["parameters"] : ()),
                returnType: mMap.hasKey("returnType") ? mMap["returnType"].toString() : "",
                exceptions: toStringArray(mMap.hasKey("exceptions") ? <json[]> mMap["exceptions"] : ()),
                isStatic: mMap.hasKey("isStatic") ? <boolean> mMap["isStatic"] : false,
                isFinal: mMap.hasKey("isFinal") ? <boolean> mMap["isFinal"] : false,
                isAbstract: mMap.hasKey("isAbstract") ? <boolean> mMap["isAbstract"] : false,
                signature: mMap.hasKey("signature") ? mMap["signature"].toString() : (mMap.hasKey("name") ? mMap["name"].toString() : ""),
                javadoc: mMap.hasKey("javadoc") && mMap["javadoc"] != () ? mMap["javadoc"].toString() : (),
                isDeprecated: mMap.hasKey("isDeprecated") ? <boolean> mMap["isDeprecated"] : false,
                typeParameters: toStringArray(mMap.hasKey("typeParameters") ? <json[]> mMap["typeParameters"] : ()),
                annotations: toStringArray(mMap.hasKey("annotations") ? <json[]> mMap["annotations"] : ())
            };
            out.push(mi);
        }
    }
    return out;
}

// Convert fields array to FieldInfo[]
function convertFields(json[]? fields) returns FieldInfo[] {
    FieldInfo[] out = [];
    if fields is json[] {
        foreach json f in fields {
            map<json> fMap = <map<json>> f;
            FieldInfo fi = {
                name: fMap.hasKey("name") ? fMap["name"].toString() : "",
                typeName: fMap.hasKey("typeName") ? fMap["typeName"].toString() : (fMap.hasKey("type") ? fMap["type"].toString() : ""),
                isStatic: fMap.hasKey("isStatic") ? <boolean> fMap["isStatic"] : false,
                isFinal: fMap.hasKey("isFinal") ? <boolean> fMap["isFinal"] : false,
                javadoc: fMap.hasKey("javadoc") && fMap["javadoc"] != () ? fMap["javadoc"].toString() : (),
                isDeprecated: fMap.hasKey("isDeprecated") ? <boolean> fMap["isDeprecated"] : false
            };
            out.push(fi);
        }
    }
    return out;
}

// Convert constructors array to ConstructorInfo[]
function convertConstructors(json[]? ctors) returns ConstructorInfo[] {
    ConstructorInfo[] out = [];
    if ctors is json[] {
        foreach json c in ctors {
            map<json> cMap = <map<json>> c;
            ConstructorInfo ci = {
                parameters: convertParameters(cMap.hasKey("parameters") ? <json[]> cMap["parameters"] : ()),
                exceptions: toStringArray(cMap.hasKey("exceptions") ? <json[]> cMap["exceptions"] : ()),
                javadoc: cMap.hasKey("javadoc") && cMap["javadoc"] != () ? cMap["javadoc"].toString() : (),
                isDeprecated: cMap.hasKey("isDeprecated") ? <boolean> cMap["isDeprecated"] : false
            };
            out.push(ci);
        }
    }
    return out;
}

# External function to analyze JAR (Java interop).
#
# + jarPathOrResolved - JAR file path or Maven resolution map
# + return - JSON array
function analyzeJarExternal(string|map<json> jarPathOrResolved) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JarAnalyzer",
    name: "parseJar",
    paramTypes: ["java.lang.Object"]
} external;

# External function to analyze JAR using JavaParser approach.
#
# + jarPathOrResolved - JAR file path or Maven resolution map
# + return - JSON array
function analyzeJarWithJavaParserExternal(string|map<json> jarPathOrResolved) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.JavaParserAnalyzer",
    name: "analyzeJarWithJavaParser",
    paramTypes: ["java.lang.Object"]
} external;

# External function to resolve Maven artifact.
#
# + coordinate - Maven coordinate
# + return - Resolution result map
function resolveMavenArtifact(string coordinate) returns json = @java:Method {
    'class: "io.ballerina.connector.automator.sdkanalyzer.MavenResolver",
    name: "resolveMavenArtifact",
    paramTypes: ["io.ballerina.runtime.api.values.BString"]
} external;
