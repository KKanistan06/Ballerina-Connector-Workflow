// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

# SDK source paths configuration.
public type SourcePaths record {|
    # Path to JAR file
    string jarPath;
    # Directory containing example code
    string? examplesDir = ();
    # Directory containing Javadoc files
    string? javadocDir = ();
|};

# Javadoc metadata for a method.
public type JavadocMethod record {|
    # Fully qualified name
    string className;
    # Method name
    string methodName;
    # Method description from javadoc
    string description;
    # Map of parameter name to description
    map<string> paramDocs;
    # Return value description
    string returnDoc;
    # Map of exeception type to description
    map<string> throwsDocs;
|};

# Maven artifact coordinates
public type MavenCoordinates record {|
    # Specifies Group ID of the artifact
    string groupId;
    # Specifies Artifact ID of the artifact
    string artifactId;
    # Specifies Version of the artifact
    string version;
    # Specifies Scope of the artifact
    string scope = "compile";
    # Specifies whether the dependency is optional
    boolean optional = false;
|};

# Maven resolution result
public type MavenArtifact record {|
    # Specifies Coordinates of the artifact
    MavenCoordinates coordinates;
    # Specifies the local file path of the resolved artifact
    string jarPath;
    # Specifies direct dependencies of the artifact
    MavenArtifact[] dependencies;
|};

# Configuration for SDK analysis.
public type AnalyzerConfig record {|
    # Enable quiet mode (minimal output)
    boolean quietMode = false;
    # Auto-confirm all prompts
    boolean autoYes = false;
    # Filter internal packages (sun.*, com.sun.*, etc.)
    boolean filterInternal = true;
    # Include deprecated methods
    boolean includeDeprecated = false;
    # Include private/protected members
    boolean includeNonPublic = false;
    # Custom package filters (packages to exclude)
    string[] excludePackages = [];
    # Specific packages to analyze (empty = all packages)
    string[] includePackages = [];
    # Maximum depth for dependency resolution
    int maxDependencyDepth = 3;
    # Specify whether to resolve dependencies via Maven
    boolean resolveDependencies = true;
    # Specify to use local Maven repository
    boolean useLocalRepository = true;
    # Custom Maven repository URL (if any)
    string? mavenRepository = ();
    # Enable offline mode (no network calls)
    boolean offlineMode = false;
    # Use documentation instead of JAR analysis
    boolean useDocumentation = false;
    # Documentation URL (Javadoc/API docs)
    string? documentationUrl = ();
    # Explicitly specify main API class name
    string? apiClassName = ();
    # OpenAI API key for spec doc generation
    string openaiApiKey = "";
|};

# Client initialization pattern metadata
public type ClientInitPattern record {|
    # Pattern name (e.g., builder, factory, constructor, static)
    string patternName;
    # Recommended initialization snippet
    string initializationCode;
    # Optional explanation or reasoning
    string? explanation = ();
    # Detection origin (llm|heuristic|error)
    string detectedBy;
|};

# Complete SDK metadata extracted from JAR.
public type SDKMetadata record {|
    # SDK name
    string sdkName;
    # SDK version
    string sdkVersion;
    # JAR file path
    string jarPath;
    # Main package name
    string mainPackage;
    # Client initialization pattern (LLM or heuristic)
    ClientInitPattern clientInitPattern;
    # All extracted classes
    ClassMetadata[] classes;
    # Total number of public methods
    int totalMethods;
    # Total number of public classes
    int totalClasses;
    # Analysis timestamp
    string analyzedAt;
    # Type hierarchy information
    TypeHierarchy hierarchy;
|};

# Metadata for a single Java class.
public type ClassMetadata record {|
    # Fully qualified class name 
    string className;
    # Simple class name
    string simpleName;
    # Package name
    string packageName;
    # Specifies whether this is an interface
    boolean isInterface;
    # Specifies whether this is abstract
    boolean isAbstract;
    # Specifies whether this is an enum
    boolean isEnum;
    # Specifies the superclass name (if any)
    string? superClass;
    # Fully qualified interface names
    string[] interfaces;
    # Methods declared in this class
    MethodMetadata[] methods;
    # Fields declared in this class
    FieldMetadata[] fields;
    # Public constructors declared in this class
    ConstructorMetadata[] constructors;
    # Specifies whether this class is deprecated
    boolean isDeprecated;
    # Annotation names present on this class
    string[] annotations;
|};

# Metadata for a Java method.
public type MethodMetadata record {|
    # Method name
    string methodName;
    # Parameters of the method
    ParameterMetadata[] parameters;
    # Return type (fully qualified)
    string returnType;
    # Simple return type name
    string returnTypeSimple;
    # Exceptions that can be thrown
    string[] exceptions;
    # Specifies whether method is static
    boolean isStatic;
    # Specifies whether method is final
    boolean isFinal;
    # Specifies whether method is abstract
    boolean isAbstract;
    # Method signature (for uniqueness)
    string signature;
    # Specifies whether this method is deprecated
    boolean isDeprecated;
    # Generic type parameters (if any)
    string[] typeParameters;
|};

