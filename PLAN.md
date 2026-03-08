# TalkClaw Feature Plan

**Status:** Planning Phase - Not Yet Implemented  
**Date:** 2026-03-07  
**Context:** Developer Mode - Building generic framework for any user  

---

## Design Philosophy

**We are building TalkClaw as a blank slate framework that anyone can use.**

- **Developer Mode:** Build generic, reusable components
- **User Mode:** Harrison (or any user) customizes framework for their needs
- **Example:** Pinned posts framework is generic. Reminders are one use case for it, not hardcoded.

---

## 1. Platform Context & Notifications

### Problem Statement

OpenClaw needs to know when it's running in TalkClaw (vs Telegram, web chat, etc.) so it can:
- Use TalkClaw-specific features (widgets, pinned posts)
- Adjust behavior accordingly
- Send notifications to the right platform

### Current State (Telegram)

OpenClaw receives platform context as JSON metadata:
```json
{
  "channel": "telegram",
  "provider": "telegram", 
  "surface": "telegram",
  "chat_id": "telegram:6656460155"
}
```

### Proposed Solution (TalkClaw)

**Use identical structure:**
```json
{
  "channel": "talkclaw",
  "provider": "talkclaw",
  "surface": "talkclaw", 
  "chat_id": "talkclaw:session-{session_id}"
}
```

### Notification Behavior

**Scope:** Primarily new chat messages
- OpenClaw sends to **existing conversations** in TalkClaw
- Not new conversations per notification type
- Reminders, alerts, etc. all go to active session

**Future Consideration:** Non-persistent, non-chat notifications (system status, background tasks)
- Not implemented in v1.0
- May revisit later

### Implementation

**Backend (TalkClaw Server):**
- Include platform metadata in every message envelope
- Format: HTTP headers or JSON wrapper
- Ensure session_id is accessible for `chat_id`

**Frontend (TalkClaw App):**
- Pass platform context when sending messages
- Include in WebSocket handshake or per-message metadata

**OpenClaw Integration:**
- TalkClaw skill reads `channel` field from inbound context
- System prompt includes platform awareness
- Agent can check `if (context.channel === 'talkclaw')` for feature availability

---

## 2. Pinned Posts Framework

### Overview

**Generic framework for pinning important messages to the top of a conversation.**

**Use Cases:**
- Reminders (auto-pin when created, unpin when done)
- Important instructions
- Reference information
- Ongoing tasks
- Anything user or agent deems important

**Key Principle:** Framework is not reminder-specific. Reminders are one application of the framework.

### Pin Management

**Creation Methods:**

1. **Manual by User:**
   - Long press on message → "Pin Message" option
   - User explicitly pins any message

2. **Agent-Triggered:**
   - User gives instructions: "Pin all reminders"
   - Agent calls `pin_message(message_id, type, metadata)` 
   - Agent decides based on content/context

**Deletion Methods:**
- Tap 📌 icon on pinned message
- Long press → "Unpin"
- Agent can unpin via API call
- Message deletion also removes pin

**Limits:**
- **Unlimited pins per session** (user decides how many)
- Stacking UI handles visual display (see below)

### Pin Scope

**Session-Isolated:**
- Pins are scoped to individual sessions
- Session A pins don't show in Session B
- Each conversation manages its own pins independently

**Cross-Session Future Consideration:**
- Global pins (show across all sessions)
- Not in v1.0

### Stacking UI - Detailed Specification

**This is a complex component. Think through carefully for 1, 3, 6, 10+ pins.**

#### Visual Display

**Pins 1-3: Full Display**
```
┌─────────────────────────────┐
│ 📌 💬 Pin 1 - Most Recent   │
├─────────────────────────────┤
│ 📌 💬 Pin 2                 │
├─────────────────────────────┤
│ 📌 💬 Pin 3                 │
└─────────────────────────────┘
[Chat messages below]
```

**Pins 4-6: Stacked with Slivers**
```
┌─────────────────────────────┐
│ 📌 💬 Pin 1 - Most Recent   │ ← Full card
├─────────────────────────────┤
│ 📌 💬 Pin 2        [sliver] │ ← Partial card showing
├─────────────────────────────┤
│ 📌 💬 Pin 3    [sliver]     │ ← Smaller sliver
├─────────────────────────────┤
│ Pin 4 [tiny sliver]         │ ← Just edge visible
├─────────────────────────────┤
│ Pin 5 [tiny]                │
├─────────────────────────────┤
│ Pin 6 [tiny]                │
└─────────────────────────────┘
[Chat messages below]
```

**7+ Pins: Stack Indicator**
- Show slivers for top 6
- "+3 more" badge on stack
- Visual depth effect (like stack of paper)

#### Interaction Behavior

**1. Tap Stack (Anywhere on Pinned Area):**
- **Action:** Unfurl all pins
- **Animation:** Expand accordion-style
- **Display:** All pins shown in full
- **Position:** Overlays on top of chat messages (not push down)
- **Scrollable:** If 20+ pins, scroll within pinned area
- **Close:** Tap outside pinned area or tap collapse icon

**Unfurled State:**
```
┌─────────────────────────────┐
│ [▼ Collapse]                │
├─────────────────────────────┤
│ 📌 💬 Pin 1                 │
├─────────────────────────────┤
│ 📌 💬 Pin 2                 │
├─────────────────────────────┤
│ 📌 💬 Pin 3                 │
├─────────────────────────────┤
│ 📌 💬 Pin 4                 │
│ ...                         │
│ 📌 💬 Pin 10                │
└─────────────────────────────┘
    ↓ (overlays chat)
┌─────────────────────────────┐
│ [Chat messages dimmed/blur] │
│                             │
└─────────────────────────────┘
```

**2. Tap Individual Pinned Message:**
- **Action:** Close stack (collapse pins)
- **Action:** Scroll to that message in chat history
- **Animation:** Smooth scroll, highlight message briefly
- **Use Case:** Navigate to important message quickly

**3. Tap 📌 Icon on Pin:**
- **Action:** Unpin this message
- **Animation:** Pin slides out of stack
- **Stack adjusts:** Remaining pins re-stack
- **Confirmation:** Optional "Unpinned" toast

**4. Tap 💬 Icon on Pin:**
- **Action:** Set as reply target
- **Display:** Message quote appears above message input box
- **Behavior:** Same as swipe-to-reply (see Reply to Message section)
- **User Experience:** Quick reply to pinned item

### Pin Data Structure

**Database Schema:**

```sql
CREATE TABLE pinned_messages (
  id UUID PRIMARY KEY,
  session_id UUID NOT NULL,
  message_id UUID NOT NULL,
  pin_type VARCHAR(50),           -- 'reminder', 'instruction', 'reference', 'custom'
  metadata JSONB,                 -- {reminder_id: "rem-123", custom_data: {...}}
  pinned_at TIMESTAMP DEFAULT NOW(),
  pinned_by VARCHAR(50),          -- 'user' or 'agent'
  pin_order INTEGER,              -- Display order (lower = top)
  
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  UNIQUE (session_id, message_id)
);

CREATE INDEX idx_pinned_session ON pinned_messages(session_id, pin_order);
```

**API Endpoints:**

