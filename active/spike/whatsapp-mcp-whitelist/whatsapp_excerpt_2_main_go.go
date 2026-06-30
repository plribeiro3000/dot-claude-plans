// SOURCE: /tmp/whatsapp-mcp/whatsapp-bridge/main.go
// Lines 412-471 — handleMessage() — the real-time event handler
// This is where Option A (Go bridge filtering) would intercept BEFORE writing to SQLite

// Handle regular incoming messages with media support
func handleMessage(client *whatsmeow.Client, messageStore *MessageStore, msg *events.Message, logger waLog.Logger) {
	// Save message to database
	chatJID := msg.Info.Chat.String()
	sender := msg.Info.Sender.User

	// Get appropriate chat name
	name := GetChatName(client, messageStore, msg.Info.Chat, chatJID, nil, sender, logger)

	// Update chat in database with the message timestamp
	err := messageStore.StoreChat(chatJID, name, msg.Info.Timestamp)
	if err != nil {
		logger.Warnf("Failed to store chat: %v", err)
	}

	// Extract text content
	content := extractTextContent(msg.Message)

	// Extract media info
	mediaType, filename, url, mediaKey, fileSHA256, fileEncSHA256, fileLength := extractMediaInfo(msg.Message)

	// Skip if there's no content and no media
	if content == "" && mediaType == "" {
		return
	}

	// Store message in database
	err = messageStore.StoreMessage(
		msg.Info.ID,
		chatJID,
		// ...
	)
}

// SOURCE: /tmp/whatsapp-mcp/whatsapp-bridge/main.go
// Lines 1009-1148 — handleHistorySync() — history sync event handler
// Option A would also need to filter here (bulk history ingest on first login)
// NOTE: This function iterates ALL conversations in historySync.Data.Conversations
// without any filtering.

func handleHistorySync(client *whatsmeow.Client, messageStore *MessageStore, historySync *events.HistorySync, logger waLog.Logger) {
	fmt.Printf("Received history sync event with %d conversations\n", len(historySync.Data.Conversations))

	syncedCount := 0
	for _, conversation := range historySync.Data.Conversations {
		if conversation.ID == nil {
			continue
		}
		chatJID := *conversation.ID
		// ... stores ALL conversations unconditionally
	}
}

// SOURCE: /tmp/whatsapp-mcp/whatsapp-bridge/main.go
// Lines 778-787 — startRESTServer binding — security note (Issue #215)
// The REST server binds to 0.0.0.0 by default (not localhost)

func startRESTServer(client *whatsmeow.Client, messageStore *MessageStore, port int) {
	// ...
	serverAddr := fmt.Sprintf(":%d", port)  // binds ALL interfaces
	fmt.Printf("Starting REST API server on %s...\n", serverAddr)
	go func() {
		if err := http.ListenAndServe(serverAddr, nil); err != nil {
			fmt.Printf("REST API server error: %v\n", err)
		}
	}()
}

// SOURCE: /tmp/whatsapp-mcp/whatsapp-bridge/main.go
// Lines 838-854 — event handler registration in main()
// Two entry points that must both be gated for Option A to work:

client.AddEventHandler(func(evt interface{}) {
	switch v := evt.(type) {
	case *events.Message:
		// Real-time messages
		handleMessage(client, messageStore, v, logger)

	case *events.HistorySync:
		// Bulk history on first connect
		handleHistorySync(client, messageStore, v, logger)

	case *events.Connected:
		logger.Infof("Connected to WhatsApp")

	case *events.LoggedOut:
		logger.Warnf("Device logged out, please scan QR code to log in again")
	}
})
