# Apple Intelligence Chat

A native macOS chat app for models that run on your own hardware: Apple's on-device model through the [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels), and any server that speaks the OpenAI API, such as Ollama, llama.cpp or LM Studio.

This is a fork of [PallavAg/Apple-Intelligence-Chat](https://github.com/PallavAg/Apple-Intelligence-Chat). Upstream is a single-conversation demo of the Foundation Models framework; the fork turns it into an app for daily use. [What the fork adds](#what-the-fork-adds) lists the differences.

## Features

**Conversations**

- Any number of conversations, stored on the Mac, in a sidebar grouped by day, with search, pinning and renaming.
- Replies rendered as Markdown: headings, nested lists, quotes, tables, and code blocks with syntax highlighting, their language and a Copy button.
- Streaming answers with Stop, Regenerate, and an inline Try Again where an answer failed.
- Each reply records which model wrote it; hover a reply to see it.

**Models**

- One menu beside the Send button lists the on-device model and every model of the configured server. Picking one switches provider and model in a single step.
- A new conversation says who will answer and where your text goes: nowhere, to a server on this Mac, or to a named host.

**Across the system**

- **Quick Ask** — press ⌃⌥Space in any app for a floating panel.
- **Services** — select text in any app, then *Services › Rewrite / Summarize / Translate with Local Model*, or *Ask Local Model…*. The prompts behind them are editable.
- A menu-bar item runs the same actions on the clipboard.

**Speech**

- Dictate a prompt. Recognition stays on the device for languages macOS can recognize locally; for others the audio goes to Apple's speech service.
- Replies are read aloud without their markup or code. *Automatic* uses the system voice for the system's language — including a Siri voice chosen in System Settings, which works although macOS does not list it to apps — and the best installed voice for any other language.
- Optionally through a speech server with OpenAI's `/audio/speech` endpoint: OpenAI, [Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI), [Speaches](https://github.com/speaches-ai/speaches), LocalAI.

## Requirements

- macOS 26 or later; developed and tested on macOS 27.
- A Mac that supports Apple Intelligence, with it turned on, for the on-device model. The app also works with a server alone.
- Xcode 26 or later to build.

The project still declares iOS and visionOS as platforms, as upstream does. The fork has only been built and run on macOS.

## Build and install

```bash
git clone https://github.com/secondtruth/Apple-Intelligence-Chat.git
cd Apple-Intelligence-Chat
xcodebuild -project "Apple Intelligence Chat.xcodeproj" \
  -scheme "Apple Intelligence Chat" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build build
```

The app is then at `build/Build/Products/Release/Apple Intelligence Chat.app`; copy it to `/Applications`. Building in Xcode works the same way. Either way, set your own development team under *Signing & Capabilities* first — the project carries the maintainer's.

The first build fetches one package, [HighlightSwift](https://github.com/appstefan/HighlightSwift), for syntax highlighting.

`xcodebuild` may print an error about the `DVTCoreDeviceCore` plug-in and a CoreSimulator version warning. Both are unrelated to macOS builds.

## Using a server

Start the server, for Ollama:

```bash
ollama serve
```

The default address, `http://localhost:11434/v1`, is already set. For another server, open *Settings › Chat Server* and enter its base URL, and an API key if it wants one; the key is kept in the Keychain. The pane shows whether the server answers and how many models it offers. Those models then appear in the menu beside the Send button.

A speech server is configured separately under *Settings › Speech Server*, because chat servers such as Ollama do not synthesize speech. Then choose *Speech Server* under *Settings › Read Aloud*.

## Privacy

With the on-device model nothing you type leaves the Mac. With a server, your messages go to the address you configured and nowhere else; the same holds for replies sent to a speech server. Conversations are stored in the app's sandbox container. The app has no analytics and no account.

## Development

```
Apple Intelligence Chat/
  Providers/    ChatProvider protocol, the on-device and the OpenAI-compatible provider, ProviderRegistry
  Store/        ConversationStore (persistence, grouping, search), ChatEngine (streaming, stop, regenerate)
  Models/       Conversation, ChatMessage
  Views/        chat pane, sidebar, model picker, empty state, quick-ask panel, menu-bar item
  Markdown/     MarkdownDocument (parser model), MarkdownView, code highlighting
  Speech/       speech engines, voice selection, SpeechOutputController
  Settings/     the Settings window: a sidebar of panes
  TextActions/  Services entries, prompt library, global hotkey
Tests/          checks that run without an Xcode test target
```

The Markdown model is checked by a script rather than a test target:

```bash
swiftc -parse-as-library "Apple Intelligence Chat/Markdown/MarkdownDocument.swift" \
  Tests/markdown-check.swift -o "$TMPDIR/markdown-check" && "$TMPDIR/markdown-check"
```

Two things that are easy to break:

- Each Services entry in `Info.plist` needs its `NSRequiredContext` key, even empty. Without it macOS hides the entry without saying so.
- Fields added to `Conversation` or `ChatMessage` must be optional. The store ignores a file it cannot decode, so a required field would make existing conversations disappear on the next launch.

## What the fork adds

Upstream offers one conversation with the on-device model, streaming, and settings for temperature and system instructions. The fork adds stored conversations with a sidebar, the provider abstraction and OpenAI-compatible servers, the combined model menu, Markdown rendering with syntax highlighting, Quick Ask, the Services entries and the menu-bar item, dictation, reading aloud with voice selection and speech servers, and the Settings window.

## License

[MIT](LICENSE), as upstream. Copyright © 2025 Pallav Agarwal; changes in this fork © their authors.

## Acknowledgments

[Pallav Agarwal](https://github.com/PallavAg) for the original app, and [HighlightSwift](https://github.com/appstefan/HighlightSwift) with [highlight.js](https://highlightjs.org) for the code colours.