```typescript
// Pin a message
POST /api/v1/sessions/{session_id}/pins
{
  message_id: "msg-123",
  pin_type: "reminder",
  metadata: { reminder_id: "rem-456" }
}

// List pins for session
GET /api/v1/sessions/{session_id}/pins
// Returns: ordered array of pinned messages with full message content

// Unpin a message
DELETE /api/v1/sessions/{session_id}/pins/{message_id}

// Reorder pins
PATCH /api/v1/sessions/{session_id}/pins/reorder
{
  pin_ids: ["pin-1", "pin-2", "pin-3"]  // New order
}
```

**OpenClaw TalkClaw Skill:**

```javascript
// Agent can pin messages
await pinMessage(messageId, {
  type: 'reminder',
  metadata: { reminder_id: 'rem-123' }
});

// Agent can unpin
await unpinMessage(messageId);

// Agent can list pins
const pins = await listPinnedMessages(sessionId);
```

### UI/UX Details

**Visual Design:**
- Pin cards have subtle shadow (stacked paper effect)
- Slivers show different colors or gradient edges
- Unfurl animation: smooth expand (300ms)
- Collapse animation: smooth contract (200ms)

**Icons:**
- 📌 Red pin icon (unpin action)
- 💬 Blue speech bubble (reply action)
- Icons always visible, even on slivers

**Accessibility:**
- Screen reader announces pin count
- Keyboard navigation through pins (Tab)
- Swipe gestures for mobile (swipe up to unfurl)

**Edge Cases:**
- 0 pins: No pinned area shown
- 1 pin: Full card, no stack
- 2 pins: Two full cards, no stack  
- 3 pins: Three full cards, stack starts at 4
- 100+ pins: Scroll within unfurled view

---

## 3. Reply to Message (Swipe Right)

### Overview

**Standard messaging pattern:** User swipes right on a message to quote-reply to it.

**Behavior matches:** Telegram, WhatsApp, Slack

### UX Specification

**Swipe Gesture:**
- **Trigger:** Slight swipe right (not full swipe)
- **Distance:** ~30-40% of screen width
- **Haptic Feedback:** Light haptic on swipe start
- **Visual:** Message slides right slightly, reply icon appears

**Restrictions:**
- **User can only reply to agent messages**
- Cannot reply to own messages
- Prevents confusing self-quoting

### Visual Indicator

**Reply Bar Above Message Box:**
```
┌─────────────────────────────────────┐
│ Replying to:                    [×] │
│ ┌─────────────────────────────────┐ │
│ │ Agent: Here's the summary...    │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ [Type your message...]              │
└─────────────────────────────────────┘
```

**Matches:** Telegram/WhatsApp pattern exactly
- Shows quoted message preview
- [×] to cancel reply
- Clear visual separation

### Backend Implementation

**Message Structure:**

```sql
ALTER TABLE messages ADD COLUMN reply_to_id UUID;
ALTER TABLE messages ADD CONSTRAINT fk_reply_to 
  FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL;

CREATE INDEX idx_messages_reply_to ON messages(reply_to_id);
```

**API:**

```typescript
// Send message with reply
POST /api/v1/sessions/{session_id}/messages
{
  content: "Yes, that sounds good",
  reply_to_id: "msg-123"
}

// Response includes replied message
{
  id: "msg-456",
  content: "Yes, that sounds good",
  reply_to_id: "msg-123",
  reply_to_message: {
    id: "msg-123",
    content: "Here's the summary...",
    sender: "agent"
  }
}
```

### OpenClaw TalkClaw Skill Integration

**When user replies to a message:**

1. **TalkClaw backend fetches original message:**
   ```javascript
   const originalMessage = await getMessage(reply_to_id);
   ```

2. **Include in context sent to OpenClaw:**
   ```json
   {
     "user_message": "Yes, that sounds good",
     "reply_context": {
       "message_id": "msg-123",
       "content": "Here's the summary of your reminders...",
       "sender": "agent",
       "timestamp": "2026-03-07T18:00:00Z"
     }
   }
   ```

3. **OpenClaw TalkClaw skill formats for prompt:**
   ```
   User replied to your previous message:
   > "Here's the summary of your reminders..."
   
   User's reply: "Yes, that sounds good"
   ```

4. **Agent sees full context and can respond appropriately**

**TalkClaw Skill Function:**

```javascript
async function handleReply(inboundMessage) {
  if (inboundMessage.reply_to_id) {
    const originalMessage = await fetchMessage(inboundMessage.reply_to_id);
    
    // Format context for agent
    const contextPrefix = `[User replied to: "${originalMessage.content.substring(0, 100)}..."]`;
    
    // Include in prompt
    return {
      message: inboundMessage.content,
      context: contextPrefix,
      metadata: {
        reply_to: originalMessage
      }
    };
  }
  
  return { message: inboundMessage.content };
}
```

### UI Details

**Swipe Animation:**
- Message slides right 40% max
- Reply icon (↩️) fades in on right side
- Release to activate (or swipe back to cancel)
- Smooth spring animation (iOS-style)

