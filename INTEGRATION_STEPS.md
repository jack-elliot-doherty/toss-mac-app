# Quick Integration Steps

## 🎯 Add New Files to Xcode (Required!)

The following files were created but need to be added to your Xcode project:

### Files to Add:
```
Toss/App/Overlay/
├── ToolCall.swift (NEW)
├── AgentStreamParser.swift (NEW)
└── SlackMessageCard.swift (NEW)
```

### Steps:

1. **Open Xcode**
   ```bash
   open /Users/jackdoherty/code/toss/toss-mac-app/Toss/Toss.xcodeproj
   ```

2. **In Xcode Navigator:**
   - Expand `Toss` → `App` → `Overlay`
   - Right-click on `Overlay` folder
   - Select **"Add Files to Toss..."**

3. **Select Files:**
   - Navigate to `/Users/jackdoherty/code/toss/toss-mac-app/Toss/App/Overlay/`
   - Select:
     - ✅ `ToolCall.swift`
     - ✅ `AgentStreamParser.swift`
     - ✅ `SlackMessageCard.swift`
   - **Important**: Check "Add to targets: Toss"
   - Click **"Add"**

4. **Verify:**
   - Files should appear in Overlay folder
   - They should have the Toss target checkbox checked
   - Build the project (`Cmd+B`)

## 🔧 Update Input Handler (Connect to Streaming)

The `AgentView` currently calls `sendMessage()` which uses the old endpoint. Update it to use streaming:

**In `AgentView.swift` line 84:**

Change:
```swift
viewModel.sendMessage(inputText)
```

To:
```swift
Task {
    await viewModel.sendMessageStreaming(inputText)
}
```

## 🧪 Quick Test

### 1. Start the Server:
```bash
cd /Users/jackdoherty/code/toss/toss-server
bun run dev
```

### 2. Build & Run App:
- In Xcode: `Cmd+R`
- Open agent panel
- Type: "Send hello to #engineering in Slack"
- Should see translucent panel with Slack approval card!

## 🎨 What You'll See

✨ **Before (opaque white background):**
```
┌─────────────────────────┐
│  Agent         [X]      │  ← White background
├─────────────────────────┤
│ User: Hello             │
│ Agent: How can I help?  │
└─────────────────────────┘
```

🌟 **After (translucent dark glass):**
```
╔═════════════════════════╗
║  ✨ Agent       [X]     ║  ← Dark frosted glass
╟─────────────────────────╢
║ User: Send to Slack     ║  ← White text
║                         ║
║ ┌─────────────────────┐ ║
║ │ 💬 Send Slack Msg   │ ║  ← Approval card
║ │ Channel: #eng       │ ║
║ │ Message: Hello!     │ ║
║ │  [Reject] [Send ✓]  │ ║
║ └─────────────────────┘ ║
╚═════════════════════════╝
     ↑ Invisible to screen recordings!
```

## 🐛 Common Issues

### "Cannot find type ToolCall"
- **Fix**: Files not added to Xcode project. Follow steps above.

### "Stream never completes"
- **Fix**: The AI SDK stream format might differ. Check server logs.
- **Workaround**: The legacy `/agent/message` endpoint still works.

### "Nothing appears in UI"
- **Fix**: Make sure `sendMessageStreaming()` is called, not `sendMessage()`
- **Check**: Server is running and endpoint returns SSE events

### "Screen recording shows the window"
- **Fix**: Make sure `panel.sharingType = .none` is set in `AgentPanelController.swift` (line 31)

## 📞 Next: Connect to Pill

Currently the agent window is standalone. To connect it to the pill:

1. **In AppDelegate** (where pill command is handled):
   ```swift
   // When user sends agent command (not just dictation)
   agentPanelController.show(with: transcribedText)
   ```

2. **Auto-hide when complete**:
   - In `AgentViewModel`, when stream emits `.done`
   - Call `agentPanelController.hide()`

3. **Handle ESC key**:
   - Already implemented in panel controller
   - Test by pressing ESC when panel is open

## 🎉 You're Done!

The ephemeral agent window is ready to use. It's:
- ✅ Translucent and beautiful
- ✅ Dark mode optimized  
- ✅ Invisible to screen recordings
- ✅ Shows purpose-built tool approval cards
- ✅ Dynamically sized with scrolling
- ✅ Ready for more tool integrations

See `IMPLEMENTATION_SUMMARY.md` for full details and future enhancements!

