# SOURCE: lharries/whatsapp-mcp — whatsapp-mcp-server/whatsapp.py
# Cloned from https://github.com/lharries/whatsapp-mcp at /tmp/whatsapp-mcp-fix (2026-05-27)
#
# RANGE 1: Lines 1-50 — module header, MESSAGES_DB_PATH, dataclass definitions including is_group
# RANGE 2: Lines 124-180 — list_messages() WHERE clause construction (injection point for Option B)
# RANGE 3: Lines 319-390 — list_chats() WHERE clause construction
# RANGE 4: Lines 393-414 — search_contacts() SQL including the @g.us exclusion

# ── RANGE 1: lines 1-50 ──────────────────────────────────────────────────────

import sqlite3
from datetime import datetime
from dataclasses import dataclass
from typing import Optional, List, Tuple
import os.path
import requests
import json
import audio

MESSAGES_DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'whatsapp-bridge', 'store', 'messages.db')
WHATSAPP_API_BASE_URL = "http://localhost:8080/api"

@dataclass
class Message:
    timestamp: datetime
    sender: str
    content: str
    is_from_me: bool
    chat_jid: str
    id: str
    chat_name: Optional[str] = None
    media_type: Optional[str] = None

@dataclass
class Chat:
    jid: str
    name: Optional[str]
    last_message_time: Optional[datetime]
    last_message: Optional[str] = None
    last_sender: Optional[str] = None
    last_is_from_me: Optional[bool] = None

    @property
    def is_group(self) -> bool:
        """Determine if chat is a group based on JID pattern."""
        return self.jid.endswith("@g.us")

@dataclass
class Contact:
    phone_number: str
    name: Optional[str]
    jid: str

@dataclass
class MessageContext:
    message: Message
    before: List[Message]
    after: List[Message]

def get_sender_name(sender_jid: str) -> str:

# ... lines 51-123 omitted ...

# ── RANGE 2: lines 124-180 — list_messages() WHERE clause ────────────────────

def list_messages(
    after: Optional[str] = None,
    before: Optional[str] = None,
    sender_phone_number: Optional[str] = None,
    chat_jid: Optional[str] = None,
    query: Optional[str] = None,
    limit: int = 20,
    page: int = 0,
    include_context: bool = True,
    context_before: int = 1,
    context_after: int = 1
) -> List[Message]:
    """Get messages matching the specified criteria with optional context."""
    try:
        conn = sqlite3.connect(MESSAGES_DB_PATH)
        cursor = conn.cursor()

        # Build base query
        query_parts = ["SELECT messages.timestamp, messages.sender, chats.name, messages.content, messages.is_from_me, chats.jid, messages.id, messages.media_type FROM messages"]
        query_parts.append("JOIN chats ON messages.chat_jid = chats.jid")
        where_clauses = []
        params = []

        # Add filters
        if after:
            try:
                after = datetime.fromisoformat(after)
            except ValueError:
                raise ValueError(f"Invalid date format for 'after': {after}. Please use ISO-8601 format.")

            where_clauses.append("messages.timestamp > ?")
            params.append(after)

        if before:
            try:
                before = datetime.fromisoformat(before)
            except ValueError:
                raise ValueError(f"Invalid date format for 'before': {before}. Please use ISO-8601 format.")

            where_clauses.append("messages.timestamp < ?")
            params.append(before)

        if sender_phone_number:
            where_clauses.append("messages.sender = ?")
            params.append(sender_phone_number)

        if chat_jid:
            where_clauses.append("messages.chat_jid = ?")
            params.append(chat_jid)

        if query:
            where_clauses.append("LOWER(messages.content) LIKE LOWER(?)")
            params.append(f"%{query}%")

        if where_clauses:
            query_parts.append("WHERE " + " AND ".join(where_clauses))

        # Add pagination
        offset = page * limit
        query_parts.append("ORDER BY messages.timestamp DESC")
        query_parts.append("LIMIT ? OFFSET ?")
        params.extend([limit, offset])

        cursor.execute(" ".join(query_parts), tuple(params))
        messages = cursor.fetchall()

        # ... rest of function builds Message objects and returns formatted output


# ... lines 181-318 omitted ...

# ── RANGE 3: lines 319-390 — list_chats() WHERE clause ──────────────────────

def list_chats(
    query: Optional[str] = None,
    limit: int = 20,
    page: int = 0,
    include_last_message: bool = True,
    sort_by: str = "last_active"
) -> List[Chat]:
    """Get chats matching the specified criteria."""
    try:
        conn = sqlite3.connect(MESSAGES_DB_PATH)
        cursor = conn.cursor()

        query_parts = ["""
            SELECT
                chats.jid,
                chats.name,
                chats.last_message_time,
                messages.content as last_message,
                messages.sender as last_sender,
                messages.is_from_me as last_is_from_me
            FROM chats
        """]

        if include_last_message:
            query_parts.append("""
                LEFT JOIN messages ON chats.jid = messages.chat_jid
                AND chats.last_message_time = messages.timestamp
            """)

        where_clauses = []
        params = []

        if query:
            where_clauses.append("(LOWER(chats.name) LIKE LOWER(?) OR chats.jid LIKE ?)")
            params.extend([f"%{query}%", f"%{query}%"])

        if where_clauses:
            query_parts.append("WHERE " + " AND ".join(where_clauses))

        # Add sorting and pagination...
        # Whitelist clause would be appended to where_clauses before this point


# ... lines 391-392 omitted ...

# ── RANGE 4: lines 393-414 — search_contacts() with @g.us exclusion ─────────

def search_contacts(query: str) -> List[Contact]:
    try:
        conn = sqlite3.connect(MESSAGES_DB_PATH)
        cursor = conn.cursor()

        # Split query into characters to support partial matching
        search_pattern = '%' +query + '%'

        cursor.execute("""
            SELECT DISTINCT
                jid,
                name
            FROM chats
            WHERE
                (LOWER(name) LIKE LOWER(?) OR LOWER(jid) LIKE LOWER(?))
                AND jid NOT LIKE '%@g.us'
            ORDER BY name, jid
            LIMIT 50
        """, (search_pattern, search_pattern))

        contacts = cursor.fetchall()