**Reply Preview:**
- Max 2 lines of quoted text
- Truncate with "..." if longer
- Show sender name (always "Agent" since can't reply to self)
- Gray background, subtle border

**Cancel Reply:**
- Tap [×] icon
- Swipe down on reply bar
- Tap outside message box area

---

## 4. Reply as Thread (Breakout Sessions)

### Overview

**Create a new OpenClaw session that branches from a specific message.**

**Use Case:** Deep dive on specific topic without cluttering main conversation.

**Status:** User uncertain about complexity. Requires careful architectural thinking.

### Constraints

- **Single-user only:** No multi-user threads
- TalkClaw is user ↔ agent only
- **Past context:** Thread starts with conversation history up to that point

### Proposed Architecture

**Thread Creation:**

1. **User Action:**
   - Long press on agent message
   - Select "Reply as Thread" option
   - Or swipe gesture variant (swipe left?)

2. **Backend Creates:**
   ```sql
   INSERT INTO sessions (id, parent_session_id, parent_message_id, forked_at)
   VALUES (
     'session-thread-789',
     'session-main-123',
     'msg-456',
     NOW()
   );
   ```

3. **Copy Context:**
   - **Snapshot model:** Copy all messages from parent session up to `parent_message_id`
   - Store as initial context for thread session
   - Thread evolves independently after creation

**Thread Data Structure:**

```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  
  -- Thread fields
  parent_session_id UUID,              -- NULL if main session
  parent_message_id UUID,              -- Which message spawned thread
  forked_at TIMESTAMP,                 -- When thread was created
  thread_context JSONB,                -- Snapshot of parent messages
  
  FOREIGN KEY (parent_session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_message_id) REFERENCES messages(id) ON DELETE SET NULL
);

CREATE INDEX idx_sessions_parent ON sessions(parent_session_id);
```

**Thread Display:**

**Parent Session:**
```
┌─────────────────────────────┐
│ Agent: Here's the plan...   │
│                  [💬 3 →]   │  ← Thread indicator
└─────────────────────────────┘
```

**Thread Session (New View):**
```
┌─────────────────────────────┐
│ ← Back to Main              │  ← Navigation
│ Thread: "Here's the plan"   │  ← Context
├─────────────────────────────┤
│ [Messages from parent       │
│  up to fork point...]       │
├─────────────────────────────┤
│ [New thread messages]       │
└─────────────────────────────┘
```

### OpenClaw Integration

**When thread is created:**

1. **TalkClaw sends to OpenClaw:**
   ```json
   {
     "action": "create_thread",
     "parent_session_id": "session-123",
     "parent_message_id": "msg-456",
     "initial_context": [
       {"role": "user", "content": "..."},
       {"role": "assistant", "content": "..."},
       // ... messages up to fork point
     ]
   }
   ```

2. **OpenClaw spawns new session:**
   ```bash
   openclaw session spawn --parent session-123 \
     --context context.json \
     --label "Thread: Planning Discussion"
   ```

3. **Thread session has:**
   - Full conversation history up to fork point
   - Aware it's a thread: system prompt includes "This is a thread discussion from: [parent message]"
   - Can reference parent context
   - Evolves independently

**Thread Session Metadata:**
```json
{
  "session_type": "thread",
  "parent_session": "session-123",
  "parent_message": "msg-456",
  "forked_at": "2026-03-07T18:00:00Z",
  "context": "User wanted to discuss planning in detail"
}
```

### UI/UX Considerations

**Thread List (Sidebar):**
```
Main Conversations
├─ 💬 General Chat
│  ├─ 🧵 Thread: Planning (3 msgs)
│  └─ 🧵 Thread: Ideas (12 msgs)
└─ 💬 Reminders
```

**Navigation:**
- Tap thread indicator on parent message → jump to thread
- Back button in thread → return to parent
- Thread shows in conversation list (indented or tagged)

**Thread Lifecycle:**
- Persist indefinitely (don't auto-archive)
- User can manually archive/delete
- Delete parent session → delete all child threads (cascade)

### Open Questions / Future Considerations

**User expressed uncertainty:** "I think it would be difficult to manage"

**Questions to resolve:**
- How to prevent thread explosion (too many branches)?
- Merge thread back to main conversation?
- Thread-of-thread (nested threads)?
- Visual indication in parent that thread exists?

**Recommendation:** Start simple
- v1.0: Basic thread creation with snapshot context
- v1.1: Thread management (archive, merge, close)
- v2.0: Advanced threading (nested, auto-archive)

**For PLAN.md:** Document architecture, mark as "Requires Further Design" for complex parts.

---

## Implementation Phasing

### Phase 1: Foundation (v1.0)

**Priority: High**

1. **Platform Context** ✅
   - Add TalkClaw metadata to message envelope
   - OpenClaw skill reads platform context
   - System prompt awareness

2. **Pinned Posts - Basic** ✅
   - Database schema
   - API endpoints (pin, unpin, list)
   - Basic UI (1-3 pins full display)
   - Manual pin/unpin

3. **Reply to Message** ✅
   - Swipe gesture
   - Reply bar UI
   - Backend reply_to_id field
   - TalkClaw skill context fetching

**Estimated:** 2-3 weeks development

### Phase 2: Enhanced UX (v1.1)

**Priority: Medium**

1. **Pinned Posts - Stacking** ⭐
   - Sliver stacking UI (4-6 pins)
   - Unfurl/collapse animation
   - Overlay display
   - Scroll to message on tap

2. **Pinned Posts - Icons** ⭐
   - 📌 Unpin icon
   - 💬 Reply from pin
   - Agent pin API integration

3. **Reply - Enhanced**
   - Rich reply preview
   - Reply chain visualization
   - Thread view (nested replies)

**Estimated:** 2-3 weeks development

### Phase 3: Advanced (v2.0)

**Priority: Low (Future)**

1. **Reply as Thread**
   - Thread creation
   - Context snapshot
   - Thread navigation UI
   - OpenClaw session spawning

2. **Thread Management**
   - Archive threads
   - Thread lifecycle
   - Thread indicators

3. **Non-Persistent Notifications**
   - System notifications
   - Background task alerts
   - External event notifications

**Estimated:** 3-4 weeks development

---

## Technical Stack

### Frontend (TalkClaw iOS App)

**Technologies:**
- SwiftUI for UI
- Combine for reactive data
- Haptic feedback engine
- Core Animation for stacking

**Key Components:**
```
TalkClawApp/
├── Views/
│   ├── PinnedMessagesStack.swift    ← Stacking component
│   ├── PinnedMessageCard.swift      ← Individual pin
│   ├── ReplyBar.swift               ← Reply indicator
│   └── ThreadNavigator.swift        ← Thread UI
├── ViewModels/
│   ├── PinnedMessagesViewModel.swift
│   └── ReplyViewModel.swift
└── Gestures/
    ├── SwipeToReplyGesture.swift
    └── PinUnfurlGesture.swift
```

### Backend (TalkClaw Server)

**Technologies:**
- Swift Vapor framework
- PostgreSQL database
- WebSocket for real-time
- Redis for caching

**API Routes:**
```swift
// Pins
app.post("sessions", ":id", "pins", use: createPin)
app.get("sessions", ":id", "pins", use: listPins)
app.delete("sessions", ":id", "pins", ":messageId", use: deletePin)

// Replies
app.post("sessions", ":id", "messages", use: sendMessage)  // with reply_to_id
app.get("messages", ":id", use: getMessage)                // for context fetch

// Threads
app.post("sessions", ":id", "threads", use: createThread)
app.get("sessions", ":id", "threads", use: listThreads)
```

### OpenClaw Integration

**TalkClaw Skill Enhancement:**

```javascript
// openclaw-skill/talkclaw-skill.js

class TalkClawSkill {
  // Pin management
  async pinMessage(messageId, type, metadata) {
    return await api.post(`/sessions/${sessionId}/pins`, {
      message_id: messageId,
      pin_type: type,
      metadata
    });
  }
  
  async unpinMessage(messageId) {
    return await api.delete(`/sessions/${sessionId}/pins/${messageId}`);
  }
  
  // Reply context
  async getReplyContext(messageId) {
    const message = await api.get(`/messages/${messageId}`);
    return {
      content: message.content,
      sender: message.sender,
      timestamp: message.created_at
    };
  }
  
  // Thread creation
  async createThread(parentMessageId, initialMessage) {
    return await api.post(`/sessions/${sessionId}/threads`, {
      parent_message_id: parentMessageId,
      initial_message: initialMessage
    });
  }
}
```

---

## Database Schema Summary

```sql
-- Pinned messages
CREATE TABLE pinned_messages (
  id UUID PRIMARY KEY,
  session_id UUID NOT NULL,
  message_id UUID NOT NULL,
  pin_type VARCHAR(50),
  metadata JSONB,
  pinned_at TIMESTAMP DEFAULT NOW(),
  pinned_by VARCHAR(50),
  pin_order INTEGER,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
  UNIQUE (session_id, message_id)
);

-- Reply chains
ALTER TABLE messages ADD COLUMN reply_to_id UUID;
ALTER TABLE messages ADD CONSTRAINT fk_reply_to 
  FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL;

-- Thread sessions
ALTER TABLE sessions ADD COLUMN parent_session_id UUID;
ALTER TABLE sessions ADD COLUMN parent_message_id UUID;
ALTER TABLE sessions ADD COLUMN forked_at TIMESTAMP;
ALTER TABLE sessions ADD COLUMN thread_context JSONB;

ALTER TABLE sessions ADD CONSTRAINT fk_parent_session
  FOREIGN KEY (parent_session_id) REFERENCES sessions(id) ON DELETE CASCADE;
  
-- Indexes
CREATE INDEX idx_pinned_session ON pinned_messages(session_id, pin_order);
CREATE INDEX idx_messages_reply_to ON messages(reply_to_id);
CREATE INDEX idx_sessions_parent ON sessions(parent_session_id);
```

---

## Success Metrics

**Phase 1:**
- ✅ OpenClaw knows it's in TalkClaw (platform context working)
- ✅ Users can pin/unpin messages
- ✅ Users can reply to agent messages
- ✅ Reply context shows in OpenClaw

**Phase 2:**
- ✅ Pin stacking works smoothly for 1-10+ pins
- ✅ Unfurl animation is smooth (60fps)
- ✅ Agent can auto-pin messages based on instructions
- ✅ Reply from pin works seamlessly

**Phase 3:**
- ✅ Users can create threads
- ✅ Threads maintain context correctly
- ✅ Thread navigation is intuitive

---

## Design Decisions Log

**1. Platform Context:** Same JSON structure as Telegram (consistent pattern)

**2. Pin Stacking:** Slivers up to 6, then stack indicator (balance visibility vs clutter)

**3. Unfurl Display:** Overlay (not push down) to avoid jarring layout shifts

**4. Reply Restriction:** Agent messages only (prevents self-quoting confusion)

**5. Thread Context:** Snapshot at creation (simpler than live reference)

**6. Developer Mode:** Build generic framework, not app-specific features

**7. Icons:** 📌 for unpin, 💬 for reply (standard, intuitive)

---

## Open Questions

1. **Pin Stacking Edge Cases:**
   - What happens with 50+ pins? Virtual scroll?
   - Should there be a "View All Pins" modal?

2. **Thread Complexity:**
   - How to prevent too many threads?
   - Should threads have expiration?
   - Merge thread back to main?

3. **Agent Auto-Pin:**
   - What triggers agent to pin?
   - User instruction format?
   - Can agent decide autonomously?

4. **Performance:**
   - Unfurl animation with 100+ pins?
   - Scroll performance in thread with 1000+ messages?

5. **Non-Persistent Notifications:**
   - Include in v1.0 or defer?
   - What types beyond chat messages?

---

## Next Steps

**Immediate:**
1. Review and approve this PLAN.md
2. Create GitHub issues for Phase 1 tasks
3. Design database migrations
4. Create UI mockups for pin stacking

**Phase 1 Development:**
1. Backend: Implement database schema
2. Backend: Build API endpoints
3. Frontend: Implement swipe gestures
4. Frontend: Build reply bar UI
5. OpenClaw: Enhance TalkClaw skill
6. Testing: E2E tests for all features

**Timeline:**
- PLAN.md approval: 1 week
- Phase 1 development: 2-3 weeks
- Phase 1 testing: 1 week
- Phase 1 deployment: 1 day
- **Total to Phase 1 launch:** ~5-6 weeks

---

## Appendix: User Requirements (Original Voice Notes)

**Configurable Notifications:**
- "We need to send context that the openclaw is in TalkClaw so that it knows to be able to use widgets and the pinned text"
- "When openclaw sends to talkclaw it should send to existing conversations"

**Pinned Posts:**
- "Unlimited pinned. The user can decide"
- "There are 3 that can be in the top but after 3 it stacks"
- "Even if there are 10 it only fills up the space of 3 and shows it like a stack of paper"
- "When tapped it can unfurl down over the chat"
- "This is a complicated component so we need to think through it very carefully"
- "We won't hard code the reminders into this"

**Reply to Message:**
- "It should be a slight swipe. Not a full swipe"
- "There is a haptic on swipe"
- "User can only reply to agent messages"
- "A bar above the message box just like telegram or WhatsApp"

**Threads:**
- "Thread has past context and starts from that thread"
- "Definitely no other users. This talkclaw is only between user and agent"
- "I think it would be difficult to manage so let's think through it"

**Developer vs User Mode:**
- "For the purposes of this chat we are the developer. So we are building talkclaw as a blank slate for anyone. When we switch to as a user mode we can use the pinned chat framework how we want to"

---

**Last Updated:** 2026-03-07  
**Status:** Planning Complete - Ready for Implementation  
**Next Review:** After Phase 1 prototype

---

## FINAL UPDATES (2026-03-07 19:09 UTC)

### Critical Clarifications from User

**1. OVERLAY - NOT PUSH DOWN ⚠️**

User emphasized (with "!!!"): **Chats are NOT pushed down when pins unfurl.**

**Unfurl behavior:**
- Pins overlay on top of chat messages (dropdown style)
- Chat messages behind become dimmed/blurred
- Does NOT push chat down (accordion style)
- Like iOS Calendar stacked meetings (see visual reference)

**2. Scrolling Within Pinned Area**

- Find optimal number of pins that fit on screen (likely 5-8)
- Once that limit is reached, enable scroll within pinned area
- Prevents unfurled pins from taking over entire screen

**3. Agent Pin API - Detailed Documentation Required**

User specifically requested: **"We need to have detailed documentation on the pinned message api so agents can pin and un pin messages"**

See expanded "Agent Pin API" section below for comprehensive documentation.

**4. User Manual Pin**

Primary method: **Long press on message** → "Pin Message" option

**5. Auto-fetch Confirmed**

Reply-to-message: TalkClaw backend auto-fetches original message and includes in context.

**6. Threads Deferred**

User decision: "Defer threads for now"

**7. Ready to Start**

User confirmed: **"I think we have enough to get started!"**

---

## Agent Pin API - Comprehensive Documentation

### Overview

Agents need detailed API documentation to programmatically pin and unpin messages based on user instructions.

### REST API Endpoints

#### POST /api/v1/sessions/{session_id}/pins

**Create a pin**

**Request:**
```http
POST /api/v1/sessions/{session_id}/pins
Content-Type: application/json
Authorization: Bearer {token}

{
  "message_id": "msg-abc123",
  "pin_type": "reminder|instruction|reference|custom",
  "metadata": {
    "reminder_id": "rem-456",
    "priority": "high",
    "custom_data": {}
  }
}
```

**Response (200 OK):**
```json
{
  "pin_id": "pin-xyz789",
  "message_id": "msg-abc123",
  "pin_type": "reminder",
  "pinned_at": "2026-03-07T19:00:00Z",
  "pinned_by": "agent",
  "pin_order": 1,
  "message": {
    "id": "msg-abc123",
    "content": "Reminder: Send email at 5pm",
    "sender": "agent",
    "created_at": "2026-03-07T18:00:00Z"
  }
}
```

**Error Responses:**
- `400 Bad Request`: message_id required or invalid format
- `404 Not Found`: message does not exist
- `409 Conflict`: message already pinned in this session
- `422 Unprocessable Entity`: invalid pin_type value

---

#### GET /api/v1/sessions/{session_id}/pins

**List all pins for session**

**Request:**
```http
GET /api/v1/sessions/{session_id}/pins
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "pins": [
    {
      "pin_id": "pin-xyz789",
      "message_id": "msg-abc123",
      "pin_type": "reminder",
      "metadata": { "reminder_id": "rem-456" },
      "pinned_at": "2026-03-07T19:00:00Z",
      "pinned_by": "agent",
      "pin_order": 1,
      "message": {
        "id": "msg-abc123",
        "content": "Reminder: Send email at 5pm",
        "sender": "agent",
        "created_at": "2026-03-07T18:00:00Z"
      }
    }
  ],
  "total_count": 5
}
```

---

#### DELETE /api/v1/sessions/{session_id}/pins/{message_id}

**Unpin a message**

**Request:**
```http
DELETE /api/v1/sessions/{session_id}/pins/{message_id}
Authorization: Bearer {token}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Pin removed",
  "message_id": "msg-abc123"
}
```

**Error Responses:**
- `404 Not Found`: pin does not exist for this message/session
- `403 Forbidden`: agent cannot unpin user-created pins (optional policy)

---

#### PATCH /api/v1/sessions/{session_id}/pins/reorder

**Reorder pins**

**Request:**
```http
PATCH /api/v1/sessions/{session_id}/pins/reorder
Content-Type: application/json
Authorization: Bearer {token}

{
  "pin_order": ["pin-abc", "pin-xyz", "pin-123"]
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "updated_count": 3
}
```

---

### OpenClaw TalkClaw Skill Functions

**Module:** `openclaw-skill/talkclaw-pin-api.js`

```javascript
/**
 * Pin a message in TalkClaw
 * 
 * @param {string} messageId - The message ID to pin
 * @param {object} options - Pin configuration
 * @param {string} options.type - Pin type: 'reminder', 'instruction', 'reference', 'custom'
 * @param {object} options.metadata - Additional data (reminder_id, priority, etc.)
 * @returns {Promise<object>} Pin object with pin_id, message, metadata
 * @throws {Error} If pin operation fails
 * 
 * @example
 * const pin = await pinMessage('msg-123', {
 *   type: 'reminder',
 *   metadata: { reminder_id: 'rem-456', priority: 'high' }
 * });
 */
async function pinMessage(messageId, { type = 'custom', metadata = {} } = {}) {
  const response = await fetch(`${TALKCLAW_API}/sessions/${sessionId}/pins`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${TALKCLAW_TOKEN}`
    },
    body: JSON.stringify({
      message_id: messageId,
      pin_type: type,
      metadata
    })
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Pin failed (${response.status}): ${error.message}`);
  }
  
  return await response.json();
}

/**
 * Unpin a message
 * 
 * @param {string} messageId - The message ID to unpin
 * @returns {Promise<object>} Success response
 * @throws {Error} If unpin operation fails
 * 
 * @example
 * await unpinMessage('msg-123');
 */
async function unpinMessage(messageId) {
  const response = await fetch(`${TALKCLAW_API}/sessions/${sessionId}/pins/${messageId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${TALKCLAW_TOKEN}`
    }
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Unpin failed (${response.status}): ${error.message}`);
  }
  
  return await response.json();
}

