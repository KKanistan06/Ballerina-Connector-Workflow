# JavaPhaser — AI-powered Ballerina connector automation

AI-powered automation that analyzes Java SDK JARs and produces structured metadata to help generate Ballerina connectors. The core analyzer is in `modules/sdkanalyzer`.

Configuration
- Optional: set `ANTHROPIC_API_KEY` to enable LLM-based scoring and ranking. If not set, the analyzer uses heuristic fallbacks.

Build
```bash
cd /home/kanistan/JavaPhaser
bal build
```

Run (example)
```bash
bal run -- analyze <path-to-jar-or-mvn-ref> <output-dir>
```
Example:
```bash
bal run -- analyze test-jars/aws-s3-2.25.16.jar ./output
```

Outputs
- JSON metadata: `./output/<sdkname>-metadata.json`
- Human report: `./output/analysis-report.txt`

Modules
- `modules/sdkanalyzer/` — SDK analyzer and connector-generation helpers

That's it — build, run, and inspect the output files. If you want examples or an expanded guide, I can add one.