# Request field for output (excludes internal flags like isCommonlyUsed)
public type RequestFieldOutput record {|
    # Field name
    string name;
    # Type name
    string 'type;
    # Fully qualified type
    string fullType;
    # Whether this field is required
    boolean isRequired;
|};

# Metadata for a method/constructor parameter.
public type ParameterMetadata record {|
    # Parameter name (may be auto-generated if not available)
    string paramName;
    # Fully qualified type name
    string paramType;
    # Simple type name
    string paramTypeSimple;
    # Request object fields (if this parameter is a Request class)
    RequestFieldOutput[]? requestFields = ();
|};
# Metadata for a Java field.
public type FieldMetadata record {|
    # Field name
    string fieldName;
    # Fully qualified type
    string fieldType;
    # Simple type name
    string fieldTypeSimple;
    # Specifies whether field is static
    boolean isStatic;
    # Specifies whether field is final
    boolean isFinal;
    # Specifies whether this field is deprecated
    boolean isDeprecated;
|};

# Metadata for a Java constructor.
public type ConstructorMetadata record {|
    # Constructor parameters
    ParameterMetadata[] parameters;
    # Exceptions that can be thrown
    string[] exceptions;
    # Constructor signature
    string signature;
    # Specifies whether this constructor is deprecated
    boolean isDeprecated;
|};

# Configuration for Anthropic API calls
type AnthropicConfiguration record {
    # API key for authentication
    string apiKey;
    # Model to use for analysis (e.g., "claude-2")
    string model;
    # Maximum number of tokens for the API call
    int maxTokens;
};

# Type hierarchy information.
public type TypeHierarchy record {|
    # Map of class name to its superclass
    map<string> inheritance;
    # Map of class name to its interfaces
    map<string[]> implementations;
    # Map of class name to its subclasses (reverse hierarchy)
    map<string[]> subclasses;
|};

# Scoring breakdown for client class identification
public type ClientClassScore record {|
    # Specifies the name score
    int nameScore;
    # Specifies the structure score
    int structureScore;
    # Specifies the package score
    int packageScore;
    # Specifies the method score
    int methodScore;
    # Specifies the pattern score
    int patternScore;
    # Specifies the total score
    int totalScore;
    # Specifies the count of public methods
    int publicMethodCount;
    # Specifies the count of CRUD-like methods
    int crudMethodCount;
|};

# Method scoring information
public type MethodScore record {|
    # Specifies the method information
    MethodInfo method;
    # Specifies the category score
    int categoryScore;
    # Specifies the name score
    int nameScore;
    # Specifies the signature score
    int signatureScore;
    # Specifies the total score
    int totalScore;
    # Specifies the method name
    string methodName;
|};

# Raw class information from Java reflection.
public type ClassInfo record {|
    # Fully qualified class name
    string className;
    # Specifies the package name
    string packageName ;
    # Spefyies whether the class is an interface
    boolean isInterface;
    # Specifies whether the class is abstract
    boolean isAbstract;
    # Specifies whether the class is an enum
    boolean isEnum;
    # Simple class name (e.g., "S3Client")
    string simpleName;
    # Fully qualified superclass name (if any)
    string? superClass;
    # Fully qualified interface names
    string[] interfaces;
    # Methods declared in the class
    MethodInfo[] methods;
    # Fields declared in the class
    FieldInfo[] fields;
    # Constructors declared in the class
    ConstructorInfo[] constructors;
    # Specifies whether the class is deprecated
    boolean isDeprecated;
    # Annotation names present on the class
    string[] annotations;
    # Indicates whether this class entry was unresolved during reflection
    # (e.g., missing dependencies prevented full loading). Default is `false`.
    boolean unresolved = false;
|};

# Information about identified client class with scoring
public type ClientClassInfo record {|
    # Specifies the class information
    ClassInfo classInfo;
    # Specifies the client class score
    ClientClassScore score;
    # Specifies the priority ( 1 = highest, 4 = lowest )
    int priority; 
|};

# Raw method information from Java reflection.
public type MethodInfo record {|
    # Method name
    string name;
    # Parameters of the method
    ParameterInfo[] parameters;
    # Return type (fully qualified)
    string returnType;
    # Exceptions that can be thrown
    string[] exceptions;
    # Specifies whether method is static
    boolean isStatic;
    # Specifies whether method is final
    boolean isFinal;
    # Specifies whether method is abstract
    boolean isAbstract;
    # Method signature (for uniqueness)
    string signature;
    # Javadoc comment (if available)
    string? javadoc;
    # Specifies whether this method is deprecated
    boolean isDeprecated;
    # Generic type parameters (if any)
    string[] typeParameters;
    # Annotation names present on the method
    string[] annotations;
|};

# Raw parameter information.
public type ParameterInfo record {|
    # Parameter name
    string name;
    # Parameter type name (simple name)
    string typeName;
    # Request object fields (if this parameter is a Request class)
    RequestFieldInfo[]? requestFields = ();
|};
# Raw field information.
public type FieldInfo record {|
    # Field name
    string name;
    # Field type (fully qualified) 
    string typeName;
    # Specifies whether field is static
    boolean isStatic;
    # Specifies whether field is final
    boolean isFinal;
    # Javadoc comment (if available)
    string? javadoc;
    # Specifies whether this field is deprecated
    boolean isDeprecated;
|};