/**
 * List all pinned messages for current session
 * 
 * @returns {Promise<array>} Array of pin objects with full message content
 * @throws {Error} If list operation fails
 * 
 * @example
 * const pins = await listPinnedMessages();
 * console.log(`${pins.length} pins found`);
 */
async function listPinnedMessages() {
  const response = await fetch(`${TALKCLAW_API}/sessions/${sessionId}/pins`, {
    headers: {
      'Authorization': `Bearer ${TALKCLAW_TOKEN}`
    }
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(`List pins failed (${response.status}): ${error.message}`);
  }
  
  const data = await response.json();
  return data.pins;
}

/**
 * Check if a message is currently pinned
 * 
 * @param {string} messageId - The message ID to check
 * @returns {Promise<boolean>} True if message is pinned
 * 
 * @example
 * if (await isMessagePinned('msg-123')) {
 *   console.log('Message is already pinned');
 * }
 */
async function isMessagePinned(messageId) {
  const pins = await listPinnedMessages();
  return pins.some(pin => pin.message_id === messageId);
}

/**
 * Find pin by metadata
 * 
 * @param {string} key - Metadata key to search (e.g., 'reminder_id')
 * @param {any} value - Value to match
 * @returns {Promise<object|null>} Pin object if found, null otherwise
 * 
 * @example
 * const reminderPin = await findPinByMetadata('reminder_id', 'rem-456');
 * if (reminderPin) {
 *   await unpinMessage(reminderPin.message_id);
 * }
 */
async function findPinByMetadata(key, value) {
  const pins = await listPinnedMessages();
  return pins.find(pin => pin.metadata && pin.metadata[key] === value) || null;
}

module.exports = {
  pinMessage,
  unpinMessage,
  listPinnedMessages,
  isMessagePinned,
  findPinByMetadata
};
```

---

### Agent Use Cases & Examples

#### Use Case 1: Auto-Pin Reminders

```javascript
// When reminder is created via user command
async function createReminderWithPin(reminderText, time) {
  // Create reminder in reminders system
  const reminder = await createReminder(reminderText, time);
  
  // Send reminder message to chat
  const message = await sendMessage(`⏰ Reminder set: ${reminderText} at ${time}`);
  
  // Auto-pin the reminder message
  await pinMessage(message.id, {
    type: 'reminder',
    metadata: {
      reminder_id: reminder.id,
      reminder_time: time,
      auto_pinned: true
    }
  });
  
  return { reminder, message };
}
```

#### Use Case 2: Unpin When Reminder Complete

```javascript
// When user marks reminder as done
async function completeReminder(reminderId) {
  // Find pinned message for this reminder
  const pin = await findPinByMetadata('reminder_id', reminderId);
  
  if (pin) {
    // Unpin the message
    await unpinMessage(pin.message_id);
    console.log(`Unpinned reminder: ${reminderId}`);
  }
  
  // Delete reminder from reminders system
  await deleteReminder(reminderId);
}
```

#### Use Case 3: Pin Important Messages

```javascript
// User instruction: "Pin important messages"
async function handleUserMessage(messageContent) {
  const response = await generateResponse(messageContent);
  const message = await sendMessage(response);
  
  // Determine if message is important
  if (isImportant(response)) {
    await pinMessage(message.id, {
      type: 'instruction',
      metadata: {
        importance: 'high',
        auto_pinned: true,
        reason: 'Contains critical information'
      }
    });
  }
  
  return message;
}

function isImportant(text) {
  const keywords = ['important', 'critical', 'urgent', 'remember', 'must'];
  return keywords.some(kw => text.toLowerCase().includes(kw));
}
```

#### Use Case 4: Review and Clean Up Old Pins

```javascript
// Periodic cleanup: unpin old completed reminders
async function cleanupOldPins() {
  const pins = await listPinnedMessages();
  const now = new Date();
  
  for (const pin of pins) {
    // If pin is a reminder older than 24 hours
    if (pin.pin_type === 'reminder') {
      const pinnedAt = new Date(pin.pinned_at);
      const ageHours = (now - pinnedAt) / (1000 * 60 * 60);
      
      if (ageHours > 24) {
        console.log(`Unpinning old reminder: ${pin.message_id}`);
        await unpinMessage(pin.message_id);
      }
    }
  }
}
```

---

### Visual Reference

**Stacking UI Inspiration:**
- Reference image: `file_45---c88030bc-1a68-413b-831c-7bf4dfb4ec3a.jpg`
- iOS Calendar stacked meetings
- Apple Reminders card stack
- 3D depth with shadows
- Progressive reveal (slivers)

**Design characteristics:**
- Front card: full display
- Back cards: partial (~20-30% visible)
- Rounded corners
- Subtle shadows for depth
- Smooth animations
- Modern, polished UI

---

## Updated Implementation Timeline

**Phase 1: Foundation (v1.0) - READY TO START**

**Scope confirmed by user:**
1. ✅ Platform Context
2. ✅ Pinned Posts (complete with overlay, stacking, agent API)
3. ✅ Reply to Message (with auto-fetch)

**Deferred:**
- ❌ Reply as Thread (Phase 2+)
- ❌ Non-persistent notifications (Future)

**Estimated:** 3-4 weeks

**User approval:** "I think we have enough to get started!"

---

**Last Updated:** 2026-03-07 19:09 UTC  
**Status:** Planning Complete - All Questions Answered - Ready for Development

---

## 5. Offline Support & Message Queueing

### Overview

**Mobile-first requirement:** TalkClaw must work seamlessly when phone loses connection.

**Behavior:**
- Messages sent while offline are queued locally
- Queue persists across app restarts
- Automatic send when connection returns
- Clear UI indication of offline/pending status

### User Experience

**When Offline:**
```
┌─────────────────────────────┐
│ Your message                │
│ [Pending... 🔄]             │  ← Queued indicator
├─────────────────────────────┤
│ Agent: Previous message     │
└─────────────────────────────┘
```

**When Connection Returns:**
```
┌─────────────────────────────┐
│ Your message                │
│ [Sent ✓]                    │  ← Status updated
├─────────────────────────────┤
│ Agent: Previous message     │
└─────────────────────────────┘
```

### Technical Implementation

#### Message Queue

**Local Storage:**
```swift
struct QueuedMessage: Codable {
    let id: UUID
    let sessionId: String
    let content: String
    let replyToId: String?
    let metadata: [String: Any]?
    let queuedAt: Date
    let retryCount: Int
    let maxRetries: Int = 3
}

class MessageQueue {
    private var queue: [QueuedMessage] = []
    
    // Persist to disk (UserDefaults or Core Data)
    func save() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(queue) {
            UserDefaults.standard.set(encoded, forKey: "messageQueue")
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: "messageQueue") {
            let decoder = JSONDecoder()
            queue = (try? decoder.decode([QueuedMessage].self, from: data)) ?? []
        }
    }
    
    func enqueue(_ message: QueuedMessage) {
        queue.append(message)
        save()
    }
    
    func dequeue() -> QueuedMessage? {
        guard !queue.isEmpty else { return nil }
        let message = queue.removeFirst()
        save()
        return message
    }
}
```

#### Connection Monitoring

**Network Reachability:**
```swift
import Network

