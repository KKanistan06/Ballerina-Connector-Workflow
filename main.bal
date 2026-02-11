import wso2/connector_automation.sdkanalyzer as analyzer;

public function main(string... args) returns error? {
    // Delegate to the executeSdkAnalyzer function in the sdkanalyzer module
    return analyzer:executeSdkAnalyzer(...args);
}