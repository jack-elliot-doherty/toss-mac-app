# Ephemeral Agent Window Implementation Summary

## ✅ What We've Built

### Phase 1: Translucent UI (COMPLETE)
**Files Modified:**
- `Toss/App/Overlay/AgentView.swift` - Updated with translucent materials and dark mode
- `Toss/App/Overlay/AgentPanelController.swift` - Added screen recording exclusion
- `Toss/App/Overlay/AgentViewModel.swift` - Added MessageRole enum

**Changes:**
- ✅ Replaced solid backgrounds with `.ultraThinMaterial` for frosted glass effect
- ✅ Updated to dark mode colors (white text, semi-transparent backgrounds)
- ✅ Added `panel.sharingType = .none` to exclude from screen recording/screenshots
- ✅ Dynamic height with max 500px and scrolling
- ✅ Beautiful shadow and rounded corners

### Phase 2: Server Streaming Endpoint (COMPLETE)
**Files Created:**
- `toss-server/src/agent.ts` - AI SDK tools and streaming logic

**Files Modified:**
- `toss-server/src/index.ts` - Added `/agent/chat` streaming endpoint
- `toss-server/package.json` - Added `ai` and `@ai-sdk/openai` packages

**Features:**
- ✅ Vercel AI SDK installed and configured
- ✅ Tool definitions for: `send_slack_message`, `get_granola_notes`, `create_linear_issue`
- ✅ Server-Sent Events (SSE) streaming
- ✅ Legacy `/agent/message` endpoint kept for backwards compatibility

### Phase 3: Client Streaming & Tool Models (COMPLETE)
**Files Created:**
- `Toss/App/Overlay/ToolCall.swift` - Tool call models and status enum
- `Toss/App/Overlay/AgentStreamParser.swift` - SSE stream parser

**Files Modified:**
- `Toss/App/Overlay/AgentViewModel.swift` - Added streaming support and tool approval

**Features:**
- ✅ `ToolCall` model with status tracking
- ✅ `AnyCodable` helper for dynamic JSON arguments
- ✅ Stream parser for AI SDK format
- ✅ `sendMessageStreaming()` method with async/await
- ✅ Tool approval/rejection methods
- ✅ Automatic distinction between read-only and mutation tools

### Phase 4: Slack Approval Card UI (COMPLETE)
**Files Created:**
- `Toss/App/Overlay/SlackMessageCard.swift` - Purpose-built Slack message approval UI

**Files Modified:**
- `Toss/App/Overlay/AgentView.swift` - Added tool approval card rendering

**Features:**
- ✅ Beautiful dark-themed Slack approval card
- ✅ Shows channel and message preview
- ✅ Approve/Reject buttons with loading states
- ✅ Error and completion state displays
- ✅ Generic fallback card for other tools
- ✅ Tool router component that switches based on tool name

## 📋 What Needs to Be Done

### 1. Add New Files to Xcode Project
The following files were created but need to be added to the Xcode project:

**Required Steps:**
1. Open `Toss.xcodeproj` in Xcode
2. Right-click on the `App/Overlay` folder
3. Select "Add Files to Toss..."
4. Add these files:
   - `ToolCall.swift`
   - `AgentStreamParser.swift`
   - `SlackMessageCard.swift`
5. Ensure they're added to the Toss target

### 2. Fix Stream Parsing (Important!)
The current `AgentStreamParser.streamEvents()` method uses a simple approach that might not work well for real-time SSE. 

**Options:**
- **Option A**: Use a third-party SSE library for Swift
- **Option B**: Implement proper URLSession delegate-based streaming
- **Option C**: Use WebSocket instead of SSE

The current implementation will work for testing but might need refinement.

### 3. Implement Actual Tool Execution
Currently, `approveToolCall()` just simulates execution. You need to:

1. Send approval to server with tool call ID
2. Server actually executes the tool (send to Slack, create Linear issue, etc.)
3. Return result to client

**Suggested API:**
```
POST /agent/tool/approve
{
  "toolCallId": "call_123",
  "approved": true
}
```

### 4. Build Linear Issue Card
Create `LinearIssueCard.swift` similar to `SlackMessageCard.swift` with:
- Title and description fields
- Team/Project dropdowns
- Priority/Assignee selectors
- Screenshot preview (if applicable)

### 5. Implement Granola Integration
The `get_granola_notes` tool currently returns mock data. Implement actual Granola API integration.

### 6. Connect to Pill
Currently the AgentView is standalone. You need to:
1. Trigger AgentView when user sends command to agent (not just dictation)
2. Ensure proper lifecycle (show when agent working, hide when done)
3. Handle ESC key to close

## 🎨 Visual Results

You should now see:
- **Translucent dark panel** with frosted glass effect
- **White text** on semi-transparent backgrounds
- **Beautiful shadows** and rounded corners
- **Smooth scrolling** with max 500px height
- **Purpose-built approval cards** for Slack messages
- **Invisible to screen recordings** (critical for meeting recordings)

## 🧪 Testing

### Test the Server:
```bash
cd toss-server
bun run dev
```

### Test with curl:
```bash
curl -X POST http://localhost:8787/agent/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "messages": [
      {"role": "user", "content": "Send a message to #engineering saying the deploy is ready"}
    ]
  }'
```

### Test in the App:
1. Build and run the Toss app
2. Open the agent panel
3. Type: "Send a message to #engineering saying hello"
4. You should see the Slack approval card appear
5. Click "Send Message" to approve

## 📝 Notes

### Color Scheme
- All backgrounds use `.ultraThinMaterial` or `.regularMaterial`
- Text is white (`Color.white`) for dark mode
- Accents use system colors (`.blue`, `.red`, `.green`)
- Borders use `.white.opacity(0.15)` for subtle separation

### Architecture
- **Streaming**: Uses Vercel AI SDK on server, custom parser on client
- **Tool Approval**: Tracked via `ToolCallStatus` enum
- **UI Routing**: `ToolApprovalCard` switches based on tool name
- **Read vs Mutation**: Automatically detected via `requiresApproval` property

### Future Enhancements
- Add more tool cards (Linear, GitHub, etc.)
- Implement tool execution on server
- Add keyboard shortcuts (Enter to approve, Esc to reject)
- Add "Always allow" setting per tool
- Add tool execution history/logs
- Implement retry on failure
- Add cost tracking for LLM calls

## 🚀 Next Steps

1. **Add files to Xcode** (5 minutes)
2. **Build and test** (10 minutes)
3. **Fix any compilation errors** (variable)
4. **Test streaming endpoint** (10 minutes)
5. **Implement real tool execution** (1-2 hours)
6. **Build Linear card** (30 minutes)
7. **Polish and iterate** (ongoing)

The foundation is solid - you now have a beautiful, translucent, ephemeral agent window with tool approval UI that's invisible to screen recordings! 🎉