class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                
                if self?.isConnected == true {
                    self?.processQueue()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
    
    func processQueue() {
        // Send all queued messages
        MessageQueueManager.shared.sendPendingMessages()
    }
}
```

#### Send Strategy

**Message Send Flow:**
```swift
func sendMessage(_ content: String, replyTo: String? = nil) async throws {
    let message = Message(
        content: content,
        replyToId: replyTo,
        timestamp: Date()
    )
    
    // Check connection
    if NetworkMonitor.shared.isConnected {
        // Send immediately
        try await api.sendMessage(message)
    } else {
        // Queue for later
        let queuedMessage = QueuedMessage(
            id: UUID(),
            sessionId: currentSessionId,
            content: content,
            replyToId: replyTo,
            queuedAt: Date(),
            retryCount: 0
        )
        
        MessageQueue.shared.enqueue(queuedMessage)
        
        // Update UI to show pending
        updateMessageStatus(message.id, status: .pending)
    }
}
```

#### Retry Logic

**Exponential Backoff:**
```swift
func sendQueuedMessage(_ queuedMessage: QueuedMessage) async {
    do {
        try await api.sendMessage(queuedMessage)
        
        // Success - remove from queue
        MessageQueue.shared.dequeue()
        updateMessageStatus(queuedMessage.id, status: .sent)
        
    } catch {
        // Retry with exponential backoff
        if queuedMessage.retryCount < queuedMessage.maxRetries {
            let delay = pow(2.0, Double(queuedMessage.retryCount)) // 1s, 2s, 4s
            
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            var updatedMessage = queuedMessage
            updatedMessage.retryCount += 1
            
            MessageQueue.shared.enqueue(updatedMessage)
            await sendQueuedMessage(updatedMessage)
            
        } else {
            // Max retries exceeded - mark as failed
            updateMessageStatus(queuedMessage.id, status: .failed)
            
            // Optionally: show retry button to user
            showRetryOption(queuedMessage)
        }
    }
}
```

### Message States

**State Machine:**
```
┌─────────┐
│ Drafting│
└────┬────┘
     │
     ▼
