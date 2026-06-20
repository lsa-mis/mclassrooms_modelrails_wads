---
title: Project Tools
description: Registering and toggling per-project tools via the extensible ProjectTools::Registry.
keywords: project tools registry toggle enabled_tools onboarding tabs EnforcesProjectTool
audience: [guide, technical]
---

# Project tools

Each project has a set of enabled **tools**. The base template ships one tool —
**Docs** (the `Resource`/`Document` surface). Add your own through the registry.

## Register a tool

1. Build the tool's surface: model, controller, routes, views — a project-scoped
   route helper like `workspace_project_messages_path(workspace, project)`.

2. Register it in `config/initializers/project_tools.rb`:

   ```ruby
   ProjectTools::Registry.register(
     key: :messages,
     path_helper: :workspace_project_messages_path,
     default_enabled: true
   )
   ```

3. (Optional) Guard the tool's controller so disabled projects can't reach it:

   ```ruby
   include EnforcesProjectTool
   enforces_tool :messages   # place after the before_action that sets @project
   ```

4. Add `project_tools.messages.{name,description}` locale keys.

The tool now appears as a project-home tab (when enabled), in the project tools
settings toggle, and — once more than one tool is toggleable — in the onboarding
"Pick your tools" step. Per-project state lives in `projects.enabled_tools`.
