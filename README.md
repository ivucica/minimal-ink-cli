Here is a thread for a question I asked from DeepWiki:

======
# DeepWiki Q&A with Code Context for Repository: google-gemini/gemini-cli
## Q1
What UI library is used in gemini CLI? How can I use it myself? What does a minimal example look like, for e.g. entering a name in a form and getting back 'Hello <name>'?
### Answer
## UI Library Used

Gemini CLI uses **Ink** - a React library for building command-line interfaces. The project combines React components with Ink's rendering system to create an interactive terminal UI gemini-cli:15-16 .

The main entry point imports both React and Ink's render function gemini-cli:7-8 .

## How to Use Ink Yourself

To use Ink in your own projects:

1. Install Ink: `npm install ink`
2. Create React components that render to the terminal
3. Use Ink's `render()` function to mount your app

## Minimal Example: Name Form

Here's a minimal example that creates a form asking for a name and returns "Hello <name>":

```jsx
import React, { useState } from 'react';
import { render, Text, Box, TextInput } from 'ink';

const NameForm = () => {
  const [name, setName] = useState('');
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = () => {
    if (name.trim()) {
      setSubmitted(true);
    }
  };

  if (submitted) {
    return <Text color="green">Hello {name}!</Text>;
  }

  return (
    <Box flexDirection="column">
      <Text>Please enter your name:</Text>
      <TextInput
        value={name}
        onChange={setName}
        onSubmit={handleSubmit}
        placeholder="Your name"
      />
    </Box>
  );
};

// Render the app
render(<NameForm />);
```

This example demonstrates:
- Using `useState` for state management
- `TextInput` for user input
- Conditional rendering based on submission state
- Basic layout with `Box` and `Text` components

The pattern is similar to how Gemini CLI handles user input in its `InputPrompt` component, but simplified for demonstration purposes gemini-cli:681-684 .

## Notes

- Ink uses React's component model but renders to terminal instead of DOM
- Components like `Box`, `Text`, and `TextInput` are Ink's equivalents of HTML elements
- The `render()` function mounts your React tree to the terminal
- Gemini CLI's architecture shows more complex patterns with contexts, providers, and streaming responses built on top of this foundation gemini-cli:88-112 

Wiki pages you might want to explore:
- [Architecture Overview (google-gemini/gemini-cli)](/wiki/google-gemini/gemini-cli#1.1)
### Citations
**File:** GEMINI.md (L15-16)
```markdown
  - **UI Framework:** React (using [Ink](https://github.com/vadimdemedes/ink)
    for CLI rendering)
```
**File:** packages/cli/src/gemini.tsx (L7-8)
```typescript
import React from 'react';
import { render } from 'ink';
```
**File:** packages/cli/src/gemini.tsx (L88-112)
```typescript
import { SettingsContext } from './ui/contexts/SettingsContext.js';
import { MouseProvider } from './ui/contexts/MouseContext.js';
import { StreamingState } from './ui/types.js';
import { computeTerminalTitle } from './utils/windowTitle.js';

import { SessionStatsProvider } from './ui/contexts/SessionContext.js';
import { VimModeProvider } from './ui/contexts/VimModeContext.js';
import { KeypressProvider } from './ui/contexts/KeypressContext.js';
import { useKittyKeyboardProtocol } from './ui/hooks/useKittyKeyboardProtocol.js';
import {
  relaunchAppInChildProcess,
  relaunchOnExitCode,
} from './utils/relaunch.js';
import { loadSandboxConfig } from './config/sandboxConfig.js';
import { deleteSession, listSessions } from './utils/sessions.js';
import { createPolicyUpdater } from './config/policy.js';
import { ScrollProvider } from './ui/contexts/ScrollProvider.js';
import { isAlternateBufferEnabled } from './ui/hooks/useAlternateBuffer.js';
import { TerminalProvider } from './ui/contexts/TerminalContext.js';
import { OverflowProvider } from './ui/contexts/OverflowContext.js';

import { setupTerminalAndTheme } from './utils/terminalTheme.js';
import { profiler } from './ui/components/DebugProfiler.js';
import { runDeferredCommand } from './deferred.js';
import { SlashCommandConflictHandler } from './services/SlashCommandConflictHandler.js';
```
**File:** packages/cli/src/ui/hooks/useGeminiStream.ts (L681-684)
```typescript
      if (typeof query === 'string') {
        const trimmedQuery = query.trim();
        await logger?.logMessage(MessageSenderType.USER, trimmedQuery);

```
======

Please write step by step process on creating a brand new Ink app like the above, on a blank minimal install Debian stable machine. Prepare a shell script that installs the tools (npm / yarn, node) and creates the directory structure. Prepare a Docker file that uses this shell script as part of the build process: base image is a debian stable image, then the shell script is copied in and is used to install dependencies; the script is used to fetch whatever is needed using yarn or npm and directory structure is created; then the demo file is copied in; then a build step is run; then finally the CLI is run inside the container. Provide the correct commands to build and to run (docker build ..., and then docker run --rm -it ...). I will want to git init + git add filea fileb filec +  git commit -m "some commit message" too.

/////////////////////////

Here are the files required to build and execute your React Ink application inside a minimal Debian container.

Note a slight adjustment to the snippet you provided: in the modern Ink ecosystem, `<TextInput>` is decoupled into its own module (`ink-text-input`), so the setup script installs it and the demo code is updated to import it correctly to prevent compilation errors.

### Step-by-Step Execution Commands

Save the three files above (`setup.sh`, `Dockerfile`, and `app.tsx`) into an empty directory on your host machine. Then, execute the following terminal commands to initialize your Git repository, build the Docker image, and run the CLI interface interactively.

**1. Initialize Git and Commit:**

```bash
git init
git add setup.sh Dockerfile app.tsx
git commit -m "feat: initial commit of minimal React Ink CLI app"

**2. Build the Docker Image:**
```bash
# This uses the Dockerfile to run the shell script, copy the file, and build the TS code.
docker build -t minimal-ink-cli .

**3. Run the CLI in the Container:**
```bash
# The -it flags are strictly required here to attach your terminal's TTY to the container,
# which allows Ink to intercept keypresses and render properly.
docker run --rm -it minimal-ink-cli

```