┌─────────┐    Offline    ┌─────────┐
│ Sending ├──────────────→│ Pending │
└────┬────┘               └────┬────┘
     │                         │
     │ Online                  │ Connection
     │                         │ Restored
     ▼                         ▼
┌─────────┐               ┌─────────┐
│  Sent   │               │ Sending │
└─────────┘               └────┬────┘
                               │
                               ▼
                          ┌─────────┐
                          │ Sent or │
                          │ Failed  │
                          └─────────┘
```

**Status Indicators:**
- 🔵 Drafting (being typed)
- 🔄 Sending (in flight)
- ⏳ Pending (queued, offline)
- ✓ Sent (confirmed by server)
- ❌ Failed (max retries exceeded)

### Offline Caching - Data to Cache

**Cache locally:**
1. **Messages:** Recent conversation history (last 100 messages per session)
2. **Pinned messages:** All pins for current session
3. **User profile:** Name, avatar, preferences
4. **Session metadata:** Session ID, created date, settings

**Don't cache:**
- Sensitive data (passwords, tokens - use Keychain)
- Large media files (images > 5MB)
- Entire conversation history (only recent)

**Storage Strategy:**
```swift
// Core Data or Realm for structured data
class OfflineCache {
    // Messages cache
    func cacheMessages(_ messages: [Message], for sessionId: String) {
        // Store last 100 messages
        let recent = messages.suffix(100)
        // Save to Core Data
    }
    
    // Pins cache
    func cachePins(_ pins: [PinnedMessage], for sessionId: String) {
        // Store all pins (usually < 10)
    }
    
