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

package io.ballerina.connector.automator.sdkanalyzer;

import com.github.javaparser.JavaParser;
import com.github.javaparser.ParserConfiguration;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.Modifier;
import com.github.javaparser.ast.NodeList;
import com.github.javaparser.ast.body.ClassOrInterfaceDeclaration;
import com.github.javaparser.ast.body.ConstructorDeclaration;
import com.github.javaparser.ast.body.EnumConstantDeclaration;
import com.github.javaparser.ast.body.EnumDeclaration;
import com.github.javaparser.ast.body.FieldDeclaration;
import com.github.javaparser.ast.body.MethodDeclaration;
import com.github.javaparser.ast.body.Parameter;
import com.github.javaparser.ast.body.TypeDeclaration;
import com.github.javaparser.ast.body.VariableDeclarator;
import com.github.javaparser.ast.comments.JavadocComment;
import com.github.javaparser.ast.type.ClassOrInterfaceType;
import com.github.javaparser.ast.type.Type;
import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.MapType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/**
 * JavaParser-based analyzer for Java SDK JARs.
 * This replaces the reflection-based approach with static source analysis
 * using JavaParser and ASM for bytecode analysis when sources are not available.
 */
public class JavaParserAnalyzer {

    private static final Set<String> EXCLUDED_PACKAGES = Set.of(
            "sun", "com.sun", "jdk", "java.lang", "java.util", "java.io", 
            "java.net", "java.time", "java.concurrent", "javax"
    );

    /**
     * Analyze JAR using JavaParser approach.
     * This is the main entry point that replaces the reflection-based parsing.
     *
     * @param jarPathOrResult JAR path or Maven resolution result
     * @return Parsed class information
     */
    @SuppressWarnings("unchecked")
    public static Object analyzeJarWithJavaParser(Object jarPathOrResult) {
        try {
            List<File> jarFiles = new ArrayList<>();
            String mainJarPath;
            
            // Handle input (JAR path or Maven result)
            if (jarPathOrResult instanceof BMap) {
                BMap<BString, Object> mavenResult = (BMap<BString, Object>) jarPathOrResult;
                
                Object allJarsObj = mavenResult.get(StringUtils.fromString("allJars"));
                if (allJarsObj instanceof BArray) {
                    BArray allJars = (BArray) allJarsObj;
                    
                    for (int i = 0; i < allJars.getLength(); i++) {
                        String jarPath = allJars.getBString(i).getValue();
                        File jarFile = new File(jarPath);
                        if (jarFile.exists()) {
                            jarFiles.add(jarFile);
                        }
                    }
                }
                
                mainJarPath = mavenResult.get(StringUtils.fromString("mainJar")).toString();
            } else {
                String jarPath = jarPathOrResult.toString();
                File jarFile = new File(jarPath);
                
                if (!jarFile.exists()) {
                    return ErrorCreator.createError(
                            StringUtils.fromString("JAR file not found: " + jarPath));
                }
                
                mainJarPath = jarPath;
                jarFiles.add(jarFile);
            }
            
            if (jarFiles.isEmpty()) {
                return ErrorCreator.createError(
                        StringUtils.fromString("No JARs to analyze"));
            }
            
            System.err.println("INFO: Analyzing " + jarFiles.size() + " JAR file(s) with JavaParser");
            
            // 1. List all classes in the main JAR
            List<String> classNames = listAllClasses(new File(mainJarPath));
            System.err.println("INFO: Found " + classNames.size() + " classes");
            
            // 2. Extract source files and analyze with JavaParser
            List<BMap<BString, Object>> classes = new ArrayList<>();

            // Check for explicit sourcesPath in the resolution map (if provided)
            String explicitSourcesPath = null;
            if (jarPathOrResult instanceof BMap) {
                BMap<BString, Object> mavenResult = (BMap<BString, Object>) jarPathOrResult;
                Object sourcesObj = mavenResult.get(StringUtils.fromString("sourcesPath"));
                if (sourcesObj != null) {
                    explicitSourcesPath = sourcesObj.toString();
                }
            }

            Map<String, CompilationUnit> parsedSources = extractAndParseSourceFiles(jarFiles, explicitSourcesPath);

            System.err.println("DEBUG: explicitSourcesPath=" + explicitSourcesPath);
            System.err.println("INFO: Parsed " + parsedSources.size() + " source files");
            
            // 3. For each class, create metadata using JavaParser + ASM fallback
            for (String className : classNames) {
                if (shouldIncludeClass(className)) {
                    try {
                        BMap<BString, Object> classInfo = analyzeClassWithJavaParser(
                                className, parsedSources, jarFiles);
                        if (classInfo != null) {
                            classes.add(classInfo);
                        }
                    } catch (Exception e) {
                        System.err.println("WARNING: Failed to analyze class " + className + ": " + e.getMessage());
                    }
                }
            }
            
            System.err.println("INFO: Successfully analyzed " + classes.size() + " classes");
            
            // Convert to BArray
            MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
            return ValueCreator.createArrayValue(
                    classes.toArray(new BMap[0]),
                    TypeCreator.createArrayType(mapType));
            
        } catch (Exception e) {
            e.printStackTrace();
            return ErrorCreator.createError(
                    StringUtils.fromString("JavaParser analysis failed: " + e.getMessage()));
        }
    }
    
