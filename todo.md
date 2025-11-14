# Toss Product Roadmap

## 🎯 Product Vision
Handle 2-5 minute tasks that fall between "too small to document" and "too big to do immediately"
- Always-accessible background agent
- Zero-friction voice interaction (hold Fn)
- Auto-detect tasks from meetings
- Ephemeral post-meeting window with suggested tasks

---

## 🔧 Phase 1: Polish & Reliability (Current Priority)
**Goal**: Build confidence - every interaction should feel reliable and predictable

### State Management & Recovery
- [ ] Fix meeting recording stuck states
  - [ ] Add timeout/recovery for stuck meetings
  - [ ] Add state validation on app launch (detect orphaned recordings)
  - [ ] Add explicit cleanup paths for all error states
  - [ ] Add state persistence/recovery (survive app crashes)
- [ ] Improve state transition reliability
  - [ ] Add explicit error handling for all async operations
  - [ ] Add state validation before transitions
  - [ ] Add recovery UI (e.g., "Meeting stuck? Force stop")
  - [ ] Add logging/telemetry for state transitions

### Agent UI Polish
- [ ] Fix agent window resizing
  - [ ] Window should dynamically resize to fit messages
  - [ ] Handle long messages gracefully (wrap + scroll)
  - [ ] Fix initial sizing when opening with message
  - [ ] Add max height with scrolling
- [ ] Improve agent UX
  - [ ] Better loading states
  - [ ] Error states with retry
  - [ ] Success feedback
  - [ ] Smooth animations

### Dictation Reliability
- [ ] Improve transcription feedback
  - [ ] Show upload progress
  - [ ] Show transcription progress
  - [ ] Better error messages
  - [ ] Retry mechanism for failed transcriptions
- [ ] Add confidence indicators
  - [ ] Visual feedback during capture
  - [ ] Success/failure toasts
  - [ ] Audio level indicators

---

## 🎨 Phase 2: UI/UX Improvements
**Goal**: Make the app feel polished and delightful

### Pill UI/UX
- [ ] Fix waveform animation (doesn't move with audio)
- [ ] Improve state transition animations
  - [ ] Smooth hover → listening
  - [ ] Smooth listening → transcribing
  - [ ] Smooth transcribing → idle
- [ ] Improve pill hover state
  - [ ] Reduce size (currently too big)
  - [ ] Smooth animation transitions
  - [ ] Better visual hierarchy

### Visual Polish
- [ ] Consistent animation timing
- [ ] Better color contrast
- [ ] Improved typography
- [ ] Smooth transitions everywhere

---

## 🚀 Phase 3: Meetings Feature (Vision)
**Goal**: Auto-detect tasks from meetings and suggest actions

### Meeting Detection & Recording
- [ ] Improve meeting detection reliability
  - [ ] Better detection algorithm
  - [ ] Reduce false positives
  - [ ] Handle edge cases (multiple meetings, overlapping)
- [ ] Meeting recording improvements
  - [ ] Better chunk management
  - [ ] Handle network failures gracefully
  - [ ] Resume interrupted recordings
  - [ ] Better meeting metadata (title, participants, etc.)

### Post-Meeting Task Extraction
- [ ] Extract action items from transcript
  - [ ] Use agent to identify tasks
  - [ ] Extract assignees ("Dave should...")
  - [ ] Extract deadlines ("by Friday")
- [ ] Ephemeral task suggestion window
  - [ ] Show after meeting ends
  - [ ] List of suggested tasks
  - [ ] One-click to create Linear issues
  - [ ] One-click to send Slack messages
  - [ ] Auto-dismiss after timeout

### Meeting Management
- [ ] Meeting history view
- [ ] Search meetings
- [ ] Meeting summaries
- [ ] Export meeting notes

---

## 🔌 Phase 4: Integrations & Features
**Goal**: Expand capabilities and integrations

### Agent Improvements
- [ ] More tool integrations
  - [ ] Calendar (create events)
  - [ ] Email (send messages)
  - [ ] More Linear operations
  - [ ] More Slack operations
- [ ] Better tool approval UX
  - [ ] Preview changes before approval
  - [ ] Batch approvals
  - [ ] Approval history

### Advanced Features
- [ ] Voice commands for agent
- [ ] Custom shortcuts/commands
- [ ] Multi-language support
- [ ] Offline mode (queue transcriptions)

---

## 🛠️ Infrastructure
- [x] Setup automated release workflow
- [ ] Fix Sparkle updates (automated OTA updates)
- [ ] Add error tracking/analytics
- [ ] Add performance monitoring
- [ ] Add user feedback mechanism
