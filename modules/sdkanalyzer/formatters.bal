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

// Formatting utilities for LLM prompts and output generation

import ballerina/regex;

# Format class information for LLM analysis
#
# + cls - Class to format
# + return - Formatted class information string
public function formatClassInfoForLLM(ClassInfo cls) returns string {
    string methodList = "";
    int methodsToShow = cls.methods.length() < 10 ? cls.methods.length() : 10;
    foreach int i in 0 ..< methodsToShow {
        MethodInfo m = cls.methods[i];
        methodList = methodList + string `  - ${m.name}(${m.parameters.length()} params) -> ${m.returnType}\n`;
    }
    
    string superClassInfo;
    if cls.superClass is () {
        superClassInfo = "None";
    } else {
        superClassInfo = <string>cls.superClass;
    }
    
    return string `
Class Name: ${cls.className}
Simple Name: ${cls.simpleName}
Package: ${cls.packageName}
Is Interface: ${cls.isInterface}
Is Abstract: ${cls.isAbstract}
Is Deprecated: ${cls.isDeprecated}
Total Methods: ${cls.methods.length()}
Total Fields: ${cls.fields.length()}
Super Class: ${superClassInfo}

Sample Methods (first 10):
${methodList}

Constructors: ${cls.constructors.length()}
Interfaces Implemented: ${cls.interfaces.length()}`;
}

# Format constructors for LLM context
#
# + constructors - Constructor list
# + return - Formatted constructor info
public function formatConstructorsForLLM(ConstructorInfo[] constructors) returns string {
    if constructors.length() == 0 {
        return "No public constructors found";
    }
    string[] constrStrings = [];
    foreach ConstructorInfo c in constructors {
        constrStrings.push(string `(${c.parameters.length()} params)`);
    }
    return "Constructors: " + joinStrings(constrStrings, ", ");
}

# Format methods for init pattern detection
#
# + methods - Method list
# + maxMethods - Maximum number to show
# + return - Formatted method info
public function formatMethodsForInitPattern(MethodInfo[] methods, int maxMethods) returns string {
    int count = methods.length() < maxMethods ? methods.length() : maxMethods;
    string result = string `Key Methods (first ${maxMethods}):\n`;
    foreach int i in 0 ..< count {
        MethodInfo m = methods[i];
        result = result + string `- ${m.name}()` + "\n";
    }
    return result;
}

# Format method list for LLM
#
# + methods - Methods to format
# + maxMethods - Maximum number of methods to show
# + return - Formatted method list
public function formatMethodsForLLM(MethodInfo[] methods, int maxMethods) returns string {
    int count = methods.length() < maxMethods ? methods.length() : maxMethods;
    string result = "";
    foreach int i in 0 ..< count {
        MethodInfo m = methods[i];
        result = result + string `- ${m.name}(${m.parameters.length()} params): ${m.returnType}` + "\n";
    }
    return result;
}

# Format methods for ranking
#
# + methods - Methods to format
# + maxMethods - Max methods to show
# + return - Formatted string
public function formatMethodsForRanking(MethodInfo[] methods, int maxMethods) returns string {
    int count = methods.length() < maxMethods ? methods.length() : maxMethods;
    string result = "";
    foreach int i in 0 ..< count {
        MethodInfo method = methods[i];
        string params = "";
        foreach int j in 0 ..< method.parameters.length() {
            params = params + method.parameters[j].name;
            if j < method.parameters.length() - 1 {
                params = params + ", ";
            }
        }
        result = result + string `${i + 1}. ${method.name}(${params}) -> ${method.returnType}` + "\n";
    }
    return result;
}

# Format methods with details for LLM analysis
#
# + methods - Methods to format
# + maxMethods - Maximum methods to include
# + return - Formatted method details
public function formatMethodsWithDetailsForLLM(MethodInfo[] methods, int maxMethods) returns string {
    int count = methods.length() < maxMethods ? methods.length() : maxMethods;
    string result = "";
    
    foreach int i in 0 ..< count {
        MethodInfo m = methods[i];
        string paramList = "";
        
        foreach int j in 0 ..< m.parameters.length() {
            ParameterInfo p = m.parameters[j];
            if j > 0 {
                paramList = paramList + ", ";
            }
            paramList = paramList + p.name + ":" + p.typeName;
        }
        
        result = result + string `${i + 1}. ${m.name}(${paramList}) -> ${m.returnType}\n`;
    }
    
    return result;
}

# Format constructor details for init pattern detection
#
# + constructors - Constructor list
# + return - Formatted constructor details
public function formatConstructorDetails(ConstructorInfo[] constructors) returns string {
    if constructors.length() == 0 {
        return "No public constructors";
    }
    string details = "";
    foreach int i in 0 ..< constructors.length() {
        ConstructorInfo ctor = constructors[i];
        string paramInfo = ctor.parameters.length() == 0 ? "no args" : string `${ctor.parameters.length()} params`;
        details = details + string `  Constructor ${i + 1}: ${paramInfo}\n`;
    }
    return details;
}

# Format static methods list
#
# + methods - All methods
# + return - Comma-separated list of static method names
public function formatStaticMethods(MethodInfo[] methods) returns string {
    string[] staticMethods = [];
    foreach MethodInfo m in methods {
        if m.isStatic {
            staticMethods.push(string `${m.name}()`);
        }
    }
    return staticMethods.length() == 0 ? "None found" : string:'join(", ", ...staticMethods);
}

# Format methods list for ranking prompt
#
# + methods - Methods to format
# + return - Formatted numbered method list
public function formatMethodsListForRanking(MethodInfo[] methods) returns string {
    string methodsList = "";
    foreach int i in 0 ..< methods.length() {
        MethodInfo m = methods[i];
        string paramInfo = m.parameters.length().toString() + " params";
        if m.parameters.length() > 0 && m.parameters.length() <= 3 {
            string[] paramTypes = [];
            foreach ParameterInfo p in m.parameters {
                string[] parts = regex:split(p.typeName, "\\.");
                paramTypes.push(parts[parts.length() - 1]);
            }
            paramInfo = string:'join(", ", ...paramTypes);
        }
        methodsList = methodsList + (i + 1).toString() + ". " + m.name + "(" + paramInfo + ")\n";
    }
    return methodsList;
}

# Join string array with separator
#
# + arr - String array to join
# + separator - Separator between elements
# + return - Joined string
public function joinStrings(string[] arr, string separator) returns string {
    if arr.length() == 0 {
        return "";
    }
    string result = "";
    foreach int i in 0 ..< arr.length() {
        result = result + arr[i];
        if i < arr.length() - 1 {
            result = result + separator;
        }
    }
    return result;
}