    /**
     * List all classes in a JAR file.
     *
     * @param jarFile JAR file to scan
     * @return List of class names
     */
    private static List<String> listAllClasses(File jarFile) throws IOException {
        List<String> classNames = new ArrayList<>();
        
        try (JarFile jar = new JarFile(jarFile)) {
            Enumeration<JarEntry> entries = jar.entries();
            
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String entryName = entry.getName();
                
                // Process .class files
                if (entryName.endsWith(".class") && !entryName.contains("$")) {
                    String className = entryName
                            .replace('/', '.')
                            .substring(0, entryName.length() - 6);
                    classNames.add(className);
                }
            }
        }
        
        return classNames;
    }
    
    /**
     * Extract and parse source files from JARs.
     *
     * @param jarFiles List of JAR files
     * @return Map of class name to CompilationUnit
     */
    private static Map<String, CompilationUnit> extractAndParseSourceFiles(List<File> jarFiles, String sourcesPath) {
        Map<String, CompilationUnit> parsedSources = new HashMap<>();

        // Configure JavaParser with basic settings
        ParserConfiguration config = new ParserConfiguration();
        config.setLanguageLevel(ParserConfiguration.LanguageLevel.JAVA_17);

        JavaParser javaParser = new JavaParser(config);

        // 1) Extract .java from provided sourcesPath (if any)
        if (sourcesPath != null && !sourcesPath.isBlank()) {
            File sp = new File(sourcesPath);
            if (sp.exists()) {
                if (sp.isDirectory()) {
                    // Walk directory for .java files
                    try {
                        java.nio.file.Files.walk(sp.toPath())
                                .filter(p -> p.toString().endsWith(".java"))
                                .forEach(p -> {
                                    try {
                                            String content = java.nio.file.Files.readString(p);
                                            CompilationUnit cu = javaParser.parse(content).getResult().orElse(null);
                                            if (cu != null) {
                                                // Derive a fallback path from the file path relative to the sources root
                                                String fallbackPath = sp.toPath().relativize(p).toString().replace(java.io.File.separatorChar, '/');
                                                String className = extractClassNameFromCU(cu, fallbackPath);
                                                if (className != null) {
                                                    parsedSources.put(className, cu);
                                                }
                                            }
                                    } catch (Exception e) {
                                        System.err.println("WARNING: Failed to parse source file " + p + ": " + e.getMessage());
                                    }
                                });
                    } catch (IOException e) {
                        System.err.println("WARNING: Failed to read sources directory: " + sp.getAbsolutePath());
                    }
                } else if (sp.isFile() && sp.getName().endsWith(".jar")) {
                    // Read .java entries from the provided sources JAR
                    try (JarFile srcJar = new JarFile(sp)) {
                        Enumeration<JarEntry> entries = srcJar.entries();
                        while (entries.hasMoreElements()) {
                            JarEntry entry = entries.nextElement();
                            String entryName = entry.getName();
                                if (entryName.endsWith(".java")) {
                                System.err.println("DEBUG: Found source entry: " + entryName);
                                try (InputStream inputStream = srcJar.getInputStream(entry)) {
                                    String content = new String(inputStream.readAllBytes());
                                    try {
                                        var parseResult = javaParser.parse(content);
                                        Optional<CompilationUnit> opt = parseResult.getResult();
                                        if (opt.isPresent()) {
                                            CompilationUnit cu = opt.get();
                                            // Use the jar entry path as a fallback if JavaParser doesn't provide a primary type
                                            String className = extractClassNameFromCU(cu, entryName);
                                            if (className != null) {
                                                parsedSources.put(className, cu);
                                                System.err.println("DEBUG: Parsed source for class: " + className);
                                            } else {
                                                System.err.println("DEBUG: Parsed but could not determine class name for: " + entryName);
                                            }
                                        } else {
                                            System.err.println("WARNING: parse returned empty for " + entryName + ", problems=" + parseResult.getProblems());
                                        }
                                    } catch (Exception e) {
                                        System.err.println("WARNING: Failed to parse " + entryName + ": " + e.getMessage());
                                    }
                                }
                            }
                        }
                    } catch (IOException e) {
                        System.err.println("WARNING: Failed to read sources JAR: " + sp.getName());
                    }
                }
            } else {
                System.err.println("INFO: sourcesPath provided but not found: " + sourcesPath);
            }
        }

        // 2) Fallback: Extract .java files that may be present inside the main JARs
        for (File jarFile : jarFiles) {
            try (JarFile jar = new JarFile(jarFile)) {
                Enumeration<JarEntry> entries = jar.entries();

                while (entries.hasMoreElements()) {
                    JarEntry entry = entries.nextElement();
                    String entryName = entry.getName();

                    // Look for .java files
                    if (entryName.endsWith(".java")) {
                        try (InputStream inputStream = jar.getInputStream(entry)) {
                            String content = new String(inputStream.readAllBytes());

                            try {
                                CompilationUnit cu = javaParser.parse(content).getResult().orElse(null);
                                if (cu != null) {
                                    // Extract class name from compilation unit; use jar entry as fallback
                                    String className = extractClassNameFromCU(cu, entryName);
                                    if (className != null) {
                                        parsedSources.put(className, cu);
                                    }
                                }
                            } catch (Exception e) {
                                System.err.println("WARNING: Failed to parse " + entryName + ": " + e.getMessage());
                            }
                        }
                    }
                }
            } catch (IOException e) {
                System.err.println("WARNING: Failed to read JAR: " + jarFile.getName());
            }
        }

        return parsedSources;
    }
    
    /**
     * Extract class name from CompilationUnit.
     *
     * @param cu CompilationUnit
     * @return Fully qualified class name
     */
    private static String extractClassNameFromCU(CompilationUnit cu, String fallbackPath) {
        Optional<String> packageName = cu.getPackageDeclaration()
                .map(pd -> pd.getNameAsString());

        Optional<TypeDeclaration<?>> primaryType = cu.getPrimaryType();
        if (primaryType.isPresent()) {
            String className = primaryType.get().getNameAsString();
            return packageName.map(pkg -> pkg + "." + className).orElse(className);
        }

        // If no primary type, try to derive from the fallbackPath (jar entry or relative path)
        if (fallbackPath != null && !fallbackPath.isBlank()) {
            String candidate = fallbackPath.replace('/', '.');
            if (candidate.endsWith(".java")) {
                candidate = candidate.substring(0, candidate.length() - 5);
            }
            // If package declaration exists, prefer it (handles cases where file is nested differently)
            if (packageName.isPresent()) {
                // If candidate already contains package, return it; otherwise combine
                if (candidate.startsWith(packageName.get())) {
                    return candidate;
                } else {
                    // Use simple name from candidate if present
                    int lastDot = candidate.lastIndexOf('.');
                    String simple = lastDot >= 0 ? candidate.substring(lastDot + 1) : candidate;
                    return packageName.get() + "." + simple;
                }
            }

            return candidate;
        }

        return null;
    }
    
    /**
     * Analyze a single class using JavaParser + ASM fallback.
     *
     * @param className Class name to analyze
     * @param parsedSources Parsed source files
     * @param jarFiles JAR files for ASM analysis
     * @return Class information map
     */
    private static BMap<BString, Object> analyzeClassWithJavaParser(
            String className, 
            Map<String, CompilationUnit> parsedSources, 
            List<File> jarFiles) throws Exception {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        BMap<BString, Object> classInfo = ValueCreator.createMapValue(mapType);
        
        // Basic class information
        classInfo.put(StringUtils.fromString("className"), StringUtils.fromString(className));
        
        String packageName = "";
        String simpleName = className;
        if (className.contains(".")) {
            int lastDot = className.lastIndexOf(".");
            packageName = className.substring(0, lastDot);
            simpleName = className.substring(lastDot + 1);
        }
        
        classInfo.put(StringUtils.fromString("packageName"), StringUtils.fromString(packageName));
        classInfo.put(StringUtils.fromString("simpleName"), StringUtils.fromString(simpleName));
        
        // Try JavaParser first (if source available)
        CompilationUnit cu = parsedSources.get(className);
        if (cu != null) {
            return analyzeWithJavaParserSource(className, cu, classInfo);
        }
        
        // Fallback to ASM for bytecode analysis
        return analyzeWithASM(className, jarFiles, classInfo);
    }
    
    /**
     * Analyze class using JavaParser with source code.
     *
     * @param className Class name
     * @param cu CompilationUnit
     * @param classInfo Base class info map
     * @return Complete class information
     */
    private static BMap<BString, Object> analyzeWithJavaParserSource(
            String className, 
            CompilationUnit cu, 
            BMap<BString, Object> classInfo) {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        
        // Try to locate the relevant top-level type declaration.
        // Prefer a type whose simple name matches the className argument, fall back to primary type,
        // then the first top-level type if available.
        String simpleName = className.contains(".") ? className.substring(className.lastIndexOf('.') + 1) : className;
        TypeDeclaration<?> typeDecl = null;

        for (TypeDeclaration<?> td : cu.getTypes()) {
            if (td.getNameAsString().equals(simpleName)) {
                typeDecl = td;
                break;
            }
        }

        if (typeDecl == null) {
            Optional<TypeDeclaration<?>> primaryType = cu.getPrimaryType();
            if (primaryType.isPresent()) {
                typeDecl = primaryType.get();
            } else if (!cu.getTypes().isEmpty()) {
                typeDecl = cu.getTypes().get(0);
            } else {
                return null;
            }
        }
        
        // Basic type information
        classInfo.put(StringUtils.fromString("isInterface"), typeDecl.isClassOrInterfaceDeclaration() && 
                typeDecl.asClassOrInterfaceDeclaration().isInterface());
        classInfo.put(StringUtils.fromString("isAbstract"), typeDecl.hasModifier(Modifier.Keyword.ABSTRACT));
        classInfo.put(StringUtils.fromString("isEnum"), typeDecl.isEnumDeclaration());
        classInfo.put(StringUtils.fromString("isDeprecated"), typeDecl.isAnnotationPresent("Deprecated"));
        
        // Handle enum types
        if (typeDecl.isEnumDeclaration()) {
            EnumDeclaration enumDecl = typeDecl.asEnumDeclaration();
            
            // Extract enum constants
            List<BMap<BString, Object>> fields = new ArrayList<>();
            for (EnumConstantDeclaration enumConst : enumDecl.getEntries()) {
                BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
                fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(enumConst.getNameAsString()));
                fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(className));
                fieldInfo.put(StringUtils.fromString("isStatic"), true);
                fieldInfo.put(StringUtils.fromString("isFinal"), true);
                fieldInfo.put(StringUtils.fromString("isDeprecated"), enumConst.isAnnotationPresent("Deprecated"));
                
                // Javadoc for enum constant
                Optional<JavadocComment> javadoc = enumConst.getJavadocComment();
                if (javadoc.isPresent()) {
                    fieldInfo.put(StringUtils.fromString("javadoc"), 
                            StringUtils.fromString(javadoc.get().getContent()));
                } else {
                    fieldInfo.put(StringUtils.fromString("javadoc"), null);
                }
                
                fields.add(fieldInfo);
            }
            
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            
            // Enums don't have constructors or methods we care about for this use case
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(new BMap[0], 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(new BMap[0], 
                    TypeCreator.createArrayType(mapType)));
            
            classInfo.put(StringUtils.fromString("superClass"), null);
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(new BString[0]));
            
            // Annotations
            String[] annotations = enumDecl.getAnnotations().stream()
                    .map(ann -> ann.getNameAsString())
                    .toArray(String[]::new);
            BString[] annotationsB = new BString[annotations.length];
            for (int i = 0; i < annotations.length; i++) {
                annotationsB[i] = StringUtils.fromString(annotations[i]);
            }
            classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(annotationsB));
            
            return classInfo;
        }
        
        if (typeDecl.isClassOrInterfaceDeclaration()) {
            ClassOrInterfaceDeclaration classDecl = typeDecl.asClassOrInterfaceDeclaration();
            
            // Superclass
            Optional<Type> superclass = classDecl.getExtendedTypes().isEmpty() ? 
                    Optional.empty() : 
                    Optional.of(classDecl.getExtendedTypes().get(0));
            
            if (superclass.isPresent()) {
                String superClassName = superclass.get().asString();
                if (!superClassName.equals("Object")) {
                    classInfo.put(StringUtils.fromString("superClass"), StringUtils.fromString(superClassName));
                } else {
                    classInfo.put(StringUtils.fromString("superClass"), null);
                }
            } else {
                classInfo.put(StringUtils.fromString("superClass"), null);
            }
            
            // Interfaces
            NodeList<ClassOrInterfaceType> implementedTypes = classDecl.getImplementedTypes();
            BString[] interfaceNames = implementedTypes.stream()
                    .map(type -> StringUtils.fromString(type.asString()))
                    .toArray(BString[]::new);
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(interfaceNames));
            
            // Extract methods
            List<BMap<BString, Object>> methods = new ArrayList<>();
            for (MethodDeclaration method : classDecl.getMethods()) {
                if (method.isPublic()) {
                    methods.add(analyzeMethodWithJavaParser(method, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(methods.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            
            // Extract fields
            List<BMap<BString, Object>> fields = new ArrayList<>();
            for (FieldDeclaration field : classDecl.getFields()) {
                if (field.isPublic()) {
                    fields.addAll(analyzeFieldWithJavaParser(field, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            
            // Extract constructors
            List<BMap<BString, Object>> constructors = new ArrayList<>();
            for (ConstructorDeclaration constructor : classDecl.getConstructors()) {
                if (constructor.isPublic()) {
                    constructors.add(analyzeConstructorWithJavaParser(constructor, mapType));
                }
            }
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(constructors.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
        }
        
        // Annotations
        String[] annotations = typeDecl.getAnnotations().stream()
                .map(ann -> ann.getNameAsString())
                .toArray(String[]::new);
        BString[] annotationsB = new BString[annotations.length];
        for (int i = 0; i < annotations.length; i++) {
            annotationsB[i] = StringUtils.fromString(annotations[i]);
        }
        classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(annotationsB));
        
        return classInfo;
    }
    
    /**
     * Analyze method using JavaParser.
     *
     * @param method MethodDeclaration
     * @param mapType Map type for creating values
     * @return Method information map
     */
    private static BMap<BString, Object> analyzeMethodWithJavaParser(
            MethodDeclaration method, MapType mapType) {
        
        BMap<BString, Object> methodInfo = ValueCreator.createMapValue(mapType);
        
        methodInfo.put(StringUtils.fromString("name"), StringUtils.fromString(method.getNameAsString()));
        methodInfo.put(StringUtils.fromString("returnType"), 
                StringUtils.fromString(method.getType().asString()));
        methodInfo.put(StringUtils.fromString("isStatic"), method.isStatic());
        methodInfo.put(StringUtils.fromString("isFinal"), method.isFinal());
        methodInfo.put(StringUtils.fromString("isAbstract"), method.isAbstract());
        methodInfo.put(StringUtils.fromString("isDeprecated"), method.isAnnotationPresent("Deprecated"));
        
        // Javadoc
        Optional<JavadocComment> javadoc = method.getJavadocComment();
        if (javadoc.isPresent()) {
            methodInfo.put(StringUtils.fromString("javadoc"), 
                    StringUtils.fromString(javadoc.get().getContent()));
        } else {
            methodInfo.put(StringUtils.fromString("javadoc"), null);
        }
        
        // Parameters
        List<BMap<BString, Object>> paramList = new ArrayList<>();
        for (Parameter param : method.getParameters()) {
            BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
            paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString(param.getNameAsString()));
            paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(param.getTypeAsString()));
            paramInfo.put(StringUtils.fromString("isVarArgs"), param.isVarArgs());
            
            // Extract request fields if this is a Request parameter
            if (param.getTypeAsString().endsWith("Request")) {
                // This would need additional analysis of the Request class
                // For now, leave it empty - could be enhanced later
                paramInfo.put(StringUtils.fromString("requestFields"), 
                        ValueCreator.createArrayValue(new BMap[0], TypeCreator.createArrayType(mapType)));
            }
            
            paramList.add(paramInfo);
        }
        methodInfo.put(StringUtils.fromString("parameters"),
                ValueCreator.createArrayValue(paramList.toArray(new BMap[0]), 
                TypeCreator.createArrayType(mapType)));
        
        // Exceptions
        String[] exceptionNames = method.getThrownExceptions().stream()
                .map(Type::asString)
                .toArray(String[]::new);
        BString[] exceptionNamesB = new BString[exceptionNames.length];
        for (int i = 0; i < exceptionNames.length; i++) {
            exceptionNamesB[i] = StringUtils.fromString(exceptionNames[i]);
        }
        methodInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNamesB));
        
        return methodInfo;
    }
    
    /**
     * Analyze field using JavaParser.
     *
     * @param field FieldDeclaration
     * @param mapType Map type for creating values
     * @return List of field information maps (one per variable)
     */
    private static List<BMap<BString, Object>> analyzeFieldWithJavaParser(
            FieldDeclaration field, MapType mapType) {
        
        List<BMap<BString, Object>> fields = new ArrayList<>();
        
        for (VariableDeclarator variable : field.getVariables()) {
            BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
            
            fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(variable.getNameAsString()));
            fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(variable.getTypeAsString()));
            fieldInfo.put(StringUtils.fromString("isStatic"), field.isStatic());
            fieldInfo.put(StringUtils.fromString("isFinal"), field.isFinal());
            fieldInfo.put(StringUtils.fromString("isDeprecated"), field.isAnnotationPresent("Deprecated"));
            
            // Javadoc
            Optional<JavadocComment> javadoc = field.getJavadocComment();
            if (javadoc.isPresent()) {
                fieldInfo.put(StringUtils.fromString("javadoc"), 
                        StringUtils.fromString(javadoc.get().getContent()));
            } else {
                fieldInfo.put(StringUtils.fromString("javadoc"), null);
            }
            
            fields.add(fieldInfo);
        }
        
        return fields;
    }
    
    /**
     * Analyze constructor using JavaParser.
     *
     * @param constructor ConstructorDeclaration  
     * @param mapType Map type for creating values
     * @return Constructor information map
     */
    private static BMap<BString, Object> analyzeConstructorWithJavaParser(
            ConstructorDeclaration constructor, MapType mapType) {
        
        BMap<BString, Object> constructorInfo = ValueCreator.createMapValue(mapType);
        
        constructorInfo.put(StringUtils.fromString("isDeprecated"), constructor.isAnnotationPresent("Deprecated"));
        
        // Javadoc
        Optional<JavadocComment> javadoc = constructor.getJavadocComment();
        if (javadoc.isPresent()) {
            constructorInfo.put(StringUtils.fromString("javadoc"), 
                    StringUtils.fromString(javadoc.get().getContent()));
        } else {
            constructorInfo.put(StringUtils.fromString("javadoc"), null);
        }
        
        // Parameters
        List<BMap<BString, Object>> paramList = new ArrayList<>();
        for (Parameter param : constructor.getParameters()) {
            BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
            paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString(param.getNameAsString()));
            paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(param.getTypeAsString()));
            paramInfo.put(StringUtils.fromString("isVarArgs"), param.isVarArgs());
            paramList.add(paramInfo);
        }
        constructorInfo.put(StringUtils.fromString("parameters"),
                ValueCreator.createArrayValue(paramList.toArray(new BMap[0]), 
                TypeCreator.createArrayType(mapType)));
        
        // Exceptions
        String[] exceptionNames = constructor.getThrownExceptions().stream()
                .map(Type::asString)
                .toArray(String[]::new);
        BString[] exceptionNamesB = new BString[exceptionNames.length];
        for (int i = 0; i < exceptionNames.length; i++) {
            exceptionNamesB[i] = StringUtils.fromString(exceptionNames[i]);
        }
        constructorInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNamesB));
        
        return constructorInfo;
    }
    
    /**
     * Analyze class using ASM bytecode analysis (fallback when source not available).
     *
     * @param className Class name
     * @param jarFiles JAR files to search
     * @param classInfo Base class info map
     * @return Complete class information
     */
    private static BMap<BString, Object> analyzeWithASM(
            String className, List<File> jarFiles, BMap<BString, Object> classInfo) throws Exception {
        
        MapType mapType = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);
        
        // Find and analyze class with ASM
        for (File jarFile : jarFiles) {
            try (JarFile jar = new JarFile(jarFile)) {
                String classPath = className.replace('.', '/') + ".class";
                JarEntry entry = jar.getJarEntry(classPath);
                
                if (entry != null) {
                    try (InputStream inputStream = jar.getInputStream(entry)) {
                        ClassReader classReader = new ClassReader(inputStream);
                        
                        ASMClassAnalyzer analyzer = new ASMClassAnalyzer(classInfo, mapType);
                        classReader.accept(analyzer, ClassReader.SKIP_DEBUG);
                        
                        return classInfo;
                    }
                }
            }
        }
        
        // If not found, return basic info
        classInfo.put(StringUtils.fromString("isInterface"), false);
        classInfo.put(StringUtils.fromString("isAbstract"), false);
        classInfo.put(StringUtils.fromString("isEnum"), false);
        classInfo.put(StringUtils.fromString("isDeprecated"), false);
        classInfo.put(StringUtils.fromString("superClass"), null);
        classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(new BString[0]));
        classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(new BString[0]));
        classInfo.put(StringUtils.fromString("methods"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        classInfo.put(StringUtils.fromString("fields"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        classInfo.put(StringUtils.fromString("constructors"), ValueCreator.createArrayValue(new BMap[0], 
                TypeCreator.createArrayType(mapType)));
        
        return classInfo;
    }
    
    /**
     * Check if class should be included in analysis.
     *
     * @param className Class name
     * @return True if should be included
     */
    private static boolean shouldIncludeClass(String className) {
        // Skip inner classes
        if (className.contains("$")) {
            return false;
        }
        
        // Skip excluded packages
        for (String excludedPackage : EXCLUDED_PACKAGES) {
            if (className.startsWith(excludedPackage + ".")) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * ASM ClassVisitor for analyzing bytecode.
     */
    private static class ASMClassAnalyzer extends ClassVisitor {
        
        private final BMap<BString, Object> classInfo;
        private final MapType mapType;
        private final List<BMap<BString, Object>> methods = new ArrayList<>();
        private final List<BMap<BString, Object>> fields = new ArrayList<>();
        private final List<BMap<BString, Object>> constructors = new ArrayList<>();
        private boolean isEnum = false;
        private String enumClassName = "";
        
        public ASMClassAnalyzer(BMap<BString, Object> classInfo, MapType mapType) {
            super(Opcodes.ASM9);
            this.classInfo = classInfo;
            this.mapType = mapType;
        }
        
        @Override
        public void visit(int version, int access, String name, String signature, 
                String superName, String[] interfaces) {
            
            // Class type information
            boolean isInterface = (access & Opcodes.ACC_INTERFACE) != 0;
            boolean isAbstract = (access & Opcodes.ACC_ABSTRACT) != 0;
            this.isEnum = (access & Opcodes.ACC_ENUM) != 0;
            this.enumClassName = name.replace('/', '.');
            
            classInfo.put(StringUtils.fromString("isInterface"), isInterface);
            classInfo.put(StringUtils.fromString("isAbstract"), isAbstract);
            classInfo.put(StringUtils.fromString("isEnum"), this.isEnum);
            
            // Superclass
            if (superName != null && !superName.equals("java/lang/Object")) {
                classInfo.put(StringUtils.fromString("superClass"), 
                        StringUtils.fromString(superName.replace('/', '.')));
            } else {
                classInfo.put(StringUtils.fromString("superClass"), null);
            }
            
            // Interfaces
            BString[] interfaceNames = new BString[interfaces.length];
            for (int i = 0; i < interfaces.length; i++) {
                interfaceNames[i] = StringUtils.fromString(interfaces[i].replace('/', '.'));
            }
            classInfo.put(StringUtils.fromString("interfaces"), ValueCreator.createArrayValue(interfaceNames));
        }
        
        @Override
        public org.objectweb.asm.FieldVisitor visitField(int access, String name, String descriptor, 
                String signature, Object value) {
            
            // For enums, extract enum constants (public static final fields of the enum type)
            if (isEnum && (access & Opcodes.ACC_PUBLIC) != 0 && 
                (access & Opcodes.ACC_STATIC) != 0 && (access & Opcodes.ACC_FINAL) != 0 &&
                (access & Opcodes.ACC_ENUM) != 0) {
                
                BMap<BString, Object> fieldInfo = ValueCreator.createMapValue(mapType);
                fieldInfo.put(StringUtils.fromString("name"), StringUtils.fromString(name));
                fieldInfo.put(StringUtils.fromString("type"), StringUtils.fromString(enumClassName));
                fieldInfo.put(StringUtils.fromString("isStatic"), true);
                fieldInfo.put(StringUtils.fromString("isFinal"), true);
                fieldInfo.put(StringUtils.fromString("isDeprecated"), false);
                fieldInfo.put(StringUtils.fromString("javadoc"), null);
                fields.add(fieldInfo);
            }
            
            return null;
        }
        
        @Override
        public MethodVisitor visitMethod(int access, String name, String descriptor, 
                String signature, String[] exceptions) {
            
            // Only include public methods
            if ((access & Opcodes.ACC_PUBLIC) != 0) {
                BMap<BString, Object> methodInfo = ValueCreator.createMapValue(mapType);
                
                methodInfo.put(StringUtils.fromString("name"), StringUtils.fromString(name));
                methodInfo.put(StringUtils.fromString("returnType"), 
                        StringUtils.fromString(extractReturnTypeFromDescriptor(descriptor)));
                methodInfo.put(StringUtils.fromString("isStatic"), (access & Opcodes.ACC_STATIC) != 0);
                methodInfo.put(StringUtils.fromString("isFinal"), (access & Opcodes.ACC_FINAL) != 0);
                methodInfo.put(StringUtils.fromString("isAbstract"), (access & Opcodes.ACC_ABSTRACT) != 0);
                methodInfo.put(StringUtils.fromString("isDeprecated"), false); // Would need annotation analysis
                methodInfo.put(StringUtils.fromString("javadoc"), null);
                
                // Basic parameter extraction from descriptor
                String[] paramTypes = extractParameterTypesFromDescriptor(descriptor);
                List<BMap<BString, Object>> params = new ArrayList<>();
                for (int i = 0; i < paramTypes.length; i++) {
                    BMap<BString, Object> paramInfo = ValueCreator.createMapValue(mapType);
                    paramInfo.put(StringUtils.fromString("name"), StringUtils.fromString("arg" + i));
                    paramInfo.put(StringUtils.fromString("type"), StringUtils.fromString(paramTypes[i]));
                    paramInfo.put(StringUtils.fromString("isVarArgs"), false);
                    params.add(paramInfo);
                }
                methodInfo.put(StringUtils.fromString("parameters"),
                        ValueCreator.createArrayValue(params.toArray(new BMap[0]), 
                        TypeCreator.createArrayType(mapType)));
                
                // Exceptions
                BString[] exceptionNames = new BString[exceptions == null ? 0 : exceptions.length];
                if (exceptions != null) {
                    for (int i = 0; i < exceptions.length; i++) {
                        exceptionNames[i] = StringUtils.fromString(exceptions[i].replace('/', '.'));
                    }
                }
                methodInfo.put(StringUtils.fromString("exceptions"), ValueCreator.createArrayValue(exceptionNames));
                
                if (name.equals("<init>")) {
                    constructors.add(methodInfo);
                } else {
                    methods.add(methodInfo);
                }
            }
            
            return null;
        }
        
        @Override
        public void visitEnd() {
            // Set collected methods, fields, constructors
            classInfo.put(StringUtils.fromString("methods"),
                    ValueCreator.createArrayValue(methods.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("fields"),
                    ValueCreator.createArrayValue(fields.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            classInfo.put(StringUtils.fromString("constructors"),
                    ValueCreator.createArrayValue(constructors.toArray(new BMap[0]), 
                    TypeCreator.createArrayType(mapType)));
            
            // Default values
            classInfo.put(StringUtils.fromString("isDeprecated"), false);
            classInfo.put(StringUtils.fromString("annotations"), ValueCreator.createArrayValue(new BString[0]));
        }
        
        private String extractReturnTypeFromDescriptor(String descriptor) {
            int returnStart = descriptor.indexOf(')') + 1;
            return descriptorToClassName(descriptor.substring(returnStart));
        }
        
        private String[] extractParameterTypesFromDescriptor(String descriptor) {
            String params = descriptor.substring(1, descriptor.indexOf(')'));
            List<String> types = new ArrayList<>();
            
            int i = 0;
            while (i < params.length()) {
                char c = params.charAt(i);
                if (c == 'L') {
                    int end = params.indexOf(';', i);
                    types.add(descriptorToClassName(params.substring(i, end + 1)));
                    i = end + 1;
                } else if (c == '[') {
                    int start = i;
                    while (i < params.length() && params.charAt(i) == '[') {
                        i++;
                    }
                    if (i < params.length()) {
                        if (params.charAt(i) == 'L') {
                            int end = params.indexOf(';', i);
                            types.add(descriptorToClassName(params.substring(start, end + 1)));
                            i = end + 1;
                        } else {
                            types.add(descriptorToClassName(params.substring(start, i + 1)));
                            i++;
                        }
                    }
                } else {
                    types.add(descriptorToClassName(String.valueOf(c)));
                    i++;
                }
            }
            
            return types.toArray(new String[0]);
        }
        
        private String descriptorToClassName(String descriptor) {
            switch (descriptor) {
                case "V": return "void";
                case "Z": return "boolean";
                case "B": return "byte";
                case "C": return "char";
                case "S": return "short";
                case "I": return "int";
                case "J": return "long";
                case "F": return "float";
                case "D": return "double";
                default:
                    if (descriptor.startsWith("L") && descriptor.endsWith(";")) {
                        return descriptor.substring(1, descriptor.length() - 1).replace('/', '.');
                    } else if (descriptor.startsWith("[")) {
                        return descriptorToClassName(descriptor.substring(1)) + "[]";
                    }
                    return descriptor;
            }
        }
    }
    
    // Overload to accept Ballerina BString
    public static Object analyzeJarWithJavaParser(BString jarPath) {
        if (jarPath == null) {
            return null;
        }
        return analyzeJarWithJavaParser(jarPath.getValue());
    }
}