# Raw constructor information.
public type ConstructorInfo record {|
    # Constructor parameters
    ParameterInfo[] parameters;
    # Exceptions that can be thrown
    string[] exceptions;
    # Javadoc comment (if available)
    string? javadoc;
    # Specifies whether this constructor is deprecated
    boolean isDeprecated;
|};

# LLM-based client scoring criteria
public type LLMClientScore record {|
    # Public API score (0-100)
    decimal publicApiScore;
    # Operation coverage score (0-100)
    decimal operationCoverage;
    # Has Request/Response types (0-100)
    decimal hasRequestResponseTypes;
    # Stability score (0-100)
    decimal stabilityScore;
    # Example usage score (0-100)
    decimal exampleUsageScore;
    # Total weighted score
    decimal totalScore;
    # Score breakdown explanation
    string breakdown;
|};

# Ensemble score record containing all signal scores and metadata.
type EnsembleScore record {
    # Scores for individual signals
    decimal methodCountScore;
    # Score based on the ratio of action verbs in method names
    decimal actionVerbScore;
    # score based on the presence of builder/fluent patterns
    decimal paramComplexityScore;
    # Score based on class name patterns
    decimal returnDiversityScore;
    # Score based on package naming conventions
    decimal interfaceScore;
    # Final aggregated score
    decimal packageDepthScore;
    # Score based on the field analysis
    decimal fieldCountScore;
    # Score baed on the hierarchy
    decimal staticRatioScore;
    # Score based on the exeception declarations
    decimal exceptionScore;
    # Score based on unique parameter types
    decimal paramTypeScore;
    # Bonus for AWS SDK v2 client pattern
    decimal sdkV2Bonus;
    # Bonus for matching service context
    decimal serviceContextBonus;
    # Total ensemble score
    decimal totalScore;
    # Count of action methods for reporting
    int actionMethodCount;
    # Breakdown of individual signal scores
    string breakdown;
};

# Filter configuration.
public type FilterConfig record {|
    # Filter internal packages
    boolean filterInternal;
    # Include deprecated members
    boolean includeDeprecated;
    # Include non-public members
    boolean includeNonPublic;
    # Custom exclude patterns
    string[] excludePackages;
    # Include only these packages
    string[] includePackages;
|};

# Configuration for method prioritization.
public type PrioritizerConfig record {|
    # Maximum methods to include per client
    int maxMethodsPerClient = 20;
    # Include method overloads or just the primary variant
    boolean includeOverloads = false;
    # Include close(), shutdown(), etc.
    boolean includeLifecycleMethods = false;
    # Include builder pattern methods
    boolean includeBuilderMethods = false;
|};

# Analysis result summary.
public type AnalysisResult record {|
    # Success status
    boolean success;
    # Path to generated metadata file
    string metadataPath;
    # Number of classes analyzed
    int classesAnalyzed;
    # Number of methods extracted
    int methodsExtracted;
    # Analysis duration in milliseconds
    int durationMs;
    # Specifies any warnings during analysis
    string[] warnings;
|};

# Error type for SDK analyzer.
public type AnalyzerError error;

# Error type for Maven resolution.
public type MavenError distinct error;

# Request field information for Request/Response objects
public type RequestFieldInfo record {|
    # Field name
    string name;
    # Field type name (simple)
    string typeName;
    # Full qualified type name
    string fullType;
    # Whether this field is required
    boolean isRequired;
|};

# Root client class information
public type RootClientInfo record {|
    # Fully qualified class name
    string className;
    # Package name
    string packageName;
    # Simple class name
    string simpleName;
    # Whether it's an interface
    boolean isInterface;
    # Constructor information
    ConstructorInfo[] constructors;
    # Selected and ranked methods
    MethodInfo[] methods;
|};

# Supporting class information
public type SupportingClassInfo record {|
    # Fully qualified class name
    string className;
    # Simple class name
    string simpleName;
    # Package name
    string packageName;
    # Purpose of this class (Return type, Parameter type, etc.)
    string purpose;
|};

# SDK information
public type SDKInfo record {|
    # SDK name
    string name;
    # SDK version
    string version;
    # Root client class name
    string rootClientClass;
|};

# Analysis summary
public type AnalysisSummary record {|
    # Total classes found in JAR
    int totalClassesFound;
    # Total methods in root client
    int totalMethodsInClient;
    # Number of selected methods
    int selectedMethods;
    # Analysis approach used
    string analysisApproach;
|};

# Complete structured SDK metadata (final output)
public type StructuredSDKMetadata record {|
    # SDK basic information
    SDKInfo sdkInfo;
    # Client initialization pattern
    ClientInitPattern clientInit;
    # Root client class details
    RootClientInfo rootClient;
    # Supporting classes used by the client
    SupportingClassInfo[] supportingClasses;
    # Analysis summary
    AnalysisSummary analysis;
|};
