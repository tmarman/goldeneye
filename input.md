An agent system for Apple devices, supporting long-running tasks like deep research, trip planning, and general productivity. 

File based, so everything is stored and versioned in iCloud.

Implements Agentic Context Engineering (ACE) https://arxiv.org/abs/2510.04618

Supports ACP & A2A for interoperability
* [Discussion of merger](https://github.com/orgs/i-am-bee/discussions/)
* https://developers.googleblog.com/en/a2a-a-new-era-of-agent-interoperability/
* https://github.com/a2aproject/A2A

Look at porting Claude's Agent SDK, Microsoft Agent Framework, Gemini CLI orchestration into 

DO anything, built anything with AgentKit for Apple ecosystem, with cloud agents running in Private Cloud Compute


Goals: 
Build this for acquisition by Apple, so assume it's something Apple will build. Deep integration with the Apple ecosystem, a business model based on subscriptions and agent completion. At Apple this will help monetize PCC infrastructure and mark a shift towards Apple OS as "LLM-first, Agent-first". 
Layered building blocks for both developers to build agentic systems (building on AppIntents and MCP work for tool use).
Model-agnostic, supporting both local and remote services.
Agent-agnostic - while we will support some native and direct LLM calls and orchestration, we want to support seamless handoff and interoperability with existing protocols, interfaces, and complete agents like Claude Code and Codex for task completion.