    // Clear old cache
    func clearOldCache(olderThan days: Int = 7) {
        // Remove messages older than 7 days
    }
}
```

### Sync Strategy

**When Connection Returns:**

1. **Send queued messages** (oldest first)
2. **Fetch new messages** from server
3. **Resolve conflicts** (if any)
4. **Update cache** with latest data
5. **Notify user** of any issues

**Conflict Resolution:**
```swift
// If message sent offline has same content as server message
// (rare, but possible with retry logic)
func resolveConflict(_ localMessage: Message, _ serverMessage: Message) {
    if localMessage.content == serverMessage.content &&
       localMessage.timestamp.timeIntervalSince(serverMessage.timestamp) < 60 {
        // Likely duplicate - keep server version
        MessageQueue.shared.dequeue()
        updateMessageStatus(localMessage.id, status: .sent)
    }
}
```

### UI/UX Details

**Message Status Icons:**
```
Your message               [🔄]  ← Sending
Your message               [⏳]  ← Pending (offline)
Your message               [✓]   ← Sent
Your message               [❌]  ← Failed (tap to retry)
```

**Retry Button:**
```
┌─────────────────────────────┐
│ ❌ Message failed to send   │
│                             │
│ [Retry] [Delete]            │
└─────────────────────────────┘
```

### Database Schema Additions

```sql
-- Message queue table
CREATE TABLE message_queue (
  id UUID PRIMARY KEY,
  session_id UUID NOT NULL,
  content TEXT NOT NULL,
  reply_to_id UUID,
  metadata JSONB,
  queued_at TIMESTAMP NOT NULL,
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  status VARCHAR(20) DEFAULT 'pending',  -- pending, sending, sent, failed
  
  FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- Add status to messages table
ALTER TABLE messages ADD COLUMN send_status VARCHAR(20) DEFAULT 'sent';
-- Values: drafting, sending, pending, sent, failed

CREATE INDEX idx_message_queue_session ON message_queue(session_id, queued_at);
```

### API Endpoint

**Batch Send (for queue processing):**
```http
POST /api/v1/sessions/{session_id}/messages/batch
Content-Type: application/json

{
  "messages": [
    {
      "client_id": "uuid-123",
      "content": "First message",
      "reply_to_id": null,
      "queued_at": "2026-03-07T19:00:00Z"
    },
    {
      "client_id": "uuid-456", 
      "content": "Second message",
      "reply_to_id": "msg-789",
      "queued_at": "2026-03-07T19:01:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "sent": [
    {
      "client_id": "uuid-123",
      "server_id": "msg-abc",
      "status": "sent"
    }
  ],
  "failed": [
    {
      "client_id": "uuid-456",
      "error": "Message invalid",
      "status": "failed"
    }
  ]
}
```

### Testing Scenarios

**Test Cases:**

1. **Airplane Mode:**
   - Enable airplane mode
   - Send 3 messages
   - Verify queued status
   - Disable airplane mode
   - Verify messages send automatically

2. **Poor Connection:**
   - Throttle network to 2G speed
   - Send message
   - Verify retry logic
   - Restore full speed
   - Verify send completes

3. **App Restart:**
   - Send message while offline
   - Force quit app
   - Relaunch app (still offline)
   - Verify message still in queue
   - Go online
   - Verify message sends

4. **Max Retries:**
   - Simulate server unavailable
   - Send message
   - Verify 3 retry attempts
   - Verify failed state after max retries
   - Verify retry button appears

5. **Conflict Resolution:**
   - Send message offline
   - Message eventually sends
   - Verify no duplicate on server

### Performance Considerations

**Queue Size Limits:**
- Max 100 messages in queue
- If exceeded, show warning
- Oldest messages may be dropped (with user confirmation)

**Battery Impact:**
- Don't poll continuously
- Use system network change notifications
- Batch operations when possible
- Limit retry attempts

**Storage:**
- Queue: ~1MB for 100 messages
- Cache: ~10MB for 100 messages + media thumbnails
- Auto-clear old cache (7 days)

### Implementation Phase

**Recommendation: Phase 1.5 or Phase 2**

**Why not Phase 1:**
- Core features should work online first
- Offline is enhancement, not blocker
- Need stable API before adding queue complexity

**Why Phase 1.5/2:**
- Essential for mobile app
- User expectation for messaging apps
- Prevents message loss
- Better UX than error messages

**Estimated:** 1-2 weeks development
- Queue implementation: 3 days
- Network monitoring: 2 days  
- Retry logic: 2 days
- UI/UX polish: 2 days
- Testing: 1 week (critical to get right)

### Success Metrics

**Offline support working:**
- ✅ Messages queue when offline
- ✅ Queue persists across app restarts
- ✅ Auto-send when connection returns
- ✅ Clear status indicators
- ✅ Retry logic handles failures
- ✅ No message loss (<0.01% acceptable)
- ✅ Battery impact minimal (<5% increase)

---

**Last Updated:** 2026-03-07 19:15 UTC  
**Addition:** Offline support & message queueing  
**Status:** Planning Complete - Ready for Development

---

## 6. Widget Marketplace - Dashboard Widget Ideas

### Overview

**Expand TalkClaw dashboard with marketplace of reusable widgets.**

**Current state:** 6 built-in widgets (Clock, Quick Notes, Countdown, Quote, Todo List, System Status)

**Vision:** 50+ widget marketplace with categories for all user types

### Widget Categories & Ideas

#### 1. Productivity & Organization

**Habit Tracker** (M, L)
- Daily habit checkboxes with streak counter
- Visual progress tracking
- Categories: health, learning, work
- Use case: Track meditation, exercise, reading

**Pomodoro Timer** (S, M)
- 25min work / 5min break cycles
- Session counter and history
- Sound notifications
- Use case: Focused work sessions

**Goal Progress** (S, M)
- Progress bars for multiple goals
- Percentage complete tracking
- Deadline awareness
- Use case: Book pages, word count, savings

**Daily Standup** (M)
- "Yesterday / Today / Blockers" template
- Team collaboration
- Daily planning
- Use case: Remote teams, personal planning

#### 2. Information & Data

**Weather Widget** (S, M, L) ⭐ Priority
- Current temperature and conditions
- 5-day forecast (M/L)
- Hourly breakdown (L)
- API: Open-Meteo or OpenWeatherMap

**RSS Feed Reader** (M, L)
- Latest headlines from chosen feeds
- Click to read full article
- Multiple feed sources
- Use case: News, blogs, podcasts

**Stock Ticker** (S, M) ⭐ Priority
- Live stock prices
- % change indicators
- Mini price charts (sparklines)
- API: Alpha Vantage or Yahoo Finance

**Crypto Tracker** (S, M)
- BTC/ETH/major coin prices
- 24-hour change percentages
- Portfolio value tracking
- API: CoinGecko or CoinMarketCap

**Exchange Rates** (S, M)
- Currency converter
- Live exchange rates
- Multiple currency pairs
- Use case: Travel, international business

#### 3. Communication & Social

**Unread Counter** (S)
- Badge count for TalkClaw unread messages
- Quick notification check
- Tap to open messages

**Quick Replies** (M)
- Canned response buttons
- Fast message sending
- Customizable templates

**Social Stats** (M)
- Follower counts across platforms
- Engagement metrics
- Growth tracking
- Use case: Content creators

#### 4. Lifestyle & Wellness

**Water Tracker** (S, M) ⭐ Priority
- Tap to add glasses
- Daily goal progress (8 glasses)
- Hydration reminders
- Visual: Water glass icons, progress circle

**Mood Tracker** (S, M) ⭐ Priority
- Log daily mood with emoji
- Weekly trends and patterns
- Mental health awareness
- Visual: Emoji selector, calendar heatmap

**Gratitude Journal** (M, L)
- Daily gratitude entry
- Browse past entries
- Positive mindset practice
- Search previous gratitudes

**Exercise Logger** (M)
- Quick workout logging
- Track weekly activity
- Exercise types and duration
- Fitness goal tracking

**Meditation Timer** (S, M)
- Guided meditation durations (5, 10, 15, 20 min)
- Session streak tracking
- Calm design with breathe animation
- Sound bell at completion

#### 5. Focus & Motivation

**Focus Mode** (S, M)
- Deep work timer
- Block distraction indicator
- Session tracking
- Pomodoro integration option

**Daily Affirmation** (S, M)
- Rotating positive affirmations
- Refresh button for new affirmation
- Motivational quotes
- Morning boost

**Win of the Day** (M)
- Log one daily win
- Weekly review of accomplishments
- Celebrate small victories
- Build positive momentum

#### 6. Developer & Technical

**GitHub Stats** (S, M, L) ⭐ Priority
- Commit activity graph
- Pull request status
- Repository stars
- Contribution streaks
- OAuth: GitHub API integration

**API Monitor** (M)
- Endpoint health checks
- Response time tracking
- Uptime percentage
- Alert on failures

**Code Snippet Library** (M, L)
- Save/search code snippets
- Syntax highlighting
- Language tags
- Quick copy to clipboard

**Bug Tracker** (M, L)
- Personal bug logging
- Priority tagging
- Status tracking (open/in-progress/resolved)
- Link to code locations

#### 7. Calendar & Time

**Month View Calendar** (M, L) ⭐ Priority
- Traditional month grid
- Mark important dates
- Visual date reference
- Event integration (future)

**Upcoming Events** (S, M)
- Next 3-5 events
- Countdown to each
- Event time display
- Quick event add

**Time Zones** (S, M)
- Multiple timezone clocks
- City names with local times
- AM/PM indicators
- Use case: Remote teams, travel

**Meeting Timer** (S, M)
- Track meeting duration
- Overtime alerts
- Elapsed time display
- Stay on schedule

#### 8. Finance & Business

**Expense Tracker** (M, L) ⭐ Priority
- Quick expense entry
- Category breakdown
- Weekly/monthly totals
- Budget awareness

**Invoice Counter** (S, M)
- Outstanding invoices
- Total amount owed
- Payment status
- Use case: Freelancers

**Revenue Dashboard** (M, L)
- Daily/weekly/monthly revenue
- Trend graph
- Growth percentage
- Business owners

#### 9. Entertainment & Fun

**Spotify Now Playing** (S, M) ⭐ Priority
- Current track display
- Album artwork
- Play/pause controls
- OAuth: Spotify API integration

**Reading List** (M, L)
- Books to read
- Currently reading with progress
- Finished list
- Book tracking

**Movie/TV Watchlist** (M, L)
- Shows to watch
- Mark as watched
- Personal ratings
- Entertainment tracking

**Dice Roller** (S)
- Roll various dice (d6, d20, etc.)
- Multiple dice at once
- Gaming utility
- Random decision maker

**Random Compliment** (S, M)
- Mood boost generator
- Refresh for new compliment
- Positive reinforcement
- Fun interaction

#### 10. Home & Utilities

**Shopping List** (M, L)
- Add grocery items
- Category organization
- Check off purchased
- Shared list option (future)

**Recipe of the Day** (M, L)
- Random recipe suggestions
- Ingredient lists
- Cooking instructions
- Meal planning

**Plant Watering Tracker** (M)
- Track plant watering schedule
- Last watered dates
- Next watering due
- Plant care reminders

**Package Tracker** (M)
- Delivery tracking numbers
- Estimated arrival dates
- Status updates
- Order monitoring

#### 11. Learning & Knowledge

**Flashcards** (M, L)
- Study flashcard decks
- Flip to reveal answer
- Deck progress tracking
- Spaced repetition (future)

**Word of the Day** (S, M)
- Daily vocabulary word
- Definition and example
- Pronunciation guide
- Vocabulary building

**Language Practice** (M)
- Daily phrase in target language
- Translation
- Audio pronunciation (future)
- Language learning

**TIL (Today I Learned)** (M)
- Log interesting facts
- Browse past learnings
- Knowledge collection
- Searchable archive

### Implementation Priority

**Top 10 Most Marketable (Build First):**

1. **Weather Widget** ⭐ - Universal appeal, everyone needs weather
2. **Habit Tracker** ⭐ - Trending productivity, gamification
3. **Pomodoro Timer** ⭐ - Proven technique, developer favorite
4. **Water Tracker** ⭐ - Simple, health-focused, viral potential
5. **Stock Ticker** ⭐ - Finance crowd, high engagement
6. **Month Calendar** ⭐ - Visual utility, date reference
7. **Spotify Now Playing** ⭐ - Music integration, brand value
8. **Expense Tracker** ⭐ - Universal financial need
9. **GitHub Stats** ⭐ - Developer community (TalkClaw audience)
10. **Mood Tracker** ⭐ - Mental health awareness, trending

### Implementation Phases

**Phase 1 - Quick Wins (2-3 weeks):**
- Weather Widget (Open-Meteo API)
- Habit Tracker (frontend + KV storage)
- Pomodoro Timer (timer logic)
- Water Tracker (counter + goals)

**Phase 2 - Integrations (3-4 weeks):**
- Spotify Now Playing (OAuth + API)
- GitHub Stats (API + caching)
- Stock Ticker (API integration)
- Expense Tracker (storage + export)

**Phase 3 - Advanced (4-6 weeks):**
- Month Calendar (date library)
- Flashcards (deck management)
- RSS Reader (feed parsing)
- API Monitor (polling + alerts)

**Phase 4 - Marketplace Platform (6-8 weeks):**
- User-submitted widgets
- Widget ratings/reviews
- Category browsing
- Search/discovery
- Installation analytics

### Technical Patterns

**Common Widget Patterns:**

**Tracker Widgets:**
- Add/increment action
- Daily/weekly view
- Progress visualization
- Streak counter
- Data export

**Information Widgets:**
- Auto-refresh logic
- API caching
- Error states
- Loading skeletons
- Data freshness indicator

**Timer Widgets:**
- Start/pause/reset controls
- Sound notifications
- Background execution
- Session history
- Progress rings

**List Widgets:**
- Add item input
- Item actions (check, delete, edit)
- Persistence via KV storage
- Scrollable view
- Empty state handling

**Display Widgets:**
- Read-only information
- Refresh button
- Minimal interaction
- Large typography
- Icon-focused design

### Marketplace Features

**Discovery:**
- Browse by category
- Search widgets
- Featured widgets
- Trending/popular
- New releases

**Installation:**
- One-click add to dashboard
- Size selection (S/M/L)
- Position preference
- Auto-refresh option

**Management:**
- Installed widgets list
- Update notifications
- Remove/reinstall
- Widget settings

**User Contribution (Future):**
- Submit custom widgets
- Widget approval process
- Rating system
- Revenue sharing

### API Integrations Required

**External APIs:**
- Weather: Open-Meteo (free) or OpenWeatherMap
- Stocks: Alpha Vantage or Yahoo Finance
- Crypto: CoinGecko or CoinMarketCap
- Spotify: OAuth + Web API
- GitHub: OAuth + REST API
- RSS: Feed parser library

**Rate Limiting:**
- Cache API responses
- Respect API rate limits
- Fallback for failures
- User API key option (premium)

### Monetization Strategy

**Free Tier:**
- Basic widgets (Clock, Notes, Todo)
- 5 widget limit on dashboard
- Standard refresh rates

**Premium Tier ($5/month):**
- All widgets unlimited
- Real-time updates (Stock, Crypto)
- Custom widget creation
- Priority support
- Export data features

**Integration Widgets:**
- Require user API keys (Spotify, GitHub)
- OAuth connection flow
- Privacy-focused (no data storage)

---

**Last Updated:** 2026-03-08 00:10 UTC  
**Addition:** Widget Marketplace expansion plan (44 new widgets)  
**Status:** Planning Complete - Ready for Implementation
